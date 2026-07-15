use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

// `#[serde(default)]` on the struct matters: without it, any field missing
// from an on-disk config.json (e.g. one saved before a new field was added)
// makes the whole deserialize fail, and `load()` below silently falls back
// to `AppConfig::default()` -- discarding the user's saved token/model/etc,
// not just the new field. This was a latent bug before `attachment_prompt`
// was added; guarding it here so it doesn't bite again on the next field.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
pub struct AppConfig {
    pub telegram_bot_token: Option<String>,
    pub telegram_chat_id: Option<String>,
    pub telegram_enabled: bool,
    pub ollama_model: Option<String>,
    pub context_size: u32,
    /// Applied as the prompt when a Telegram photo/document arrives with no
    /// caption -- Telegram doesn't always let the user attach a caption
    /// (e.g. some clients' "send as file" flow), so without this the
    /// message would fall back to a generic "첨부된 파일을 확인해주세요."
    pub attachment_prompt: Option<String>,
}

fn config_path() -> PathBuf {
    let dir = dirs::config_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("noriter-ai");
    fs::create_dir_all(&dir).ok();
    dir.join("config.json")
}

pub fn load() -> AppConfig {
    let path = config_path();
    match fs::read_to_string(&path) {
        Ok(text) => serde_json::from_str(&text).unwrap_or_default(),
        Err(_) => AppConfig {
            context_size: 4096,
            ..Default::default()
        },
    }
}

pub fn save(cfg: &AppConfig) -> std::io::Result<()> {
    let path = config_path();
    let text = serde_json::to_string_pretty(cfg)?;
    fs::write(path, text)
}
