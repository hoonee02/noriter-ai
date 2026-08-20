//! Turning uploaded files into prompt text.
//!
//! Shared between the Telegram bridge and web chat. It started out inside
//! `telegram.rs` because that was the only surface that accepted files; web
//! chat now does too (0.1.6), and one copy of the parsing rules means an
//! `.xlsx` reaches the model the same way whichever door it came through.

/// Cap per attachment, so one large file cannot crowd the model's window.
pub const MAX_ATTACHMENT_CHARS: usize = 8000;

/// Renders a file as the `[Attached file: ...]` block the old Dart bridge
/// used -- `.xlsx` becomes a plain-text table (one section per sheet,
/// pipe-separated cells), anything else is decoded as UTF-8 (lossy).
pub fn compose_attachment_text(file_name: &str, bytes: &[u8]) -> String {
    let ext = file_name.rsplit('.').next().unwrap_or("").to_lowercase();
    let content = if ext == "xlsx" {
        xlsx_bytes_to_text(bytes).unwrap_or_else(|e| format!("(failed to parse spreadsheet: {e})"))
    } else {
        String::from_utf8_lossy(bytes).to_string()
    };

    let truncated = content.chars().count() > MAX_ATTACHMENT_CHARS;
    let body: String = content.chars().take(MAX_ATTACHMENT_CHARS).collect();
    let notice = if truncated {
        format!("\n\n(File truncated to {MAX_ATTACHMENT_CHARS} characters)")
    } else {
        String::new()
    };
    format!("[Attached file: {file_name}]\n```\n{body}\n```{notice}")
}

pub fn xlsx_bytes_to_text(bytes: &[u8]) -> anyhow::Result<String> {
    use calamine::{Reader, Xlsx};
    let cursor = std::io::Cursor::new(bytes);
    let mut workbook: Xlsx<_> = calamine::open_workbook_from_rs(cursor)?;

    let mut out = String::new();
    for sheet_name in workbook.sheet_names().to_vec() {
        let Ok(range) = workbook.worksheet_range(&sheet_name) else {
            continue;
        };
        out.push_str(&format!("--- {sheet_name} ---\n"));
        for row in range.rows() {
            let cells: Vec<String> = row.iter().map(|c| c.to_string()).collect();
            out.push_str(&cells.join(" | "));
            out.push('\n');
        }
        out.push('\n');
    }
    Ok(out)
}

/// One file as it arrives from the web UI: name plus base64 content.
#[derive(Debug, serde::Deserialize)]
pub struct UploadedFile {
    pub name: String,
    /// base64 -- the webview cannot hand raw bytes across the IPC boundary.
    pub data: String,
}

impl UploadedFile {
    pub fn decode(&self) -> Vec<u8> {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD
            .decode(&self.data)
            .unwrap_or_default()
    }

    /// True for formats a vision model takes as an image rather than text.
    pub fn is_image(&self) -> bool {
        let ext = self.name.rsplit('.').next().unwrap_or("").to_lowercase();
        matches!(ext.as_str(), "png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oversized_attachment_is_truncated_and_says_so() {
        let big = "가".repeat(MAX_ATTACHMENT_CHARS + 500).into_bytes();
        let text = compose_attachment_text("note.txt", &big);
        assert!(text.contains("File truncated"));
        // The notice must survive: silently shortening the text would let the
        // model answer from a partial file as if it had the whole thing.
        assert!(text.contains("note.txt"));
    }

    /// Image detection drives whether the file goes to the model as an image
    /// or as text -- a misclassified image would arrive as UTF-8 garbage.
    #[test]
    fn image_extensions_are_recognised_case_insensitively() {
        let img = UploadedFile { name: "Chart.PNG".into(), data: String::new() };
        let doc = UploadedFile { name: "book.xlsx".into(), data: String::new() };
        assert!(img.is_image());
        assert!(!doc.is_image());
    }
}
