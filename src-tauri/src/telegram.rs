use crate::config;
use crate::ollama::{self, ChatMessage};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter};
use teloxide::{prelude::*, types::Message};

// Telegram's hard limit on a single sendMessage's text is 4096 chars; stay
// a little under it the same way the old Dart bridge did.
const MAX_REPLY_CHARS: usize = 3900;

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
/// answered, and messages from bot accounts are ignored entirely.
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

            let Some(text) = msg.text() else {
                return Ok(());
            };

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
                    let messages = vec![ChatMessage {
                        role: "user".into(),
                        content: text.to_string(),
                    }];
                    let preview: String = text.chars().take(60).collect();
                    match crate::queue::run_queued(
                        &app,
                        "telegram",
                        preview,
                        ollama::chat(model, &messages, num_ctx),
                    )
                    .await
                    {
                        Ok(r) => (r.content, r.tokens_used, r.elapsed_ms),
                        Err(e) => (format!("(error contacting local model: {e})"), None, 0),
                    }
                }
            };
            // Echo the original prompt back above the generated reply so the
            // conversation reads clearly even when messages arrive out of
            // order or after a delay.
            let outgoing = format!("> {text}\n\n{reply}");
            let outgoing = if outgoing.chars().count() > MAX_REPLY_CHARS {
                let truncated: String = outgoing.chars().take(MAX_REPLY_CHARS).collect();
                format!("{truncated}\n\n(Truncated)")
            } else {
                outgoing
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
