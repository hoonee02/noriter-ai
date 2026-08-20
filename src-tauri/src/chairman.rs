//! Routing: deciding what a prompt is actually asking for.
//!
//! Until 0.1.6 the wiki panel asked the user to make this decision through
//! the UI -- one box to paste source text into, another to ask a question,
//! another for the company scope, and a form for title/summary/body/tags.
//! That put the work of classification on the person, which is the opposite
//! of what an agent architecture is for: the design has always said the
//! chairman routes (§2.4 `chairman::decide_routing`), the user just talks.
//!
//! So the prompt (plus any attachments) is now the only entry point, and
//! this module is the reduced form of that routing decision.

use crate::ollama::ChatMessage;
use crate::queue;

/// What the user's message turned out to be.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Intent {
    /// Ordinary conversation -- no wiki involvement.
    Chat,
    /// A question to answer from the wiki.
    WikiQuery,
    /// Material to fold into the wiki as a page.
    WikiIngest,
}

impl Intent {
    fn from_label(raw: &str) -> Option<Self> {
        match raw.trim().to_uppercase().as_str() {
            s if s.starts_with("QUERY") => Some(Intent::WikiQuery),
            s if s.starts_with("INGEST") => Some(Intent::WikiIngest),
            s if s.starts_with("CHAT") => Some(Intent::Chat),
            _ => None,
        }
    }
}

/// Classifies one message.
///
/// Goes through `call_llm` like every other model call (D-01), so it is
/// serialised with the answer that follows rather than racing it.
///
/// Falls back to `Chat` when the model answers with something unexpected.
/// That direction is deliberate: `Chat` is the one outcome that changes
/// nothing on disk, so a misroute costs the user a re-phrase instead of an
/// unwanted page in the wiki.
pub async fn decide_intent(
    app: &tauri::AppHandle,
    model: &str,
    num_ctx: u32,
    prompt: &str,
    attachment_names: &[String],
) -> Intent {
    let attachments = if attachment_names.is_empty() {
        "없음".to_string()
    } else {
        attachment_names.join(", ")
    };

    let instruction = format!(
        "사용자의 메시지를 세 가지 중 하나로 분류해줘. 한 단어만 답하고 다른 말은 하지 마.\n\n\
         CHAT   -- 일반 대화나 질문. 저장해 둔 자료와 무관하다.\n\
         QUERY  -- 이전에 정리해 둔 자료(위키)를 찾아보거나 근거로 답해야 하는 질문.\n\
         INGEST -- 새 자료를 정리해서 보관해 달라는 요청. 붙여넣은 원문이나 첨부파일이 있다.\n\n\
         첨부파일: {attachments}\n\
         메시지: {prompt}\n\n\
         답(CHAT/QUERY/INGEST):"
    );

    let messages = vec![ChatMessage::text("user", instruction)];
    let result = queue::call_llm(
        app,
        "chairman-routing",
        "(요청 분류)".to_string(),
        model,
        &messages,
        num_ctx,
    )
    .await;

    match result {
        Ok(r) => Intent::from_label(&r.content).unwrap_or(Intent::Chat),
        Err(e) => {
            eprintln!("chairman: routing failed, treating as chat: {e}");
            Intent::Chat
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Intent;

    /// Small local models pad their answers -- a bare `match` on the exact
    /// string would drop back to `Chat` for perfectly good classifications.
    #[test]
    fn label_parsing_tolerates_model_padding() {
        assert_eq!(Intent::from_label("QUERY"), Some(Intent::WikiQuery));
        assert_eq!(Intent::from_label(" ingest "), Some(Intent::WikiIngest));
        assert_eq!(Intent::from_label("CHAT입니다"), Some(Intent::Chat));
        assert_eq!(Intent::from_label("QUERY -- 위키를 찾아야 함"), Some(Intent::WikiQuery));
    }

    /// An unrecognised answer must not be guessed at. The caller turns this
    /// into `Chat`, the only outcome that writes nothing.
    #[test]
    fn unknown_label_is_not_guessed() {
        assert_eq!(Intent::from_label("잘 모르겠습니다"), None);
        assert_eq!(Intent::from_label(""), None);
    }
}
