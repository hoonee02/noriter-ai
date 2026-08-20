//! LLM wiki / encyclopedia -- user-curated documents (not auto-generated
//! every turn, per design: only explicit saves, to avoid noise). Persisted
//! to `<config dir>/noriter-ai/wiki/index.json`. Distinct from
//! `personal_memory.rs`: memory is "always injected", the wiki is "looked
//! up" -- entries are not automatically added to prompts.

use crate::ollama::ChatMessage;
use crate::preflight;
use crate::queue;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::AppHandle;

/// What one page says about another. Replaces the old bare `related_ids`:
/// "these are connected" was never enough to act on -- a contradiction and
/// a citation are both links but mean opposite things (design §3.1).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RelationKind {
    Basis,       // built from this
    Reference,   // refers to this
    Contradicts, // conflicts with this
    PartOf,      // subordinate to this
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WikiRelation {
    /// Points at an id, never a title: titles get disambiguated and edited,
    /// ids do not (D-06 made them unique so this can be relied on).
    pub target_id: String,
    pub kind: RelationKind,
}

/// How much weight a page's content can carry (design §2.4).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Confidence {
    Stated,    // written in the source
    Inferred,  // reasonable inference
    Uncertain, // thin evidence
}

/// Defaults to the *lowest* grade on purpose: this value is only reached
/// when an entry arrived without one, and inventing `Stated` for something
/// we know nothing about is exactly the "asserting without evidence" the
/// confidence system exists to prevent (§2.4).
impl Default for Confidence {
    fn default() -> Self {
        Confidence::Uncertain
    }
}

/// D-08 ④: what distinguishes two pages that share a title.
///
/// Stored apart from `title` on purpose. Folding the parenthesis into the
/// title itself would leave it stranded once the other page is deleted and
/// the clash is gone -- keeping the base title lets the suffix simply drop.
///
/// The industry axis (1st priority, design §4.1.1) is absent until Taxonomy
/// lands. `AXES` below is ordered, so adding it is one entry plus its key
/// and label arms.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Disambiguator {
    Company(String), // display name, not corp_code: this is a label to read
    Period(String),
}

impl Disambiguator {
    fn label(&self) -> &str {
        match self {
            Disambiguator::Company(s) | Disambiguator::Period(s) => s,
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Axis {
    Company,
    Period,
}

/// Priority order from the design: industry, then company, then period.
const AXES: [Axis; 2] = [Axis::Company, Axis::Period];

/// What decides whether two pages differ on this axis. Uses `corp_code`
/// rather than the display name so spelling variants don't read as two
/// different companies (D-05c).
fn axis_key(entry: &WikiEntry, axis: Axis) -> Option<String> {
    match axis {
        Axis::Company => entry.company.as_ref().map(|c| c.corp_code.clone()),
        Axis::Period => entry.period.clone(),
    }
}

fn axis_disambiguator(entry: &WikiEntry, axis: Axis) -> Option<Disambiguator> {
    match axis {
        Axis::Company => entry
            .company
            .as_ref()
            .map(|c| Disambiguator::Company(c.display_name.clone())),
        Axis::Period => entry.period.clone().map(Disambiguator::Period),
    }
}

/// Company identity (10_OpenDART_연동 §4). `corp_code` is the key for every
/// filter, path and index -- display names drift (`삼성전자` / `삼성전자(주)`)
/// and, used as a path segment, would let `\` or `..` through (D-10).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompanyRef {
    pub corp_code: String,
    pub display_name: String,
    pub stock_code: Option<String>,
}

/// D-02: container-level `serde(default)` so entries written by an older
/// schema keep loading when fields are added later -- without it the whole
/// index fails to parse, the loader silently starts empty, and the next
/// save overwrites the file (same bug `config.rs` already hit and fixed on
/// `AppConfig`). Schema keeps evolving after v0.1.5, so this stays.
///
/// `RelationKind` needs no `Default` despite the D-02 note: the container
/// attribute only requires `WikiEntry: Default`, and `Vec<WikiRelation>`
/// defaults to empty without ever constructing a relation.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct WikiEntry {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub body: String,
    pub tags: Vec<String>,
    pub source: String,
    pub relations: Vec<WikiRelation>,
    pub confidence: Confidence,
    /// Company scope. `None` means "not about one company" (a concept
    /// page), which is different from "we don't know" -- D-05a treats an
    /// unscoped page as readable from any company's context.
    pub company: Option<CompanyRef>,
    /// Accounting period, e.g. `"2025-FY"`.
    pub period: Option<String>,
    /// Set only while another page shares this title (D-08 ④).
    pub disambiguator: Option<Disambiguator>,
    /// Whether this page's body carries figures that a summary cannot stand
    /// in for (09 §3.2). `summary` for a financial page reads "2025년 실적
    /// 요약" -- every number lives in the body, so summarising it is not
    /// lossy compression but total loss. Such a page is dropped outright
    /// (and reported) rather than reduced to its summary.
    pub body_required: bool,
    pub created_at: String,
    pub updated_at: String,
}

impl WikiEntry {
    /// The one way a title is rendered -- display, reports, and the text a
    /// body links by. Titles became link anchors when the "제목 없음"
    /// fallback was removed (D-08 ③), so two pages sharing one must be
    /// distinguishable wherever the title is shown.
    pub fn canonical_title(&self) -> String {
        match &self.disambiguator {
            None => self.title.clone(),
            Some(d) => format!("{}({})", self.title, d.label()),
        }
    }
}

/// Re-derives disambiguators for every page sharing `title`. Returns `true`
/// when the group turned out to be a real duplicate, leaving the logging to
/// the caller.
///
/// Keeping the write out of here is what makes the function testable: it
/// touches only the slice it is given, so tests do not append to the real
/// `wiki/log.md` in the user's config directory.
///
/// Runs on both save and delete, and rewrites the *whole* group rather than
/// just the new page. Tagging only the newcomer would leave `영업이익률` and
/// `영업이익률(LG전자)` side by side, where the untagged one silently reads
/// as the canonical one; and on delete, the survivor's suffix has to come
/// back off once there is nothing left to distinguish it from.
#[must_use]
fn reconcile_disambiguators(entries: &mut [WikiEntry], title: &str) -> bool {
    let group: Vec<usize> = entries
        .iter()
        .enumerate()
        .filter(|(_, e)| e.title == title)
        .map(|(i, _)| i)
        .collect();

    if group.len() < 2 {
        for i in group {
            entries[i].disambiguator = None;
        }
        return false;
    }

    for axis in AXES {
        let keys: Vec<Option<String>> = group.iter().map(|&i| axis_key(&entries[i], axis)).collect();
        // An axis only works if every page in the group has a value for it
        // and no two share one -- a partial split would leave some pages
        // still ambiguous while looking resolved.
        if keys.iter().any(|k| k.is_none()) {
            continue;
        }
        let mut seen: Vec<&String> = keys.iter().flatten().collect();
        seen.sort();
        seen.dedup();
        if seen.len() != group.len() {
            continue;
        }
        for &i in &group {
            entries[i].disambiguator = axis_disambiguator(&entries[i], axis);
        }
        return false;
    }

    // Same title, same company, same period: this is not an ambiguity to
    // label but the same page stored twice. Numbering them would bury that,
    // so report it for lint to pick up (§2.6) and leave the titles bare.
    for &i in &group {
        entries[i].disambiguator = None;
    }
    true
}

/// Applies `reconcile_disambiguators` and records a duplicate if one showed up.
fn reconcile_and_log(entries: &mut [WikiEntry], title: &str) {
    if reconcile_disambiguators(entries, title) {
        log_append("duplicate", &format!("{title} -- 구분 축이 없어 중복으로 보입니다 (병합 검토)"));
    }
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

/// D-03: unpromoted answers live here, and nothing ever reads this file
/// back as model context.
fn draft_path() -> PathBuf {
    wiki_dir().join("draft.json")
}

fn log_path() -> PathBuf {
    wiki_dir().join("log.md")
}

/// Shared with the rework-loop escalation in the agent design (D3 §8.3):
/// one place a person has to check, not one per failure mode.
fn pending_work_path() -> PathBuf {
    wiki_dir().join("미결작업.md")
}

/// Appends a timestamped, grep-able line to `wiki/log.md`, mirroring the
/// `## [date] action | title` convention -- lets a plain `grep "^## \["`
/// show recent activity without needing to open the app.
fn log_append(action: &str, title: &str) {
    let line = format!(
        "## [{}] {action} | {title}\n",
        chrono::Local::now().format("%Y-%m-%d %H:%M")
    );
    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(log_path()) {
        let _ = f.write_all(line.as_bytes());
    }
}

/// D-08 ②: after `PARSE_RETRY_LIMIT` attempts the problem is not transient
/// format drift, so it stops being the machine's to retry. Appends a record
/// a person can act on and gives up -- deliberately no auto-resume (O-9).
fn save_pending_work(source_label: &str, failures: &[ParseError]) {
    let mut text = format!(
        "\n## [{}] 자료 통합 실패 — {source_label}\n- 시도 횟수: {}회 (상한 도달)\n- 실패 유형 이력:\n",
        chrono::Local::now().format("%Y-%m-%d %H:%M"),
        failures.len()
    );
    for (i, f) in failures.iter().enumerate() {
        text.push_str(&format!("  {}. {f}\n", i + 1));
    }
    if let Some(last) = failures.last() {
        let excerpt: String = last.raw_response().chars().take(500).collect();
        text.push_str(&format!("- 마지막 모델 응답(발췌):\n```\n{excerpt}\n```\n"));
    }
    text.push_str("- 상태: 사람 검토 대기\n");

    if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(pending_work_path()) {
        let _ = f.write_all(text.as_bytes());
    }
}

fn load_from(path: PathBuf) -> Vec<WikiEntry> {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

/// D-07: write-temp-then-rename so the store file is always either the
/// complete old state or the complete new state -- a crash mid-write must
/// never leave a truncated file (which the loader would silently treat as
/// an empty wiki, per the D-02 decision to keep `unwrap_or_default`).
fn save_to(path: PathBuf, entries: &[WikiEntry]) {
    let Ok(text) = serde_json::to_string_pretty(entries) else { return };
    let tmp = path.with_extension("json.tmp");
    // Write the temp file completely first -- if we die here, the real file is untouched.
    if fs::write(&tmp, text).is_err() {
        return;
    }
    // rename is atomic within a volume; on Windows fs::rename replaces an
    // existing target (MOVEFILE_REPLACE_EXISTING).
    let _ = fs::rename(&tmp, &path);
}

fn now_iso() -> String {
    chrono::Local::now().to_rfc3339()
}

/// D-06: millisecond timestamps alone collide when ids are minted faster
/// than the clock ticks (tight save loops), and a collision makes
/// `update()` touch only the first entry while `delete()` removes both.
/// The timestamp provides macro uniqueness (across restarts -- the counter
/// resetting is harmless because restart takes far longer than 1ms), the
/// counter provides micro uniqueness within the same millisecond.
static SEQ: AtomicU64 = AtomicU64::new(0);

fn new_id() -> String {
    format!(
        "wiki_{}_{}",
        chrono::Local::now().format("%Y%m%d%H%M%S%3f"),
        SEQ.fetch_add(1, Ordering::Relaxed)
    )
}

/// The promoted store (`index.json`) -- the only thing ever fed back to the
/// model as context.
pub struct WikiState(Mutex<Vec<WikiEntry>>);

impl Default for WikiState {
    fn default() -> Self {
        Self(Mutex::new(load_from(index_path())))
    }
}

/// D-03: the unpromoted store (`draft.json`). `query()` writes here
/// unconditionally, exactly as it used to write to the wiki -- the fix is
/// that nothing reads this back, so a generated answer can never become the
/// evidence for the next answer. Entries leave only via `promote` (a person,
/// or the post-approval versioning agent) or `discard_draft`.
pub struct DraftState(Mutex<Vec<WikiEntry>>);

impl Default for DraftState {
    fn default() -> Self {
        Self(Mutex::new(load_from(draft_path())))
    }
}

/// An entry as the UI shows it: every stored field plus the rendered title.
///
/// `canonical_title` is computed rather than stored so there is exactly one
/// place that decides how a title reads (D-08 ④). The UI displays this and
/// edits `title`, which keeps the base title editable without the suffix
/// getting baked into it.
#[derive(Serialize)]
pub struct WikiEntryView {
    #[serde(flatten)]
    pub entry: WikiEntry,
    pub canonical_title: String,
}

impl From<WikiEntry> for WikiEntryView {
    fn from(entry: WikiEntry) -> Self {
        Self { canonical_title: entry.canonical_title(), entry }
    }
}

pub fn list(state: &WikiState) -> Vec<WikiEntry> {
    state.0.lock().unwrap().clone()
}

pub fn list_view(state: &WikiState) -> Vec<WikiEntryView> {
    list(state).into_iter().map(Into::into).collect()
}

pub fn list_draft_view(state: &DraftState) -> Vec<WikiEntryView> {
    list_draft(state).into_iter().map(Into::into).collect()
}

/// Pure half of `list_scoped`, split out so the filter rule can be tested
/// without standing up a `WikiState` bound to the real config directory.
fn in_scope(entry: &WikiEntry, scope: Option<&str>) -> bool {
    match (scope, &entry.company) {
        (None, _) => true,
        // Concept pages ("what operating margin means") carry no company and
        // are useful from every company's context.
        (Some(_), None) => true,
        (Some(code), Some(c)) => c.corp_code == code,
    }
}

/// D-05a: pages visible from one company's context.
///
/// `None` means no scope was asked for, so everything is returned -- callers
/// must say so in their output, otherwise a whole-wiki answer reads as a
/// company-specific one.
///
/// Pages with no company are always included: they are concept pages
/// ("what operating margin means"), useful from any company's context. That
/// is different from a page whose company we failed to record -- which is
/// why `company` is only ever filled from a resolved `CompanyRef` and never
/// guessed (D-05b/c).
pub fn list_scoped(state: &WikiState, scope: Option<&str>) -> Vec<WikiEntry> {
    let entries = state.0.lock().unwrap();
    match scope {
        None => entries.clone(),
        Some(_) => entries.iter().filter(|e| in_scope(e, scope)).cloned().collect(),
    }
}

pub fn list_draft(state: &DraftState) -> Vec<WikiEntry> {
    state.0.lock().unwrap().clone()
}

/// Same unconditional save `query()` always did -- only the destination
/// changed (D-03). Kept separate from `save()` rather than parameterised so
/// the two stores can never be mixed up at a call site.
fn save_draft(state: &DraftState, entry: WikiEntry) -> WikiEntry {
    let mut entries = state.0.lock().unwrap();
    entries.push(entry.clone());
    save_to(draft_path(), &entries);
    drop(entries);
    log_append("draft", &entry.title);
    entry
}

/// Moves a draft into the promoted store. The **only** way content reaches
/// `index.json` from a query answer -- called either by a person via the UI
/// or by the post-approval versioning agent (design §8.1).
///
/// The id is carried over unchanged: relations and version chains point at
/// ids, so re-minting one here would break every link into this page.
pub fn promote(draft: &DraftState, wiki: &WikiState, id: &str) -> Result<WikiEntry, String> {
    let mut drafts = draft.0.lock().unwrap();
    let entry = take_entry(&mut drafts, id).ok_or("draft entry not found")?;
    save_to(draft_path(), &drafts);
    drop(drafts);

    let mut entries = wiki.0.lock().unwrap();
    entries.push(entry);
    // Promotion is the moment a draft joins the store where titles are
    // anchors, so it can create a clash the draft never had (D-08 ④).
    let title = entries.last().expect("just pushed").title.clone();
    reconcile_and_log(&mut entries, &title);
    save_to(index_path(), &entries);

    let entry = entries.last().expect("just pushed").clone();
    drop(entries);

    log_append("promote", &entry.title);
    Ok(entry)
}

/// Removes and returns the entry with `id`, leaving the rest untouched.
/// Split out from `promote` so the part that can actually be wrong (finding
/// the right entry, removing it exactly once, handing it back unmodified) is
/// testable without touching the real config directory.
fn take_entry(entries: &mut Vec<WikiEntry>, id: &str) -> Option<WikiEntry> {
    let pos = entries.iter().position(|e| e.id == id)?;
    Some(entries.remove(pos))
}

pub fn discard_draft(state: &DraftState, id: &str) {
    let mut entries = state.0.lock().unwrap();
    let title = entries.iter().find(|e| e.id == id).map(|e| e.title.clone());
    entries.retain(|e| e.id != id);
    save_to(draft_path(), &entries);
    drop(entries);
    if let Some(t) = title {
        log_append("discard-draft", &t);
    }
}

/// Everything a caller supplies for a new page. A struct rather than nine
/// positional arguments -- with `confidence`/`company`/`period` added, a
/// call site could no longer be read without counting commas.
#[derive(Default)]
pub struct NewPage {
    pub title: String,
    pub summary: String,
    pub body: String,
    pub tags: Vec<String>,
    pub source: String,
    pub relations: Vec<WikiRelation>,
    pub confidence: Confidence,
    pub company: Option<CompanyRef>,
    pub period: Option<String>,
    pub body_required: bool,
}

pub fn save(state: &WikiState, page: NewPage) -> WikiEntry {
    let mut entries = state.0.lock().unwrap();
    // D-06: mint the id while holding the lock so id order matches insertion
    // order -- costs nothing since we take the lock right after anyway.
    let now = now_iso();
    let entry = WikiEntry {
        id: new_id(),
        title: page.title,
        summary: page.summary,
        body: page.body,
        tags: page.tags,
        source: page.source,
        relations: page.relations,
        confidence: page.confidence,
        company: page.company,
        period: page.period,
        // Derived below from the whole same-title group, never supplied.
        disambiguator: None,
        body_required: page.body_required,
        created_at: now.clone(),
        updated_at: now,
    };
    entries.push(entry);
    // D-08 ④: a new page can make an existing one ambiguous, so the whole
    // same-title group is re-derived, not just this entry.
    let title = entries.last().expect("just pushed").title.clone();
    reconcile_and_log(&mut entries, &title);
    save_to(index_path(), &entries);

    let entry = entries.last().expect("just pushed").clone();
    drop(entries);
    // Body length goes in the log too (D-08 ①) so a page that came out
    // thinner than it should have is visible after the fact.
    log_append("save", &format!("{} (본문 {}자)", entry.title, entry.body.chars().count()));
    entry
}

// `update` was removed in 0.1.6 along with the manual edit form. Pages are
// written by ingest and reviewed in the draft queue; a page that came out
// wrong is discarded there or deleted, not hand-patched field by field.

pub fn delete(state: &WikiState, id: &str) {
    let mut entries = state.0.lock().unwrap();
    let removed = entries.iter().find(|e| e.id == id).map(|e| e.title.clone());
    entries.retain(|e| e.id != id);
    // Deleting can resolve a clash, and then the survivor's suffix has to go.
    if let Some(title) = removed {
        reconcile_and_log(&mut entries, &title);
    }
    save_to(index_path(), &entries);
}

#[derive(Debug)]
pub struct ParsedPage {
    pub title: String,
    pub summary: String,
    pub tags: Vec<String>,
    pub body: String,
}

/// D-08: parsing failures are reported, never papered over. A page with no
/// body (or no title) is worse than no page at all -- it looks like a real
/// entry to every later reader while carrying nothing.
#[derive(Debug)]
pub enum ParseError {
    EmptyBody { raw_response: String },
    EmptyTitle { raw_response: String },
}

impl ParseError {
    fn raw_response(&self) -> &str {
        match self {
            ParseError::EmptyBody { raw_response } | ParseError::EmptyTitle { raw_response } => raw_response,
        }
    }
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParseError::EmptyBody { .. } => write!(f, "본문 수집 실패"),
            ParseError::EmptyTitle { .. } => write!(f, "제목 수집 실패"),
        }
    }
}

/// Drops leading markdown decoration so a label the model wrote as
/// `**TITLE:**` or `## TITLE:` still matches -- models drift into markdown
/// constantly, and that drift is not a reason to lose the content.
fn strip_decoration(line: &str) -> &str {
    line.trim().trim_start_matches(['#', '*', '-', '>', ' ']).trim_start()
}

/// Case-insensitive label match, returning what follows on the same line.
fn match_label<'a>(line: &'a str, label: &str) -> Option<&'a str> {
    let s = strip_decoration(line);
    // `get` rather than slicing: `s` may start with a multi-byte character,
    // where a byte-index slice would panic on a char boundary.
    if !s.get(..label.len())?.eq_ignore_ascii_case(label) {
        return None;
    }
    Some(s[label.len()..].trim().trim_matches('*').trim())
}

/// Parses the model's `TITLE:`/`SUMMARY:`/`TAGS:`/`BODY:` structured
/// response -- plain line-prefix parsing rather than asking for JSON,
/// since small local models are much more reliable at this than at
/// producing well-formed JSON.
fn parse_structured(text: &str) -> Result<ParsedPage, ParseError> {
    let mut title = String::new();
    let mut summary = String::new();
    let mut tags = Vec::new();
    let mut body = String::new();
    let mut in_body = false;

    for line in text.lines() {
        if in_body {
            body.push_str(line);
            body.push('\n');
            continue;
        }
        if let Some(rest) = match_label(line, "BODY:") {
            in_body = true;
            // The original defect: `BODY:` was only honoured as an exact
            // standalone line, so `BODY: 내용...` silently produced an empty
            // body. Anything trailing the label is the body's first line.
            if !rest.is_empty() {
                body.push_str(rest);
                body.push('\n');
            }
        } else if let Some(rest) = match_label(line, "TITLE:") {
            title = rest.to_string();
        } else if let Some(rest) = match_label(line, "SUMMARY:") {
            summary = rest.to_string();
        } else if let Some(rest) = match_label(line, "TAGS:") {
            tags = rest
                .split(',')
                .map(|t| t.trim().to_string())
                .filter(|t| !t.is_empty())
                .collect();
        }
    }

    let title = title.trim().to_string();
    let body = body.trim().to_string();

    // No "제목 없음" fallback (D-08 ③): the title is a link anchor, not a
    // display string. A shared placeholder would make unrelated pages
    // collide on the same anchor and quietly corrupt the link graph.
    if title.is_empty() {
        return Err(ParseError::EmptyTitle { raw_response: text.to_string() });
    }
    if body.is_empty() {
        return Err(ParseError::EmptyBody { raw_response: text.to_string() });
    }
    Ok(ParsedPage { title, summary: summary.trim().to_string(), tags, body })
}

/// D-08 ②: same limit as the approval-gate rework loop (D3 §8.1) -- "three
/// tries, then a person" is one rule across the system, even though the two
/// loops fail for different reasons (content disagreement vs format drift).
const PARSE_RETRY_LIMIT: u32 = 3;

/// **Ingest**: integrates a piece of raw source text into the wiki by
/// asking the model to write one structured page from it (title, summary,
/// tags, markdown body), then saves it. A real multi-page Ingest (one
/// source updating 10-15 existing pages) is a larger follow-up; this is
/// the single-page MVP of the same idea.
///
/// Retries on parse failure rather than saving something half-formed: an
/// empty page is indistinguishable from a real one once it's in the wiki,
/// so it must never be written in the first place (D-08).
pub async fn ingest(
    app: &AppHandle,
    state: &WikiState,
    model: &str,
    num_ctx: u32,
    source_text: &str,
    source_label: &str,
) -> Result<WikiEntry, String> {
    let prompt = format!(
        "다음은 위키에 새로 통합할 자료입니다 (출처: {source_label}).\n\n{source_text}\n\n\
         이 자료를 바탕으로 위키 문서 하나를 작성해줘. 아래 형식을 정확히 지켜서 답해:\n\
         TITLE: (문서 제목, 한 줄)\n\
         SUMMARY: (한 문장 요약)\n\
         TAGS: (쉼표로 구분한 태그 목록)\n\
         BODY:\n\
         (마크다운 본문, 핵심 내용을 구조화해서 정리)"
    );
    let messages = vec![ChatMessage::text("user", prompt)];
    let mut failures = Vec::new();

    for attempt in 1..=PARSE_RETRY_LIMIT {
        let preview = format!("(위키 통합: {source_label})");
        let result = queue::call_llm(app, "wiki-ingest", preview, model, &messages, num_ctx).await?;

        match parse_structured(&result.content) {
            Ok(page) => {
                return Ok(save(
                    state,
                    NewPage {
                        title: page.title,
                        summary: page.summary,
                        body: page.body,
                        tags: page.tags,
                        source: format!("ingest:{source_label}"),
                        // Ingest restructures what the source already says,
                        // so the content is `Stated`. (OCR input downgrades
                        // to `Inferred` per Guard 0 -- that lives in the
                        // preprocessing agent, which doesn't exist yet.)
                        confidence: Confidence::Stated,
                        ..Default::default()
                    },
                ))
            }
            Err(e) => {
                log_append(
                    "ingest-fail",
                    &format!("{source_label} ({attempt}/{PARSE_RETRY_LIMIT}): {e}"),
                );
                failures.push(e);
            }
        }
    }

    save_pending_work(source_label, &failures);
    Err(format!(
        "본문 수집에 {PARSE_RETRY_LIMIT}회 반복 실패해 미결작업.md로 이관했습니다 ({source_label})"
    ))
}

/// **Query**: answers a question using the wiki as context (index-style
/// title/summary/tags for every entry, plus full bodies too if the whole
/// wiki is small enough to fit comfortably). The answer is still saved
/// unconditionally -- per the core LLM-wiki idea, exploration accumulates
/// instead of disappearing into chat history.
///
/// D-03: context comes from `wiki` (promoted) and the answer goes to
/// `draft` (unpromoted). Because those are different stores, an answer can
/// never become evidence for the next answer -- no filtering logic needed,
/// the path simply doesn't exist. Promotion is a separate human/agent step.
pub async fn query(
    app: &AppHandle,
    wiki: &WikiState,
    draft: &DraftState,
    model: &str,
    num_ctx: u32,
    question: &str,
    scope: Option<&str>,
    history: &[ChatMessage],
) -> Result<String, String> {
    let entries = list_scoped(wiki, scope);

    // D-04: ranked tiers and a derived budget, replacing the old
    // all-or-nothing 6000-char switch. Path B goes through the same
    // preflight as the agent pipeline will (design §8.2.2), which is also
    // how the ranking gets exercised in isolation before that pipeline
    // exists.
    let hint = preflight::match_known_company(&entries, question);
    let index = preflight::run_preflight(&entries, question, hint);
    // The remembered turns share the window with the retrieved pages, so the
    // wiki's share shrinks by what the history already occupies -- otherwise
    // both size against the full window and the tail is silently cut.
    let history_chars: usize = history.iter().map(|m| m.content.chars().count()).sum();
    let budget = preflight::ContextBudget::from_num_ctx(num_ctx).reserving(history_chars);
    let routed = preflight::allocate_budget(&index, &budget);
    let context = preflight::render_context(&entries, &routed);
    let excluded = preflight::excluded_notice(&entries, &routed);

    let prompt = if entries.is_empty() {
        format!("위키가 비어 있습니다. 다음 질문에 일반적으로 답해줘: {question}")
    } else {
        format!("다음은 위키에 저장된 문서들입니다.\n\n{context}\n\n위 내용을 참고해서 다음 질문에 답해줘: {question}")
    };
    let mut messages = history.to_vec();
    messages.push(ChatMessage::text("user", prompt));
    let preview = format!("(위키 질의: {question})");
    let result = queue::call_llm(app, "wiki-query", preview, model, &messages, num_ctx).await?;

    // Both notices attach to the answer rather than to a log: what the model
    // could not see has to travel with what it said.
    let mut answer = result.content;
    // D-05a: an unscoped answer must say so. Without this the user cannot
    // tell "삼성전자 only" from "every company in the wiki", and a figure
    // borrowed from another company reads as if it belonged here.
    if scope.is_none() {
        answer.push_str("\n\n---\n(기업 스코프 미지정 -- 위키 전체를 대상으로 답했습니다)");
    }
    // D-04: never let a truncated context pass as a complete one.
    if let Some(notice) = excluded {
        answer.push_str(&format!("\n\n---\n⚠ {notice}"));
    }
    let now = now_iso();
    save_draft(
        draft,
        WikiEntry {
            id: new_id(),
            title: format!("Q: {}", answer_title(question)),
            summary: answer.chars().take(200).collect(),
            body: answer.clone(),
            tags: vec!["query".to_string()],
            source: "query".to_string(),
            // Model reasoning over the wiki, not something a source states
            // -- and it stays in the draft store until a person promotes it.
            confidence: Confidence::Inferred,
            created_at: now.clone(),
            updated_at: now,
            ..Default::default()
        },
    );

    Ok(answer)
}

fn answer_title(question: &str) -> String {
    question.chars().take(80).collect()
}

/// **Lint**: asks the model to review the wiki's title/summary/tags index
/// for contradictions, orphaned pages, concepts that come up often but
/// have no dedicated page, and suggests follow-up questions -- a text
/// report, not stored as a page itself (only logged).
/// D-05a applies here too, and matters more than it looks: unscoped lint
/// reports "A사 매출 300조 vs B사 매출 84조" as a contradiction, because
/// nothing tells it the two figures belong to different companies.
pub async fn lint(
    app: &AppHandle,
    state: &WikiState,
    model: &str,
    num_ctx: u32,
    scope: Option<&str>,
) -> Result<String, String> {
    let entries = list_scoped(state, scope);
    if entries.is_empty() {
        return Ok("위키가 비어 있습니다.".to_string());
    }

    // Each line carries its company so the model can tell two firms' figures
    // apart even when the scope is the whole wiki.
    let context: String = entries
        .iter()
        .map(|e| {
            let company = e
                .company
                .as_ref()
                .map(|c| c.display_name.as_str())
                .unwrap_or("기업 무관");
            format!(
                "- [{}] {} (기업: {company}, 태그: {})\n",
                e.canonical_title(),
                e.summary,
                e.tags.join(", ")
            )
        })
        .collect();
    let prompt = format!(
        "다음은 위키 문서 목록(제목/요약/기업/태그)입니다.\n\n{context}\n\n\
         이 목록을 점검해서 다음을 간단히 정리해줘:\n\
         1) 서로 모순되는 것으로 보이는 문서 -- **기업이 다르면 수치가 달라도 모순이 아니다**\n\
         2) 다른 문서와 연결이 없어 보이는 고아 문서\n\
         3) 자주 언급되지만 전용 문서가 없어 보이는 개념\n\
         4) 추가로 조사하면 좋을 질문"
    );
    let messages = vec![ChatMessage::text("user", prompt)];
    let result = queue::call_llm(app, "wiki-lint", "(위키 점검)".to_string(), model, &messages, num_ctx).await?;

    log_append("lint", "위키 점검 실행");
    let report = match scope {
        Some(_) => result.content,
        None => format!(
            "{}\n\n---\n(기업 스코프 미지정 -- 위키 전체를 점검했습니다)",
            result.content
        ),
    };
    Ok(report)
}

pub fn log_tail(lines: usize) -> Vec<String> {
    let text = fs::read_to_string(log_path()).unwrap_or_default();
    let all: Vec<String> = text.lines().map(String::from).collect();
    let start = all.len().saturating_sub(lines);
    all[start..].to_vec()
}

#[cfg(test)]
mod tests {
    use super::{
        in_scope, new_id, parse_structured, reconcile_disambiguators, take_entry, CompanyRef,
        Disambiguator, ParseError, WikiEntry,
    };

    fn titled(title: &str, corp: Option<&str>, period: Option<&str>) -> WikiEntry {
        WikiEntry {
            id: format!("{title}-{corp:?}-{period:?}"),
            title: title.into(),
            company: corp.map(|c| CompanyRef {
                corp_code: c.into(),
                display_name: format!("{c}사"),
                stock_code: None,
            }),
            period: period.map(Into::into),
            ..Default::default()
        }
    }

    fn entry(id: &str) -> WikiEntry {
        WikiEntry { id: id.into(), title: id.into(), ..Default::default() }
    }

    fn entry_for(id: &str, corp_code: &str) -> WikiEntry {
        WikiEntry {
            id: id.into(),
            title: id.into(),
            company: Some(CompanyRef {
                corp_code: corp_code.into(),
                display_name: corp_code.into(),
                stock_code: None,
            }),
            ..Default::default()
        }
    }

    /// D-06 regression: the original millisecond-only id collided whenever
    /// two ids were minted within the same millisecond. A tight loop is
    /// exactly that scenario -- every id must still be unique.
    #[test]
    fn new_id_unique_in_tight_loop() {
        let ids: std::collections::HashSet<String> = (0..10_000).map(|_| new_id()).collect();
        assert_eq!(ids.len(), 10_000);
    }

    /// D-02 regression: an entry serialized by an older schema (fields
    /// missing that a newer schema knows about) must still deserialize,
    /// filling the gaps with defaults -- a parse failure here would blank
    /// the whole wiki and the next save would make the loss permanent.
    #[test]
    fn wiki_entry_tolerates_missing_fields() {
        let old_schema = r#"{"id":"wiki_x","title":"t","summary":"s","body":"b",
                             "source":"src","created_at":"c","updated_at":"u"}"#;
        let e: WikiEntry = serde_json::from_str(old_schema).expect("old entry must load");
        assert_eq!(e.id, "wiki_x");
        assert!(e.tags.is_empty());
        assert!(e.relations.is_empty());
        // Fields the old schema never had must not be invented optimistically:
        // an entry we know nothing about is Uncertain, not Stated.
        assert_eq!(e.confidence, super::Confidence::Uncertain);
        assert!(e.company.is_none());
    }

    /// D-03: promoting must move the entry across stores exactly once and
    /// hand it over with its id intact -- relations and version chains point
    /// at ids, so re-minting one here would silently orphan every link into
    /// the page, and failing to remove it would leave the same page in both
    /// stores (the self-contamination the two-store split exists to prevent).
    #[test]
    fn take_entry_removes_once_and_preserves_id() {
        let mut drafts = vec![entry("a"), entry("b"), entry("c")];

        let taken = take_entry(&mut drafts, "b").expect("entry must be found");
        assert_eq!(taken.id, "b");
        assert_eq!(
            drafts.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(),
            ["a", "c"]
        );

        // A second promote of the same id must not resurrect it.
        assert!(take_entry(&mut drafts, "b").is_none());
        assert_eq!(drafts.len(), 2);
    }

    /// D-08 regression: `BODY:` used to be honoured only as an exact
    /// standalone line, so a model writing the body on the same line
    /// produced a page whose body was the empty string -- saved without
    /// complaint, indistinguishable from a real page afterwards.
    #[test]
    fn body_on_same_line_as_label_is_kept() {
        let page = parse_structured("TITLE: 삼성전자\nBODY: 첫 줄 내용\n둘째 줄")
            .expect("body on the label line must parse");
        assert_eq!(page.title, "삼성전자");
        assert_eq!(page.body, "첫 줄 내용\n둘째 줄");
    }

    /// Models drift into markdown and add leading whitespace; neither is a
    /// reason to lose the content, so labels match after decoration is
    /// stripped and regardless of case.
    #[test]
    fn labels_match_through_markdown_and_case() {
        let page = parse_structured("  **title:** 영업이익률\n## TAGS: 재무, 지표\n**BODY:**\n본문")
            .expect("decorated labels must parse");
        assert_eq!(page.title, "영업이익률");
        assert_eq!(page.tags, ["재무", "지표"]);
        assert_eq!(page.body, "본문");
    }

    /// An empty body must fail loudly instead of producing a page that
    /// looks real to every later reader while carrying nothing.
    #[test]
    fn empty_body_is_an_error() {
        let err = parse_structured("TITLE: 제목만 있음\nSUMMARY: 요약").unwrap_err();
        assert!(matches!(err, ParseError::EmptyBody { .. }));
        // The raw response rides along so a retry or a person can diagnose it.
        assert!(err.raw_response().contains("제목만 있음"));
    }

    /// D-05a: scoping must keep another company's pages out while letting
    /// company-agnostic concept pages through. Excluding concept pages would
    /// strip shared definitions from every scoped answer; including the
    /// other company's is the contamination the filter exists to stop --
    /// worse than no filter, because the verification agent would then find
    /// the borrowed figure in the wiki and confirm it.
    #[test]
    fn scope_excludes_other_companies_but_keeps_concept_pages() {
        let samsung = entry_for("a", "00126380");
        let lg = entry_for("b", "00401731");
        let concept = entry("영업이익률"); // no company

        assert!(in_scope(&samsung, Some("00126380")));
        assert!(!in_scope(&lg, Some("00126380")));
        assert!(in_scope(&concept, Some("00126380")));

        // No scope asked for -- everything is in, and the caller has to say so.
        for e in [&samsung, &lg, &concept] {
            assert!(in_scope(e, None));
        }
    }

    /// D-08 ④: both pages get a suffix, not just the newcomer. Tagging only
    /// the new one leaves `영업이익률` beside `영업이익률(B사)`, where the
    /// bare title silently reads as the canonical one.
    #[test]
    fn clash_labels_every_page_in_the_group() {
        let mut entries = vec![
            titled("영업이익률", Some("A"), None),
            titled("영업이익률", Some("B"), None),
        ];
        let _ = reconcile_disambiguators(&mut entries, "영업이익률");

        assert_eq!(entries[0].canonical_title(), "영업이익률(A사)");
        assert_eq!(entries[1].canonical_title(), "영업이익률(B사)");
    }

    /// Company first, period only when the company matches -- the design's
    /// priority order, so two years of one firm don't get labelled by a
    /// company name that fails to tell them apart.
    #[test]
    fn period_is_used_only_when_company_cannot_split() {
        let mut entries = vec![
            titled("영업이익률", Some("A"), Some("2025-FY")),
            titled("영업이익률", Some("A"), Some("2024-FY")),
        ];
        let _ = reconcile_disambiguators(&mut entries, "영업이익률");

        assert_eq!(entries[0].disambiguator, Some(Disambiguator::Period("2025-FY".into())));
        assert_eq!(entries[1].disambiguator, Some(Disambiguator::Period("2024-FY".into())));
    }

    /// Same title, same company, same period is not an ambiguity to label --
    /// it is one page stored twice. Numbering them would hide that, so the
    /// titles stay bare and lint gets told.
    #[test]
    fn indistinguishable_pages_are_left_bare_as_duplicates() {
        let mut entries = vec![
            titled("영업이익률", Some("A"), Some("2025-FY")),
            titled("영업이익률", Some("A"), Some("2025-FY")),
        ];
        let _ = reconcile_disambiguators(&mut entries, "영업이익률");

        assert!(entries.iter().all(|e| e.disambiguator.is_none()));
    }

    /// Deleting the other page resolves the clash, so the survivor's suffix
    /// must come off -- the reason the suffix is stored apart from `title`.
    #[test]
    fn suffix_is_dropped_once_the_clash_is_gone() {
        let mut entries = vec![
            titled("영업이익률", Some("A"), None),
            titled("영업이익률", Some("B"), None),
        ];
        let _ = reconcile_disambiguators(&mut entries, "영업이익률");
        assert!(entries[0].disambiguator.is_some());

        entries.remove(1);
        let _ = reconcile_disambiguators(&mut entries, "영업이익률");
        assert_eq!(entries[0].canonical_title(), "영업이익률");
    }

    /// D-08 ③: the "제목 없음" fallback is gone. The title is a link
    /// anchor, so a shared placeholder would collide unrelated pages onto
    /// one anchor -- a fallback is fine for a display string, never for an
    /// identifier.
    #[test]
    fn missing_title_is_an_error_not_a_fallback() {
        let err = parse_structured("BODY:\n본문은 있는데 제목이 없다").unwrap_err();
        assert!(matches!(err, ParseError::EmptyTitle { .. }));
    }
}
