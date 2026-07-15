//! Personal persistent memory -- durable facts/preferences about the user,
//! distinct from `memory.rs`'s session-only working memory. Persisted to
//! `<config dir>/noriter-ai/memory.json` and survives restarts. Injected
//! into every request (pinned entries first, then most recently updated),
//! and can also grow automatically: every 5th turn (per source), a short
//! extra Ollama call checks whether anything durable should be remembered.

use crate::ollama::{self, ChatMessage};
use crate::queue;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::AppHandle;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEntry {
    pub id: String,
    pub content: String,
    pub category: String, // hardware | preference | fact | instruction | other
    pub source: String,
    pub created_at: String,
    pub updated_at: String,
    pub confidence: String, // high | medium | low
    pub pinned: bool,
}

fn memory_path() -> PathBuf {
    let dir = dirs::config_dir().unwrap_or_else(std::env::temp_dir).join("noriter-ai");
    fs::create_dir_all(&dir).ok();
    dir.join("memory.json")
}

fn load_entries() -> Vec<MemoryEntry> {
    fs::read_to_string(memory_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_entries(entries: &[MemoryEntry]) {
    if let Ok(text) = serde_json::to_string_pretty(entries) {
        let _ = fs::write(memory_path(), text);
    }
}

fn now_iso() -> String {
    chrono::Local::now().to_rfc3339()
}

fn new_id() -> String {
    format!("mem_{}", chrono::Local::now().format("%Y%m%d%H%M%S%3f"))
}

pub struct PersonalMemoryState {
    entries: Mutex<Vec<MemoryEntry>>,
    // Per-source turn counter, throttling automatic extraction to roughly
    // every 5th turn so it doesn't double Ollama traffic on every message.
    turn_counts: Mutex<HashMap<String, u32>>,
}

impl Default for PersonalMemoryState {
    fn default() -> Self {
        Self {
            entries: Mutex::new(load_entries()),
            turn_counts: Mutex::new(HashMap::new()),
        }
    }
}

pub fn list(state: &PersonalMemoryState) -> Vec<MemoryEntry> {
    state.entries.lock().unwrap().clone()
}

pub fn add(state: &PersonalMemoryState, content: String, category: String, source: String, pinned: bool) -> MemoryEntry {
    let now = now_iso();
    let entry = MemoryEntry {
        id: new_id(),
        content,
        category,
        source,
        created_at: now.clone(),
        updated_at: now,
        confidence: "high".into(),
        pinned,
    };
    let mut entries = state.entries.lock().unwrap();
    entries.push(entry.clone());
    save_entries(&entries);
    entry
}

pub fn update(
    state: &PersonalMemoryState,
    id: &str,
    content: Option<String>,
    category: Option<String>,
    pinned: Option<bool>,
) -> Result<(), String> {
    let mut entries = state.entries.lock().unwrap();
    let Some(entry) = entries.iter_mut().find(|e| e.id == id) else {
        return Err("memory entry not found".into());
    };
    if let Some(c) = content {
        entry.content = c;
    }
    if let Some(c) = category {
        entry.category = c;
    }
    if let Some(p) = pinned {
        entry.pinned = p;
    }
    entry.updated_at = now_iso();
    save_entries(&entries);
    Ok(())
}

pub fn delete(state: &PersonalMemoryState, id: &str) {
    let mut entries = state.entries.lock().unwrap();
    entries.retain(|e| e.id != id);
    save_entries(&entries);
}

const MAX_CONTEXT_CHARS: usize = 2000;

/// Builds the context message injected at the front of every request --
/// pinned entries first, then most recently updated, capped so it can't
/// eat an unbounded share of the context window on its own.
pub fn context_message(state: &PersonalMemoryState) -> Option<ChatMessage> {
    let entries = state.entries.lock().unwrap();
    if entries.is_empty() {
        return None;
    }
    let mut sorted: Vec<&MemoryEntry> = entries.iter().collect();
    sorted.sort_by(|a, b| b.pinned.cmp(&a.pinned).then(b.updated_at.cmp(&a.updated_at)));

    let mut text = String::new();
    for entry in sorted {
        let line = format!("- {}\n", entry.content);
        if text.len() + line.len() > MAX_CONTEXT_CHARS {
            break;
        }
        text.push_str(&line);
    }
    if text.is_empty() {
        return None;
    }
    Some(ChatMessage::text("user", format!("(사용자에 대해 기억하고 있는 정보)\n{text}")))
}

/// Called once per completed turn. Throttled to roughly every 5th turn per
/// source (web, or a Telegram chat) so it doesn't double Ollama traffic on
/// every single message; asks the model to extract one durable fact (or
/// say NONE), storing it if it returned anything usable.
pub async fn maybe_extract(
    app: &AppHandle,
    state: &PersonalMemoryState,
    source: &str,
    model: &str,
    num_ctx: u32,
    user_text: &str,
    assistant_text: &str,
) {
    let should_run = {
        let mut counts = state.turn_counts.lock().unwrap();
        let count = counts.entry(source.to_string()).or_insert(0);
        *count += 1;
        *count % 5 == 0
    };
    if !should_run {
        return;
    }

    let prompt = format!(
        "다음은 최근 대화 내용입니다.\n사용자: {user_text}\n답변: {assistant_text}\n\n\
         이 대화에서 앞으로도 계속 참고할 만한, 사용자에 대한 새로운 사실이나 선호가 있다면 \
         한 문장으로만 답해줘 (예: '사용자는 GTX 1660 6GB VRAM 환경을 사용한다'). \
         새로 기억해둘 만한 게 없다면 정확히 NONE 이라고만 답해."
    );
    let messages = vec![ChatMessage::text("user", prompt)];
    let result = queue::run_queued(
        app,
        "memory-extract",
        "(개인 메모리 추출)".to_string(),
        ollama::chat(model, &messages, num_ctx),
    )
    .await;

    if let Ok(r) = result {
        let content = r.content.trim().to_string();
        if !content.is_empty() && !content.eq_ignore_ascii_case("none") && content.chars().count() < 300 {
            add(state, content, "fact".to_string(), source.to_string(), false);
        }
    }
}
