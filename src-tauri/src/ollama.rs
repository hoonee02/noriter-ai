use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Instant;

const BASE_URL: &str = "http://127.0.0.1:11434";

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
    /// Base64-encoded image bytes (no data-URL prefix) -- Ollama's own
    /// multimodal format, distinct from OpenAI's content-parts array.
    /// Requires a vision-capable model; Ollama returns an error otherwise,
    /// which surfaces to the user as-is (no capability pre-check yet).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub images: Option<Vec<String>>,
}

impl ChatMessage {
    pub fn text(role: impl Into<String>, content: impl Into<String>) -> Self {
        Self { role: role.into(), content: content.into(), images: None }
    }
}

#[derive(Debug, Serialize, Clone)]
pub struct ChatResult {
    pub content: String,
    /// Ollama's `eval_count` (tokens generated), when the server reports it.
    pub tokens_used: Option<u64>,
    /// Wall-clock time for the whole request, measured on our side so it's
    /// always available even if Ollama's own duration fields are absent.
    pub elapsed_ms: u64,
}

/// Non-streaming chat completion against the local Ollama server.
/// Streaming (token-by-token) is left as a follow-up: reqwest's `bytes_stream`
/// over `/api/chat` with `stream: true`, forwarded to the frontend via a
/// Tauri event per chunk instead of returning one final string.
pub async fn chat(model: &str, messages: &[ChatMessage], num_ctx: u32) -> anyhow::Result<ChatResult> {
    let started = Instant::now();
    let client = reqwest::Client::new();
    let body = json!({
        "model": model,
        "messages": messages,
        "stream": false,
        "options": { "num_ctx": num_ctx }
    });

    let resp = client
        .post(format!("{BASE_URL}/api/chat"))
        .json(&body)
        .send()
        .await?
        .error_for_status()?;

    let value: serde_json::Value = resp.json().await?;
    let content = value["message"]["content"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    let tokens_used = value["eval_count"].as_u64();

    Ok(ChatResult {
        content,
        tokens_used,
        elapsed_ms: started.elapsed().as_millis() as u64,
    })
}

pub async fn is_running() -> bool {
    reqwest::Client::new()
        .get(format!("{BASE_URL}/api/tags"))
        .send()
        .await
        .is_ok()
}

pub async fn list_models() -> anyhow::Result<Vec<String>> {
    let resp: serde_json::Value = reqwest::get(format!("{BASE_URL}/api/tags"))
        .await?
        .json()
        .await?;
    let names = resp["models"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|m| m["name"].as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    Ok(names)
}

/// Models currently loaded into memory (Ollama's `/api/ps`) -- distinct
/// from `list_models`, which only reports what's been pulled to disk. A
/// model can be installed but not actually running/loaded yet.
pub async fn running_models() -> anyhow::Result<Vec<String>> {
    let resp: serde_json::Value = reqwest::get(format!("{BASE_URL}/api/ps"))
        .await?
        .json()
        .await?;
    let names = resp["models"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|m| m["name"].as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    Ok(names)
}
