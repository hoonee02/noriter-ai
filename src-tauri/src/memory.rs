//! Session-only conversation working memory. Not persisted to disk --
//! cleared on restart (chat history *persistence* was explicitly ruled
//! out; this is just enough memory to keep a topic coherent turn-to-turn
//! while the app is running).
//!
//! Policy (fixed, per user decision -- not configurable):
//!   - last 3 turns kept verbatim
//!   - turns 4-8 back are compressed into one short summary (regenerated
//!     via an extra Ollama call whenever the window shifts)
//!   - anything older than 8 turns back is simply dropped, unsummarized
//!
//! Attachment content (image bytes, extracted file text) is never
//! re-sent in later turns: only the plain prompt text is remembered, so a
//! multi-turn conversation about a file/image stays coherent without the
//! payload growing every turn.

use crate::ollama::{self, ChatMessage};
use crate::queue;
use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;
use tauri::AppHandle;

const RECENT_TURNS: usize = 3;
const TOTAL_TURNS: usize = 8; // RECENT_TURNS + summarized-window size

#[derive(Clone)]
struct Turn {
    user: String,
    assistant: String,
}

#[derive(Default)]
struct ConversationMemory {
    turns: VecDeque<Turn>,
}

impl ConversationMemory {
    fn record(&mut self, user: String, assistant: String) {
        self.turns.push_back(Turn { user, assistant });
        while self.turns.len() > TOTAL_TURNS {
            self.turns.pop_front();
        }
    }

    /// Turns older than the most recent `RECENT_TURNS`, but still within
    /// the `TOTAL_TURNS` window -- these get summarized, not sent verbatim.
    fn middle_turns(&self) -> Vec<Turn> {
        let len = self.turns.len();
        if len <= RECENT_TURNS {
            return Vec::new();
        }
        self.turns.iter().take(len - RECENT_TURNS).cloned().collect()
    }

    fn recent_turns(&self) -> Vec<Turn> {
        let len = self.turns.len();
        let start = len.saturating_sub(RECENT_TURNS);
        self.turns.iter().skip(start).cloned().collect()
    }
}

#[derive(Default)]
pub struct MemoryState(Mutex<HashMap<String, ConversationMemory>>);

/// Builds the full message list to send to Ollama for `key`'s next turn:
/// an optional summary of turns 4-8 back, the last up to 3 turns verbatim,
/// then the new user message (with `images` attached only to this last
/// message, never to remembered history).
pub async fn build_messages(
    app: &AppHandle,
    state: &MemoryState,
    key: &str,
    model: &str,
    num_ctx: u32,
    new_user_text: &str,
    images: Option<Vec<String>>,
) -> Vec<ChatMessage> {
    let (middle, recent) = {
        let map = state.0.lock().unwrap();
        match map.get(key) {
            Some(mem) => (mem.middle_turns(), mem.recent_turns()),
            None => (Vec::new(), Vec::new()),
        }
    };

    let mut messages = Vec::new();

    if !middle.is_empty() {
        if let Some(summary) = summarize(app, model, num_ctx, &middle).await {
            messages.push(ChatMessage::text(
                "user",
                format!("(참고용 이전 대화 요약: {summary})"),
            ));
        }
    }

    for turn in recent {
        messages.push(ChatMessage::text("user", turn.user));
        messages.push(ChatMessage::text("assistant", turn.assistant));
    }

    let mut current = ChatMessage::text("user", new_user_text);
    current.images = images;
    messages.push(current);

    messages
}

/// Records the completed turn (plain text only -- attachment images are
/// never stored, see module docs).
pub fn record_turn(state: &MemoryState, key: &str, user_text: &str, assistant_text: &str) {
    let mut map = state.0.lock().unwrap();
    map.entry(key.to_string())
        .or_default()
        .record(user_text.to_string(), assistant_text.to_string());
}

async fn summarize(app: &AppHandle, model: &str, num_ctx: u32, turns: &[Turn]) -> Option<String> {
    let mut transcript = String::new();
    for turn in turns {
        transcript.push_str("사용자: ");
        transcript.push_str(&turn.user);
        transcript.push('\n');
        transcript.push_str("답변: ");
        transcript.push_str(&turn.assistant);
        transcript.push('\n');
    }

    let prompt = format!(
        "다음은 이전 대화의 일부입니다. 이후 대화에서 참고할 수 있도록 핵심 내용만 \
         2~3문장으로 간결하게 요약해줘. 요약문만 출력하고 다른 설명은 하지 마.\n\n{transcript}"
    );
    let messages = vec![ChatMessage::text("user", prompt)];

    let result = queue::run_queued(
        app,
        "memory-summary",
        "(대화 요약 생성)".to_string(),
        ollama::chat(model, &messages, num_ctx),
    )
    .await;

    match result {
        Ok(r) => Some(r.content),
        Err(e) => {
            eprintln!("memory: summarization failed: {e}");
            None
        }
    }
}
