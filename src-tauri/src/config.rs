use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppConfig {
    pub telegram_bot_token: Option<String>,
    pub telegram_chat_id: Option<String>,
    pub telegram_enabled: bool,
    pub ollama_model: Option<String>,
    pub context_size: u32,
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
