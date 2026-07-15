//! LLM wiki / encyclopedia -- user-curated documents (not auto-generated
//! every turn, per design: only explicit saves, to avoid noise). Persisted
//! to `<config dir>/noriter-ai/wiki/index.json`. Distinct from
//! `personal_memory.rs`: memory is "always injected", the wiki is "looked
//! up" -- entries are not automatically added to prompts.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WikiEntry {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub body: String,
    pub tags: Vec<String>,
    pub source: String,
    pub related_ids: Vec<String>,
    pub created_at: String,
    pub updated_at: String,
}

fn wiki_dir() -> PathBuf {
    let dir = dirs::config_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("noriter-ai")
        .join("wiki");
    fs::create_dir_all(&dir).ok();
    dir
}

fn index_path() -> PathBuf {
    wiki_dir().join("index.json")
}

fn load_entries() -> Vec<WikiEntry> {
    fs::read_to_string(index_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_entries(entries: &[WikiEntry]) {
    if let Ok(text) = serde_json::to_string_pretty(entries) {
        let _ = fs::write(index_path(), text);
    }
}

fn now_iso() -> String {
    chrono::Local::now().to_rfc3339()
}

fn new_id() -> String {
    format!("wiki_{}", chrono::Local::now().format("%Y%m%d%H%M%S%3f"))
}

pub struct WikiState(Mutex<Vec<WikiEntry>>);

impl Default for WikiState {
    fn default() -> Self {
        Self(Mutex::new(load_entries()))
    }
}

pub fn list(state: &WikiState) -> Vec<WikiEntry> {
    state.0.lock().unwrap().clone()
}

#[allow(clippy::too_many_arguments)]
pub fn save(
    state: &WikiState,
    title: String,
    summary: String,
    body: String,
    tags: Vec<String>,
    source: String,
    related_ids: Vec<String>,
) -> WikiEntry {
    let now = now_iso();
    let entry = WikiEntry {
        id: new_id(),
        title,
        summary,
        body,
        tags,
        source,
        related_ids,
        created_at: now.clone(),
        updated_at: now,
    };
    let mut entries = state.0.lock().unwrap();
    entries.push(entry.clone());
    save_entries(&entries);
    entry
}

pub fn update(
    state: &WikiState,
    id: &str,
    title: Option<String>,
    summary: Option<String>,
    body: Option<String>,
    tags: Option<Vec<String>>,
) -> Result<(), String> {
    let mut entries = state.0.lock().unwrap();
    let Some(entry) = entries.iter_mut().find(|e| e.id == id) else {
        return Err("wiki entry not found".into());
    };
    if let Some(v) = title {
        entry.title = v;
    }
    if let Some(v) = summary {
        entry.summary = v;
    }
    if let Some(v) = body {
        entry.body = v;
    }
    if let Some(v) = tags {
        entry.tags = v;
    }
    entry.updated_at = now_iso();
    save_entries(&entries);
    Ok(())
}

pub fn delete(state: &WikiState, id: &str) {
    let mut entries = state.0.lock().unwrap();
    entries.retain(|e| e.id != id);
    save_entries(&entries);
}
