//! OpenDART integration (see `구성도/v0.1.5_적용/10_OpenDART_연동.md`).
//!
//! Scope is deliberately narrow: the corp-code directory, and nothing else.
//! That one table is what D-05c needs -- a stable key per company, so the
//! same firm written `삼성전자`, `삼성전자(주)` or `005930` resolves to one
//! scope instead of scattering across three.
//!
//! This is the first outbound network call in the app. It does not
//! contradict the "no crawling" rule (O-4): that rule bans wandering the
//! web unprompted, whereas this fetches one specific table when the user
//! asks for it. `SPEC.md`'s "offline" wording needs updating though (O-25).

use crate::wiki::CompanyRef;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Cursor, Read};
use std::path::PathBuf;
use std::sync::Mutex;

const CORP_CODE_URL: &str = "https://opendart.fss.or.kr/api/corpCode.xml";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CorpEntry {
    pub corp_code: String,
    pub corp_name: String,
    /// Listed companies only; DART pads the field with spaces when absent.
    pub stock_code: Option<String>,
}

impl CorpEntry {
    pub fn to_company_ref(&self) -> CompanyRef {
        CompanyRef {
            corp_code: self.corp_code.clone(),
            display_name: self.corp_name.clone(),
            stock_code: self.stock_code.clone(),
        }
    }
}

fn dart_dir() -> PathBuf {
    let dir = dirs::config_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("noriter-ai")
        .join("dart");
    fs::create_dir_all(&dir).ok();
    dir
}

fn corp_codes_path() -> PathBuf {
    dart_dir().join("corp_codes.json")
}

/// The cached directory, held in memory for lookups.
///
/// Cached on disk not just for speed: once fetched, company resolution keeps
/// working with no network at all, which is what preserves the app's offline
/// behaviour for everything except the initial fetch (10 §5).
#[derive(Default)]
pub struct DartState(Mutex<Vec<CorpEntry>>);

impl DartState {
    pub fn loaded() -> Self {
        Self(Mutex::new(load_cached()))
    }

    pub fn count(&self) -> usize {
        self.0.lock().unwrap().len()
    }
}

fn load_cached() -> Vec<CorpEntry> {
    fs::read_to_string(corp_codes_path())
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// Downloads the full corp-code directory and replaces the cache.
///
/// Deliberately not automatic: DART publishes ~100k rows and the list barely
/// changes, so it runs when the user asks (O-27 left the refresh cadence to
/// the user).
pub async fn refresh_corp_codes(state: &DartState, api_key: &str) -> Result<usize, String> {
    let bytes = reqwest::Client::new()
        .get(CORP_CODE_URL)
        .query(&[("crtfc_key", api_key)])
        .send()
        .await
        .map_err(|e| format!("OpenDART 요청 실패: {e}"))?
        .bytes()
        .await
        .map_err(|e| format!("OpenDART 응답 수신 실패: {e}"))?;

    let xml = unzip_single(&bytes)?;
    let entries = parse_corp_codes(&xml)?;
    if entries.is_empty() {
        // An API-key error comes back as a small XML document with a status
        // code rather than an HTTP error, so "parsed fine but empty" is the
        // shape a bad key actually takes. Reporting it as success would
        // leave the user with a silently useless cache.
        return Err("고유번호 목록이 비어 있습니다 -- API 키를 확인해주세요".into());
    }

    let text = serde_json::to_string(&entries).map_err(|e| e.to_string())?;
    // Same temp-then-rename as the wiki store (D-07): a partial write here
    // would leave a cache that parses to nothing on next start.
    let path = corp_codes_path();
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, text).map_err(|e| format!("캐시 저장 실패: {e}"))?;
    fs::rename(&tmp, &path).map_err(|e| format!("캐시 교체 실패: {e}"))?;

    let count = entries.len();
    *state.0.lock().unwrap() = entries;
    Ok(count)
}

/// DART returns the directory as a zip holding one XML document.
fn unzip_single(bytes: &[u8]) -> Result<String, String> {
    let mut archive =
        zip::ZipArchive::new(Cursor::new(bytes)).map_err(|e| format!("압축 해제 실패: {e}"))?;
    let mut file = archive
        .by_index(0)
        .map_err(|e| format!("압축 파일이 비어 있습니다: {e}"))?;
    let mut xml = String::new();
    file.read_to_string(&mut xml)
        .map_err(|e| format!("XML 읽기 실패: {e}"))?;
    Ok(xml)
}

/// Parses `<list><corp_code/><corp_name/><stock_code/></list>` repeats.
fn parse_corp_codes(xml: &str) -> Result<Vec<CorpEntry>, String> {
    use quick_xml::events::Event;
    use quick_xml::Reader;

    let mut reader = Reader::from_str(xml);
    reader.trim_text(true);

    let mut entries = Vec::new();
    let mut current: Option<CorpEntry> = None;
    let mut field = String::new();
    let mut buf = Vec::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                let name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                if name == "list" {
                    current = Some(CorpEntry {
                        corp_code: String::new(),
                        corp_name: String::new(),
                        stock_code: None,
                    });
                }
                field = name;
            }
            Ok(Event::Text(e)) => {
                let Some(entry) = current.as_mut() else { continue };
                let text = e.unescape().unwrap_or_default().trim().to_string();
                match field.as_str() {
                    "corp_code" => entry.corp_code = text,
                    "corp_name" => entry.corp_name = text,
                    // DART pads unlisted companies with spaces, so an empty
                    // string here means "not listed", not "unknown".
                    "stock_code" => entry.stock_code = (!text.is_empty()).then_some(text),
                    _ => {}
                }
            }
            Ok(Event::End(e)) => {
                if e.name().as_ref() == b"list" {
                    if let Some(entry) = current.take() {
                        if !entry.corp_code.is_empty() && !entry.corp_name.is_empty() {
                            entries.push(entry);
                        }
                    }
                }
                field.clear();
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(format!("XML 파싱 실패: {e}")),
            _ => {}
        }
        buf.clear();
    }

    Ok(entries)
}

/// Normalises a company name for comparison: strips whitespace and the
/// decorations Korean company names carry inconsistently (`(주)`, `주식회사`).
/// This is presentation noise, not identity -- `삼성전자` and `삼성전자(주)`
/// are the same company and must land on the same `corp_code` (D-05c).
fn normalize(name: &str) -> String {
    name.replace("(주)", "")
        .replace("（주）", "")
        .replace("주식회사", "")
        .chars()
        .filter(|c| !c.is_whitespace())
        .flat_map(|c| c.to_lowercase())
        .collect()
}

/// Resolves a company name (or stock code) to its canonical reference.
///
/// Returns `None` rather than guessing when the name is ambiguous or absent
/// -- an unscoped page is recoverable, a page filed under the wrong company
/// quietly pollutes that company's evidence base.
pub fn lookup(state: &DartState, name: &str) -> Option<CompanyRef> {
    let query = normalize(name);
    if query.is_empty() {
        return None;
    }
    let entries = state.0.lock().unwrap();

    // A stock code is unambiguous when given, so it wins outright.
    if let Some(hit) = entries.iter().find(|e| e.stock_code.as_deref() == Some(name.trim())) {
        return Some(hit.to_company_ref());
    }

    let mut exact = entries.iter().filter(|e| normalize(&e.corp_name) == query);
    let first = exact.next()?;
    match exact.next() {
        // Same name, two companies: picking one would file pages under a
        // firm the user never meant. Leave it unresolved instead.
        Some(_) => None,
        None => Some(first.to_company_ref()),
    }
}

#[cfg(test)]
mod tests {
    use super::{normalize, parse_corp_codes};

    #[test]
    fn parses_corp_code_directory() {
        let xml = r#"<result>
            <list><corp_code>00126380</corp_code><corp_name>삼성전자</corp_name><stock_code>005930</stock_code></list>
            <list><corp_code>00434003</corp_code><corp_name>다코</corp_name><stock_code> </stock_code></list>
        </result>"#;
        let entries = parse_corp_codes(xml).expect("directory must parse");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].corp_code, "00126380");
        assert_eq!(entries[0].stock_code.as_deref(), Some("005930"));
        // Space-padded stock code means unlisted, not an empty-string code.
        assert_eq!(entries[1].stock_code, None);
    }

    /// D-05c: the same company written three ways must normalise to one key,
    /// otherwise its pages scatter across scopes and the filter hides data
    /// while looking like it works.
    #[test]
    fn name_decoration_does_not_change_identity() {
        assert_eq!(normalize("삼성전자"), normalize("삼성전자(주)"));
        assert_eq!(normalize("삼성전자"), normalize("주식회사 삼성전자"));
        assert_eq!(normalize("SK Hynix"), normalize("skhynix"));
        assert_ne!(normalize("삼성전자"), normalize("삼성전기"));
    }
}
