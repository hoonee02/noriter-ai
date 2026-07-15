#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod config;
mod ollama;
mod queue;
mod telegram;

use config::AppConfig;
use queue::QueueState;
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
}

#[tauri::command]
async fn ollama_chat(app: AppHandle, model: String, prompt: String, num_ctx: u32) -> Result<ChatReply, String> {
    let preview: String = prompt.chars().take(60).collect();
    let messages = vec![ollama::ChatMessage {
        role: "user".into(),
        content: prompt,
    }];
    queue::run_queued(&app, "web", preview, ollama::chat(&model, &messages, num_ctx))
        .await
        .map(|r| ChatReply {
            content: r.content,
            tokens_used: r.tokens_used,
            elapsed_ms: r.elapsed_ms,
        })
        .map_err(|e| e.to_string())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(TelegramState::default())
        .manage(QueueState::default())
        .invoke_handler(tauri::generate_handler![
            load_config,
            save_config,
            start_telegram,
            ollama_status,
            ollama_models,
            ollama_running_models,
            ollama_chat,
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
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .on_window_event(|window, event| {
            // Close ([X]) hides instead of quitting so the Telegram bridge
            // (spawned once in setup, independent of the window) keeps running.
            if let WindowEvent::CloseRequested { api, .. } = event {
                window.hide().ok();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running noriter-ai");
}
