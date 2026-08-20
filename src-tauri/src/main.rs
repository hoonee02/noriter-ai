#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod attachment;
mod chairman;
mod config;
mod dart;
mod memory;
mod ollama;
mod personal_memory;
mod power;
mod preflight;
mod queue;
mod telegram;
mod wiki;

use config::AppConfig;
use dart::DartState;
use memory::MemoryState;
use personal_memory::{MemoryEntry, PersonalMemoryState};
use queue::QueueState;
use wiki::{DraftState, WikiEntry, WikiState};
use serde::Serialize;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Manager, State, WindowEvent,
};

/// Guards against spawning a second Telegram long-poll loop when the user
/// re-saves settings while the bridge is already running -- teloxide's
/// `getUpdates` polling isn't safe to run twice against the same bot token.
#[derive(Default)]
struct TelegramState(AtomicBool);

#[tauri::command]
fn load_config() -> AppConfig {
    config::load()
}

#[tauri::command]
fn save_config(cfg: AppConfig) -> Result<(), String> {
    config::save(&cfg).map_err(|e| e.to_string())
}

/// Starts the Telegram bridge from whatever is currently saved in config.
/// Safe to call repeatedly (e.g. right after `save_config`): no-ops if a
/// bridge is already running or the config isn't complete enough to start.
#[tauri::command]
fn start_telegram(app: AppHandle, state: State<TelegramState>) -> Result<bool, String> {
    if state.0.swap(true, Ordering::SeqCst) {
        return Ok(false); // already running
    }
    let cfg = config::load();
    if !cfg.telegram_enabled {
        state.0.store(false, Ordering::SeqCst);
        return Ok(false);
    }
    let Some(token) = cfg.telegram_bot_token else {
        state.0.store(false, Ordering::SeqCst);
        return Err("telegram_bot_token must be set".into());
    };
    // No model chosen yet is fine -- the bridge still starts and listens;
    // see telegram::run, which replies with setup guidance instead of
    // calling Ollama until a model is picked in the Model panel.
    tauri::async_runtime::spawn(async move {
        telegram::run(app, token, cfg.ollama_model, cfg.context_size).await;
    });
    Ok(true)
}

#[tauri::command]
async fn ollama_status() -> bool {
    ollama::is_running().await
}

#[tauri::command]
async fn ollama_models() -> Result<Vec<String>, String> {
    ollama::list_models().await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn ollama_running_models() -> Result<Vec<String>, String> {
    ollama::running_models().await.map_err(|e| e.to_string())
}

#[derive(Serialize)]
struct ChatReply {
    content: String,
    tokens_used: Option<u64>,
    elapsed_ms: u64,
    /// Which route the chairman picked, so the UI can say what it did with
    /// the message ("위키에 정리했습니다") instead of leaving the user to
    /// guess why a reply looks different.
    routed_as: String,
}

/// The single entry point for anything the user types.
///
/// 0.1.6: the wiki's separate input boxes are gone. The chairman classifies
/// the message (§2.4) and the matching path runs -- a question against the
/// wiki, material to file into it, or ordinary conversation. Deciding which
/// is the agent's job, not something to make the user pick from a UI.
#[tauri::command]
async fn ollama_chat(
    app: AppHandle,
    memory: State<'_, MemoryState>,
    personal_memory: State<'_, PersonalMemoryState>,
    wiki_state: State<'_, WikiState>,
    draft: State<'_, DraftState>,
    model: String,
    prompt: String,
    num_ctx: u32,
    files: Option<Vec<attachment::UploadedFile>>,
) -> Result<ChatReply, String> {
    let started = std::time::Instant::now();
    let files = files.unwrap_or_default();

    // Images go to the model as images; everything else is flattened into
    // text and appended to the prompt (same rules as the Telegram bridge).
    let mut images: Vec<String> = Vec::new();
    let mut attachment_text = String::new();
    for f in &files {
        if f.is_image() {
            images.push(f.data.clone());
        } else {
            attachment_text.push_str("\n\n");
            attachment_text.push_str(&attachment::compose_attachment_text(&f.name, &f.decode()));
        }
    }

    let file_names: Vec<String> = files.iter().map(|f| f.name.clone()).collect();
    let full_prompt = format!("{prompt}{attachment_text}");

    let intent = chairman::decide_intent(&app, &model, num_ctx, &prompt, &file_names).await;

    match intent {
        chairman::Intent::WikiQuery => {
            // Company scope comes out of the sentence itself (§8.2.3), so
            // there is nothing extra for the user to set.
            let entries = wiki::list(&wiki_state);
            let scope = preflight::match_known_company(&entries, &prompt).map(|c| c.corp_code);
            // The wiki path is part of the same conversation now, so it gets
            // the same remembered turns -- a follow-up like "그 날짜는?" is
            // meaningless without them.
            let history =
                memory::history_messages(&app, &memory, "web", &model, num_ctx).await;
            let answer = wiki::query(
                &app,
                &wiki_state,
                &draft,
                &model,
                num_ctx,
                &full_prompt,
                scope.as_deref(),
                &history,
            )
            .await?;
            // Recorded like any other turn, or the next message would have a
            // hole where this exchange was.
            memory::record_turn(&memory, "web", &prompt, &answer);
            return Ok(ChatReply {
                content: answer,
                tokens_used: None,
                elapsed_ms: started.elapsed().as_millis() as u64,
                routed_as: "wiki-query".into(),
            });
        }
        chairman::Intent::WikiIngest => {
            let label = if file_names.is_empty() {
                "붙여넣은 자료".to_string()
            } else {
                file_names.join(", ")
            };
            let entry = wiki::ingest(&app, &wiki_state, &model, num_ctx, &full_prompt, &label).await?;
            let content = format!(
                "위키에 정리했습니다: **{}**\n\n{}",
                entry.canonical_title(),
                entry.summary
            );
            // Recorded like any other turn, so a later question can refer
            // back to what was just filed.
            memory::record_turn(&memory, "web", &prompt, &content);
            return Ok(ChatReply {
                content,
                tokens_used: None,
                elapsed_ms: started.elapsed().as_millis() as u64,
                routed_as: "wiki-ingest".into(),
            });
        }
        chairman::Intent::Chat => {}
    }

    let preview: String = prompt.chars().take(60).collect();

    let mut messages = Vec::new();
    if let Some(pm) = personal_memory::context_message(&personal_memory) {
        messages.push(pm);
    }
    let images_opt = if images.is_empty() { None } else { Some(images) };
    messages.extend(
        memory::build_messages(&app, &memory, "web", &model, num_ctx, &full_prompt, images_opt).await,
    );

    let result = queue::call_llm(&app, "web", preview, &model, &messages, num_ctx).await?;

    memory::record_turn(&memory, "web", &prompt, &result.content);

    // Fire-and-forget: occasionally extracts a durable fact about the user
    // in the background so it never adds latency to the reply itself.
    {
        let app2 = app.clone();
        let model2 = model.clone();
        let prompt2 = prompt.clone();
        let content2 = result.content.clone();
        tauri::async_runtime::spawn(async move {
            let pm_state = app2.state::<PersonalMemoryState>();
            personal_memory::maybe_extract(&app2, &pm_state, "web", &model2, num_ctx, &prompt2, &content2).await;
        });
    }

    Ok(ChatReply {
        content: result.content,
        tokens_used: result.tokens_used,
        elapsed_ms: result.elapsed_ms,
        routed_as: "chat".into(),
    })
}

#[tauri::command]
fn personal_memory_list(state: State<PersonalMemoryState>) -> Vec<MemoryEntry> {
    personal_memory::list(&state)
}

#[tauri::command]
fn personal_memory_add(state: State<PersonalMemoryState>, content: String, category: String, pinned: bool) -> MemoryEntry {
    personal_memory::add(&state, content, category, "manual".to_string(), pinned)
}

#[tauri::command]
fn personal_memory_update(
    state: State<PersonalMemoryState>,
    id: String,
    content: Option<String>,
    category: Option<String>,
    pinned: Option<bool>,
) -> Result<(), String> {
    personal_memory::update(&state, &id, content, category, pinned)
}

#[tauri::command]
fn personal_memory_delete(state: State<PersonalMemoryState>, id: String) {
    personal_memory::delete(&state, &id)
}

#[tauri::command]
fn wiki_list(state: State<WikiState>) -> Vec<wiki::WikiEntryView> {
    wiki::list_view(&state)
}

// 0.1.6 removed `wiki_save` and `wiki_ingest` as separate commands: pages are
// now created only by routing a prompt (`ollama_chat`). Asking the user to
// type a title, summary, tags, company and period by hand was the agents'
// work pushed onto the person -- Taxonomy decides the company (§4.1.2),
// ingest writes the structure, and O-22 assigns `body_required`.

#[tauri::command]
fn wiki_delete(state: State<WikiState>, id: String) {
    wiki::delete(&state, &id)
}

/// D-03: unpromoted answers, for the review UI. Kept separate from
/// `wiki_list` so a caller can't accidentally feed drafts back as context.
#[tauri::command]
fn wiki_draft_list(draft: State<DraftState>) -> Vec<wiki::WikiEntryView> {
    wiki::list_draft_view(&draft)
}

#[tauri::command]
fn wiki_promote(
    draft: State<DraftState>,
    state: State<WikiState>,
    id: String,
) -> Result<WikiEntry, String> {
    wiki::promote(&draft, &state, &id)
}

#[tauri::command]
fn wiki_discard_draft(draft: State<DraftState>, id: String) {
    wiki::discard_draft(&draft, &id)
}

#[tauri::command]
async fn wiki_lint(
    app: AppHandle,
    state: State<'_, WikiState>,
    model: String,
    num_ctx: u32,
) -> Result<String, String> {
    // Lint is deliberately unscoped: it looks for contradictions *across* the
    // wiki, which is exactly the comparison a company filter would prevent.
    // Each line carries its company so the model can still tell two firms'
    // figures apart (D-14).
    wiki::lint(&app, &state, &model, num_ctx, None).await
}

#[tauri::command]
fn wiki_log_tail(lines: usize) -> Vec<String> {
    wiki::log_tail(lines)
}

/// How many companies the local DART cache holds -- 0 means "never fetched",
/// which is what the settings panel shows the user.
#[tauri::command]
fn dart_corp_count(state: State<DartState>) -> usize {
    state.count()
}

#[tauri::command]
async fn dart_refresh_corp_codes(state: State<'_, DartState>) -> Result<usize, String> {
    let Some(key) = config::load().opendart_api_key.filter(|k| !k.trim().is_empty()) else {
        return Err("OpenDART API 키가 설정되지 않았습니다 (⚙ 설정에서 입력)".into());
    };
    dart::refresh_corp_codes(&state, &key).await
}

/// Name -> canonical company reference. `None` when the cache has no match
/// or the name is ambiguous; the caller then stores no company scope rather
/// than a guessed one.
#[tauri::command]
fn dart_lookup_company(state: State<DartState>, name: String) -> Option<wiki::CompanyRef> {
    dart::lookup(&state, &name)
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(TelegramState::default())
        .manage(QueueState::default())
        .manage(MemoryState::default())
        .manage(PersonalMemoryState::default())
        .manage(WikiState::default())
        .manage(DraftState::default())
        .manage(DartState::loaded())
        .invoke_handler(tauri::generate_handler![
            load_config,
            save_config,
            start_telegram,
            ollama_status,
            ollama_models,
            ollama_running_models,
            ollama_chat,
            personal_memory_list,
            personal_memory_add,
            personal_memory_update,
            personal_memory_delete,
            wiki_list,
            wiki_delete,
            wiki_lint,
            wiki_log_tail,
            wiki_draft_list,
            wiki_promote,
            wiki_discard_draft,
            dart_corp_count,
            dart_refresh_corp_codes,
            dart_lookup_company,
        ])
        .setup(|app| {
            // Always-on Telegram bridge: started once at launch (if already
            // configured), keeps running regardless of window visibility
            // (requirement 2.1). Also callable on demand via `start_telegram`
            // right after the user saves settings in the UI.
            let app_handle = app.handle().clone();
            let cfg = config::load();
            if cfg.telegram_enabled {
                if let Some(token) = cfg.telegram_bot_token.clone() {
                    let state: State<TelegramState> = app.state();
                    state.0.store(true, Ordering::SeqCst);
                    let model = cfg.ollama_model.clone();
                    let context_size = cfg.context_size;
                    tauri::async_runtime::spawn(async move {
                        telegram::run(app_handle, token, model, context_size).await;
                    });
                }
            }

            // System tray: double-click / "열기" restores the window instead
            // of the app ever fully quitting on close (requirement 2.2).
            let show_item = MenuItem::with_id(app, "show", "열기", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "종료", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_item, &quit_item])?;

            TrayIconBuilder::new()
                .icon(app.default_window_icon().cloned().expect("bundled icon"))
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(win) = app.get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.set_focus();
                            power::set_background(false);
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let tauri::tray::TrayIconEvent::DoubleClick { .. } = event {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.set_focus();
                            power::set_background(false);
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .on_window_event(|window, event| {
            // Close ([X]) hides instead of quitting so the Telegram bridge
            // (spawned once in setup, independent of the window) keeps running.
            // Also drops process priority to IDLE while hidden -- nothing
            // running in the background (Telegram poll, an in-flight Ollama
            // request) needs to compete with foreground apps for CPU.
            if let WindowEvent::CloseRequested { api, .. } = event {
                window.hide().ok();
                api.prevent_close();
                power::set_background(true);
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running noriter-ai");
}
