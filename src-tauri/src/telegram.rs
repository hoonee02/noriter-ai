use crate::config;
use crate::memory::MemoryState;
use crate::ollama;
use base64::Engine;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager};
use teloxide::{net::Download, prelude::*, types::Message};

// Telegram's hard limit on a single sendMessage's text is 4096 chars; stay
// a little under it the same way the old Dart bridge did.
const MAX_REPLY_CHARS: usize = 3900;
// Same truncation the old Dart bridge applied to document text before
// embedding it in the prompt, to avoid blowing a small model's context.
const MAX_ATTACHMENT_CHARS: usize = 8000;
// The echoed prompt preview above the reply is capped short and separate
// from MAX_ATTACHMENT_CHARS: an attachment's full extracted text can be
// thousands of chars (goes to Ollama as the prompt, never sent back to
// Telegram as-is) -- echoing it in full would eat the entire MAX_REPLY_CHARS
// budget and truncate the *actual generated reply* clean off the message
// (this happened in practice with an .xlsx attachment, see BUGFIXES.md).
const MAX_ECHO_CHARS: usize = 200;

/// Runs the Telegram long-poll loop for the lifetime of the process --
/// independent of window visibility. When the window is open, incoming
/// messages/replies are also emitted to the frontend via `telegram-event`
/// so the Dart Wasm UI can mirror them; when hidden, this loop still calls
/// Ollama directly and replies, with no frontend involved.
///
/// Ported from the old `dart_platform/lib/src/telegram_bridge.dart`: no chat
/// ID configured yet auto-binds to whichever chat sends the first message
/// (typical for a single-user personal bot) and persists it to config;
/// once bound, messages from any other chat are ignored rather than
/// answered, and messages from bot accounts are ignored entirely. Photo and
/// document attachments are downloaded and embedded the same way the old
/// bridge did (photos as Ollama multimodal `images`, documents as
/// extracted/decoded text appended to the prompt).
pub async fn run(app: AppHandle, bot_token: String, model: Option<String>, num_ctx: u32) {
    let bot = Bot::new(bot_token);

    let initial_chat_id = config::load().telegram_chat_id.and_then(|s| s.parse::<i64>().ok());
    let allowed_chat_id: Arc<Mutex<Option<i64>>> = Arc::new(Mutex::new(initial_chat_id));

    teloxide::repl(bot, move |bot: Bot, msg: Message| {
        let app = app.clone();
        let model = model.clone();
        let allowed_chat_id = allowed_chat_id.clone();
        async move {
            if msg.from.as_ref().is_some_and(|u| u.is_bot) {
                return Ok(());
            }

            let raw_text = msg.text().or_else(|| msg.caption()).unwrap_or("").to_string();
            let has_photo = msg.photo().is_some_and(|p| !p.is_empty());
            let has_document = msg.document().is_some();
            if !has_photo && !has_document && raw_text.trim().is_empty() {
                return Ok(());
            }

            let chat_id = msg.chat.id.0;
            {
                let mut allowed = allowed_chat_id.lock().unwrap();
                match *allowed {
                    None => {
                        *allowed = Some(chat_id);
                        let mut cfg = config::load();
                        cfg.telegram_chat_id = Some(chat_id.to_string());
                        let _ = config::save(&cfg);
                    }
                    Some(id) if id != chat_id => return Ok(()),
                    _ => {}
                }
            }

            // Photos arrive as multiple resolutions of the same image
            // ("PhotoSize"); the last entry is the largest.
            let mut images: Vec<String> = Vec::new();
            if let Some(sizes) = msg.photo() {
                if let Some(largest) = sizes.last() {
                    match download_file(&bot, &largest.file.id).await {
                        Ok(bytes) => images.push(base64::engine::general_purpose::STANDARD.encode(bytes)),
                        Err(e) => eprintln!("telegram: failed to download photo: {e}"),
                    }
                }
            }

            let mut attachment_text: Option<String> = None;
            if let Some(doc) = msg.document() {
                let file_name = doc.file_name.clone().unwrap_or_else(|| "file".to_string());
                match download_file(&bot, &doc.file.id).await {
                    Ok(bytes) => attachment_text = Some(compose_attachment_text(&file_name, &bytes)),
                    Err(e) => eprintln!("telegram: failed to download document: {e}"),
                }
            }

            // Telegram doesn't always let the sender attach a caption (e.g.
            // some "send as file" flows), so a caption-less attachment
            // falls back to the user's configured default instruction
            // instead of a generic placeholder.
            let default_prompt = config::load()
                .attachment_prompt
                .filter(|p| !p.trim().is_empty())
                .unwrap_or_else(|| "첨부된 내용을 확인하고 설명해주세요.".to_string());

            let mut text = raw_text.trim().to_string();
            if let Some(attachment) = &attachment_text {
                text = if text.is_empty() {
                    format!("{default_prompt}\n\n{attachment}")
                } else {
                    format!("{text}\n\n{attachment}")
                };
            } else if text.is_empty() && !images.is_empty() {
                text = default_prompt;
            }
            if text.is_empty() {
                return Ok(());
            }

            let _ = app.emit(
                "telegram-event",
                serde_json::json!({ "type": "incoming", "text": text }),
            );

            let (reply, tokens_used, elapsed_ms) = match &model {
                None => (
                    "아직 사용할 모델이 설정되지 않았습니다. 앱의 🧠 모델 패널에서 \
                     모델을 선택하고 저장한 뒤 다시 메시지를 보내주세요."
                        .to_string(),
                    None,
                    0,
                ),
                Some(model) => {
                    let memory_key = format!("telegram:{chat_id}");
                    let memory = app.state::<MemoryState>();
                    let personal_memory = app.state::<crate::personal_memory::PersonalMemoryState>();
                    let images_opt = if images.is_empty() { None } else { Some(images) };

                    let mut messages = Vec::new();
                    if let Some(pm) = crate::personal_memory::context_message(&personal_memory) {
                        messages.push(pm);
                    }
                    messages.extend(
                        crate::memory::build_messages(
                            &app,
                            &memory,
                            &memory_key,
                            model,
                            num_ctx,
                            &text,
                            images_opt,
                        )
                        .await,
                    );

                    let preview: String = text.chars().take(60).collect();
                    let result = crate::queue::run_queued(
                        &app,
                        "telegram",
                        preview,
                        ollama::chat(model, &messages, num_ctx),
                    )
                    .await;

                    match result {
                        Ok(r) => {
                            crate::memory::record_turn(&memory, &memory_key, &text, &r.content);

                            let app2 = app.clone();
                            let model2 = model.clone();
                            let text2 = text.clone();
                            let content2 = r.content.clone();
                            let memory_key2 = memory_key.clone();
                            tauri::async_runtime::spawn(async move {
                                let pm_state =
                                    app2.state::<crate::personal_memory::PersonalMemoryState>();
                                crate::personal_memory::maybe_extract(
                                    &app2,
                                    &pm_state,
                                    &memory_key2,
                                    &model2,
                                    num_ctx,
                                    &text2,
                                    &content2,
                                )
                                .await;
                            });

                            (r.content, r.tokens_used, r.elapsed_ms)
                        }
                        Err(e) => (format!("(error contacting local model: {e})"), None, 0),
                    }
                }
            };
            // Echo a short preview of the prompt above the generated reply
            // so the conversation reads clearly even when messages arrive
            // out of order or after a delay. Deliberately NOT the full
            // `text` sent to Ollama -- that can contain an entire
            // attachment's extracted content (thousands of chars), and
            // echoing it in full would eat the whole MAX_REPLY_CHARS budget
            // and truncate the actual reply away entirely.
            let echo = match (attachment_text.is_some(), raw_text.trim()) {
                (true, "") => "[첨부파일]".to_string(),
                (true, caption) => format!("[첨부파일] {caption}"),
                (false, caption) => caption.to_string(),
            };
            let echo: String = if echo.chars().count() > MAX_ECHO_CHARS {
                let truncated: String = echo.chars().take(MAX_ECHO_CHARS).collect();
                format!("{truncated}...")
            } else {
                echo
            };

            // The reply itself always takes priority: only the echo portion
            // (bounded to MAX_ECHO_CHARS above) is ever at risk of pushing
            // the combined message over Telegram's limit, so it's safe to
            // truncate the reply on its own budget rather than truncating
            // the whole combined string and risking cutting the reply off.
            let reply_budget = MAX_REPLY_CHARS.saturating_sub(echo.chars().count() + 10);
            let reply_for_send = if reply.chars().count() > reply_budget {
                let truncated: String = reply.chars().take(reply_budget).collect();
                format!("{truncated}\n\n(Truncated)")
            } else {
                reply.clone()
            };
            let outgoing = if echo.is_empty() {
                reply_for_send
            } else {
                format!("> {echo}\n\n{reply_for_send}")
            };

            bot.send_message(msg.chat.id, &outgoing).await?;

            let _ = app.emit(
                "telegram-event",
                serde_json::json!({
                    "type": "reply",
                    "text": reply,
                    "tokensUsed": tokens_used,
                    "elapsedMs": elapsed_ms,
                }),
            );

            Ok(())
        }
    })
    .await;
}

/// Downloads a Telegram file (photo or document) by its file_id via
/// getFile + the file download endpoint.
async fn download_file(bot: &Bot, file_id: &str) -> anyhow::Result<Vec<u8>> {
    let file = bot.get_file(file_id).await?;
    let mut buf: Vec<u8> = Vec::new();
    bot.download_file(&file.path, &mut buf).await?;
    Ok(buf)
}

/// Converts a downloaded document into the same "[Attached file: ...]" text
/// block the old Dart bridge used -- .xlsx is parsed into a plain-text
/// table (one section per sheet, pipe-separated cells) via `calamine`,
/// everything else is decoded as UTF-8 (lossy). Truncated at
/// `MAX_ATTACHMENT_CHARS` to avoid blowing a small model's context window.
fn compose_attachment_text(file_name: &str, bytes: &[u8]) -> String {
    let ext = file_name.rsplit('.').next().unwrap_or("").to_lowercase();
    let content = if ext == "xlsx" {
        xlsx_bytes_to_text(bytes).unwrap_or_else(|e| format!("(failed to parse spreadsheet: {e})"))
    } else {
        String::from_utf8_lossy(bytes).to_string()
    };

    let truncated = content.chars().count() > MAX_ATTACHMENT_CHARS;
    let body: String = content.chars().take(MAX_ATTACHMENT_CHARS).collect();
    let notice = if truncated {
        format!("\n\n(File truncated to {MAX_ATTACHMENT_CHARS} characters)")
    } else {
        String::new()
    };
    format!("[Attached file: {file_name}]\n```\n{body}\n```{notice}")
}

fn xlsx_bytes_to_text(bytes: &[u8]) -> anyhow::Result<String> {
    use calamine::{Reader, Xlsx};
    let cursor = std::io::Cursor::new(bytes);
    let mut workbook: Xlsx<_> = calamine::open_workbook_from_rs(cursor)?;

    let mut out = String::new();
    for sheet_name in workbook.sheet_names().to_vec() {
        let Ok(range) = workbook.worksheet_range(&sheet_name) else {
            continue;
        };
        out.push_str(&format!("--- {sheet_name} ---\n"));
        for row in range.rows() {
            let cells: Vec<String> = row.iter().map(|c| c.to_string()).collect();
            out.push_str(&cells.join(" | "));
            out.push('\n');
        }
        out.push('\n');
    }
    Ok(out)
}
