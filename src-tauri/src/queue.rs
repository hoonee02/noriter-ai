use crate::ollama::{self, ChatMessage, ChatResult};
use serde::Serialize;
use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::{AppHandle, Emitter, Manager};

#[derive(Clone, Serialize)]
pub struct QueueItem {
    pub id: u64,
    pub preview: String,
    pub source: String, // "web" | "telegram"
    pub status: String, // "waiting" | "running"
}

#[derive(Default)]
pub struct QueueState {
    items: Mutex<Vec<QueueItem>>,
    // Serializes generation requests from both surfaces through one FIFO so
    // web chat and the Telegram bridge never call Ollama concurrently.
    run_lock: tokio::sync::Mutex<()>,
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn broadcast(app: &AppHandle, state: &QueueState) {
    let items = state.items.lock().unwrap().clone();
    println!("queue broadcast: {} item(s)", items.len());
    match app.emit("queue-update", serde_json::json!({ "items": items })) {
        Ok(()) => println!("queue broadcast: emit ok"),
        Err(e) => eprintln!("queue broadcast: emit FAILED: {e}"),
    }
}

/// Runs `work` through the shared generation queue: registers a "waiting"
/// entry, broadcasts `queue-update` (so the UI's 📋 큐 panel can render it
/// live for both web chat and Telegram requests), waits its turn, flips to
/// "running", runs the future, then removes the entry and broadcasts again.
/// Mirrors the old Dart server's `_runQueued()` FIFO.
///
/// D-01: private on purpose -- `run_lock` is not re-entrant, so a
/// coordinating function that ran itself through the queue and then called
/// a sub-agent doing the same would deadlock forever. Keeping this `fn`
/// (not `pub fn`) makes `call_llm` below the only possible entry, ruling
/// the re-entrancy out by structure instead of by convention.
async fn run_queued<T, F>(app: &AppHandle, source: &str, preview: String, work: F) -> T
where
    F: Future<Output = T>,
{
    let state = app.state::<QueueState>();
    let id = NEXT_ID.fetch_add(1, Ordering::SeqCst);

    {
        let mut items = state.items.lock().unwrap();
        items.push(QueueItem {
            id,
            preview,
            source: source.to_string(),
            status: "waiting".into(),
        });
    }
    broadcast(app, &state);

    let _guard = state.run_lock.lock().await;

    {
        let mut items = state.items.lock().unwrap();
        if let Some(item) = items.iter_mut().find(|i| i.id == id) {
            item.status = "running".into();
        }
    }
    broadcast(app, &state);

    let result = work.await;

    {
        let mut items = state.items.lock().unwrap();
        items.retain(|i| i.id != id);
    }
    broadcast(app, &state);

    result
}

/// D-01: the one function in the whole system that goes through the
/// generation queue. Every module calls this instead of `ollama::chat` --
/// the queue gates exactly one thing ("never call Ollama twice at once"),
/// so only the actual leaf LLM call belongs inside it. Coordinating
/// functions stay outside the queue and simply await their leaves.
pub async fn call_llm(
    app: &AppHandle,
    source: &str, // queue-panel label: "web", "telegram", "wiki-query", ...
    preview: String,
    model: &str,
    messages: &[ChatMessage],
    num_ctx: u32,
) -> Result<ChatResult, String> {
    run_queued(app, source, preview, ollama::chat(model, messages, num_ctx))
        .await
        .map_err(|e| e.to_string())
}
