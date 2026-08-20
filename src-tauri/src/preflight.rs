//! Context budgeting for wiki queries -- the D-04 fix.
//!
//! What it replaces: one line, `if full_context.chars().count() < 6000`,
//! choosing between the entire wiki and titles-only. A single financial
//! statement pushed past that threshold, every body was dropped, and the
//! answer still came back looking fine. Nothing failed; the numbers were
//! simply gone.
//!
//! So the rule here is never "shrink until it fits". Pages are ranked, the
//! ones that must keep their bodies keep them, and whatever does not fit is
//! **reported as excluded** rather than quietly reduced to a summary that
//! contains no figures (09 §3.1).
//!
//! No LLM call anywhere in this module: ranking and budgeting are plain
//! metadata work (design §8.2). That is what lets the preflight run outside
//! the generation queue without risking the re-entrancy of D-01.

use crate::wiki::{CompanyRef, WikiEntry};

/// Budget split derived from `num_ctx` (11 §4).
///
/// Everything is derived, never hard-coded: `num_ctx` is still provisional
/// (4096 until the VRAM probe runs), so the whole point is that changing
/// that one number moves every sub-budget with it.
pub struct ContextBudget {
    /// What context material may occupy.
    ///
    /// Only the content share is modelled so far. The other derived
    /// quantities in 11 §4 -- Map-Reduce chunk size (08), the fallacy-list
    /// prompt (06) -- belong here as their features land; carrying them now
    /// would just be unused fields claiming the design is further along
    /// than it is.
    pub content: u32,
}

impl ContextBudget {
    pub fn from_num_ctx(num_ctx: u32) -> Self {
        let output_reserve = num_ctx / 5; // 20%
        let prompt_reserve = num_ctx / 10; // instructions + the question
        Self { content: num_ctx.saturating_sub(output_reserve + prompt_reserve) }
    }

    /// Budget in characters.
    ///
    /// Assumes one token per character, which under-uses the window for
    /// Korean (roughly 1.4 chars/token in practice). That direction is
    /// deliberate: over-estimating would silently truncate at the model
    /// boundary, which is the failure D-04 exists to remove. Wasting a
    /// little context is recoverable; losing the tail of it is not.
    pub fn content_chars(&self) -> usize {
        self.content as usize
    }

    /// Gives back part of the content budget to something else sharing the
    /// window -- currently the remembered conversation, which rides along
    /// with a wiki query since 0.1.6.
    ///
    /// Without this the two would each size themselves against the full
    /// window and together overflow it, and an overflow is a silent tail
    /// truncation: exactly the failure D-04 exists to remove, just moved
    /// one layer out.
    pub fn reserving(mut self, chars: usize) -> Self {
        self.content = self.content.saturating_sub(chars as u32);
        self
    }
}

// Design §8.2.3 also carries `hint_source` on the index, to record how the
// company was arrived at. Its consumer is the verification agent judging how
// far to trust tier 1, and that agent does not exist yet -- so it is left
// out here rather than stored with nothing reading it.

/// A ranked reference to a page. Holds only what budgeting needs -- the text
/// itself is read from the entries at render time, so there is one copy of
/// it rather than two that can drift.
pub struct WikiSummary {
    pub id: String,
    pub body_required: bool,
    pub body_chars: usize,
    pub summary_chars: usize,
    relevance: usize,
}

/// Pages ranked into the four priority tiers (design §8.2).
pub struct PreflightIndex {
    pub tiers: [Vec<WikiSummary>; 4],
}

/// Splits text into comparable words. Crude on purpose -- this is a ranking
/// hint, not a search engine, and an LLM call here would defeat the reason
/// the preflight can run outside the queue.
fn tokenize(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.chars().count() > 1)
        .map(|w| w.to_lowercase())
        .collect()
}

fn relevance(entry: &WikiEntry, keywords: &[String]) -> usize {
    let haystack = format!(
        "{} {} {}",
        entry.title,
        entry.summary,
        entry.tags.join(" ")
    )
    .to_lowercase();
    keywords.iter().filter(|k| haystack.contains(k.as_str())).count()
}

/// Finds a company the wiki already knows about in the prompt (RD-01, §8.2.3).
///
/// Plain string matching against names already stored -- no LLM, so the
/// preflight stays outside the queue and adds no call to the pipeline.
///
/// The reason this works at all: a company absent from the wiki has no pages
/// to rank into tier 1 anyway, so "no match" and "nothing to prioritise"
/// coincide exactly. There is no case where a guess would have helped.
pub fn match_known_company(entries: &[WikiEntry], prompt: &str) -> Option<CompanyRef> {
    let mut best: Option<&CompanyRef> = None;
    for entry in entries {
        let Some(company) = &entry.company else { continue };
        if !prompt.contains(&company.display_name) {
            continue;
        }
        match best {
            // Longest match wins (TD-09): Korean group names are prefixes of
            // their subsidiaries (`LG` inside `LG에너지솔루션`), so dropping
            // both on a multiple match would throw away the precise one.
            Some(prev) if prev.display_name.chars().count() >= company.display_name.chars().count() => {}
            _ => best = Some(company),
        }
    }
    best.cloned()
}

/// Ranks `entries` for `prompt` into four tiers.
///
/// With no company hint, tiers 1 and 2 stay empty rather than being filled
/// on a guess (TD-07): both are defined as "same subject", and a wrong guess
/// there puts unrelated pages in the layer the answer trusts most -- the
/// silent-wrong shape this whole defect class keeps taking.
pub fn run_preflight(entries: &[WikiEntry], prompt: &str, hint: Option<CompanyRef>) -> PreflightIndex {
    let keywords = tokenize(prompt);
    let mut tiers: [Vec<WikiSummary>; 4] = Default::default();

    for entry in entries {
        let score = relevance(entry, &keywords);
        let same_company = match (&hint, &entry.company) {
            (Some(h), Some(c)) => h.corp_code == c.corp_code,
            _ => false,
        };

        let tier = if same_company {
            // Tier 1 is "trust this now": confirmed, and actually about what
            // was asked. Same company but off-topic drops to tier 2.
            if entry.confidence == crate::wiki::Confidence::Stated && score > 0 {
                0
            } else {
                1
            }
        } else if entry.confidence == crate::wiki::Confidence::Uncertain {
            3
        } else if entry.company.is_none() && score > 0 {
            // Concept pages relevant to the question -- indirect reference.
            2
        } else {
            3
        };

        tiers[tier].push(WikiSummary {
            id: entry.id.clone(),
            body_required: entry.body_required,
            body_chars: entry.body.chars().count(),
            summary_chars: entry.summary.chars().count(),
            relevance: score,
        });
    }

    for tier in &mut tiers {
        tier.sort_by(|a, b| b.relevance.cmp(&a.relevance));
    }

    PreflightIndex { tiers }
}

/// What made it into the context and what did not.
#[derive(Default)]
pub struct RoutedContext {
    pub full_body: Vec<String>,
    pub summary_only: Vec<String>,
    /// Dropped entirely. Must be surfaced in the answer (09 §3.3).
    pub excluded: Vec<String>,
}

/// Fills the budget by priority (09 §3.3).
///
/// Two passes, and the order is the point: pages whose figures cannot
/// survive summarising claim body space first, across all tiers, before any
/// ordinary page gets its body. Otherwise a long tier-1 narrative page could
/// eat the budget and push the financial statement out.
pub fn allocate_budget(index: &PreflightIndex, budget: &ContextBudget) -> RoutedContext {
    let mut routed = RoutedContext::default();
    let mut used = 0usize;
    let limit = budget.content_chars();

    let ordered: Vec<&WikiSummary> = index.tiers.iter().flatten().collect();

    // Pass 1 -- bodies that cannot be replaced by a summary.
    for page in ordered.iter().filter(|p| p.body_required) {
        if used + page.body_chars <= limit {
            used += page.body_chars;
            routed.full_body.push(page.id.clone());
        } else {
            // Not demoted to its summary: for a figures page that would put
            // a number-free stub in front of the model, which is worse than
            // an acknowledged gap (09 §3.1).
            routed.excluded.push(page.id.clone());
        }
    }

    // Pass 2 -- ordinary pages, bodies while they fit.
    let mut needs_summary = Vec::new();
    for page in ordered.iter().filter(|p| !p.body_required) {
        if used + page.body_chars <= limit {
            used += page.body_chars;
            routed.full_body.push(page.id.clone());
        } else {
            needs_summary.push(*page);
        }
    }

    // Pass 3 -- summaries for what missed out. Lossy here, but a prose page
    // still means something in summary form; a figures page does not.
    for page in needs_summary {
        if used + page.summary_chars <= limit {
            used += page.summary_chars;
            routed.summary_only.push(page.id.clone());
        } else {
            routed.excluded.push(page.id.clone());
        }
    }

    routed
}

/// Builds the prompt context from the allocation.
pub fn render_context(entries: &[WikiEntry], routed: &RoutedContext) -> String {
    let find = |id: &String| entries.iter().find(|e| &e.id == id);
    let mut out = String::new();

    for id in &routed.full_body {
        if let Some(e) = find(id) {
            out.push_str(&format!("---\n# {}\n{}\n\n", e.canonical_title(), e.body));
        }
    }
    for id in &routed.summary_only {
        if let Some(e) = find(id) {
            out.push_str(&format!(
                "### {}\n{}\n(태그: {})\n\n",
                e.canonical_title(),
                e.summary,
                e.tags.join(", ")
            ));
        }
    }
    out
}

/// Names the pages left out, for the answer to carry.
///
/// D-04's core claim: an answer that admits what it could not see beats a
/// confident one built on a silently truncated context.
pub fn excluded_notice(entries: &[WikiEntry], routed: &RoutedContext) -> Option<String> {
    if routed.excluded.is_empty() {
        return None;
    }
    let titles: Vec<String> = routed
        .excluded
        .iter()
        .filter_map(|id| entries.iter().find(|e| &e.id == id))
        .map(|e| e.canonical_title())
        .collect();
    Some(format!(
        "컨텍스트 예산이 부족해 다음 문서는 제외했습니다 (요약으로 대체하지 않음): {}",
        titles.join(", ")
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wiki::Confidence;

    fn page(id: &str, body_len: usize, body_required: bool) -> WikiEntry {
        WikiEntry {
            id: id.into(),
            title: id.into(),
            summary: "요약".repeat(5), // 10 chars
            body: "x".repeat(body_len),
            body_required,
            confidence: Confidence::Stated,
            ..Default::default()
        }
    }

    fn budget_of(chars: u32) -> ContextBudget {
        // content = num_ctx - 20% - 10% = 70%
        ContextBudget::from_num_ctx(chars * 10 / 7)
    }

    /// The budget has to move with `num_ctx` -- the provisional 4096 gets
    /// replaced once the VRAM probe runs, and any constant left behind would
    /// silently keep the old sizing (11 §4).
    #[test]
    fn budget_scales_with_num_ctx() {
        // 70% of the window: 100% less 20% for the answer and 10% for the
        // prompt. The ratio is what must hold at any size -- a fixed number
        // here would stop tracking `num_ctx` the moment it is re-measured.
        for num_ctx in [2048u32, 4096, 8192, 32768] {
            let ratio = ContextBudget::from_num_ctx(num_ctx).content as f64 / num_ctx as f64;
            assert!((ratio - 0.7).abs() < 0.01, "content share drifted at num_ctx={num_ctx}");
        }
        // Content must never claim the whole window, or the answer itself
        // gets truncated -- the same silent cut-off in a different place.
        assert!(ContextBudget::from_num_ctx(4096).content < 4096);
    }

    /// 0.1.6: the remembered conversation now shares the window with the
    /// retrieved pages. If the wiki kept sizing against the full budget the
    /// two would overflow together, and an overflow truncates the tail
    /// silently -- the same failure mode D-04 removed, one layer out.
    #[test]
    fn history_takes_its_share_out_of_the_content_budget() {
        let plain = ContextBudget::from_num_ctx(4096);
        let shared = ContextBudget::from_num_ctx(4096).reserving(1000);
        assert_eq!(shared.content_chars(), plain.content_chars() - 1000);

        // A history longer than the whole budget must clamp to zero rather
        // than wrap around into an enormous allowance.
        let swamped = ContextBudget::from_num_ctx(4096).reserving(999_999);
        assert_eq!(swamped.content_chars(), 0);
    }

    /// The D-04 defect itself: a financial page must not be silently traded
    /// for its summary. It either arrives whole or is named as missing.
    #[test]
    fn figures_page_is_excluded_rather_than_summarised() {
        let budget = budget_of(100);
        let entries = vec![page("재무제표", 500, true)];
        let index = run_preflight(&entries, "재무제표", None);
        let routed = allocate_budget(&index, &budget);

        assert!(routed.full_body.is_empty());
        assert!(routed.summary_only.is_empty(), "요약으로 대체하면 숫자가 사라진다");
        assert_eq!(routed.excluded, ["재무제표"]);
        assert!(excluded_notice(&entries, &routed).is_some());
    }

    /// An ordinary page still means something in summary form, so it demotes
    /// instead of vanishing -- the distinction `body_required` encodes.
    #[test]
    fn prose_page_falls_back_to_its_summary() {
        let budget = budget_of(100);
        let entries = vec![page("서술형", 500, false)];
        let index = run_preflight(&entries, "서술형", None);
        let routed = allocate_budget(&index, &budget);

        assert_eq!(routed.summary_only, ["서술형"]);
        assert!(routed.excluded.is_empty());
    }

    /// Required bodies claim space before ordinary ones regardless of tier,
    /// so a long narrative cannot crowd out the statement.
    #[test]
    fn required_bodies_win_the_budget_over_prose() {
        let budget = budget_of(120);
        let entries = vec![page("긴서술", 100, false), page("재무제표", 100, true)];
        let index = run_preflight(&entries, "재무", None);
        let routed = allocate_budget(&index, &budget);

        assert_eq!(routed.full_body, ["재무제표"]);
        assert_eq!(routed.summary_only, ["긴서술"]);
    }

    /// RD-01/TD-07: with no hint, "same subject" cannot be judged, so the
    /// top tiers stay empty instead of being filled with a guess.
    #[test]
    fn tiers_one_and_two_stay_empty_without_a_company_hint() {
        let entries = vec![page("a", 10, false), page("b", 10, false)];
        let index = run_preflight(&entries, "a", None);

        assert!(index.tiers[0].is_empty());
        assert!(index.tiers[1].is_empty());
        // Still reachable -- just not as "most trusted".
        assert_eq!(index.tiers[2].len() + index.tiers[3].len(), 2);
    }

    /// TD-09: the more specific name wins, rather than both being discarded.
    #[test]
    fn longest_company_name_wins_the_match() {
        let mut group = page("g", 10, false);
        group.company = Some(CompanyRef {
            corp_code: "1".into(),
            display_name: "LG".into(),
            stock_code: None,
        });
        let mut sub = page("s", 10, false);
        sub.company = Some(CompanyRef {
            corp_code: "2".into(),
            display_name: "LG에너지솔루션".into(),
            stock_code: None,
        });

        let hit = match_known_company(&[group, sub], "LG에너지솔루션 실적 알려줘").unwrap();
        assert_eq!(hit.corp_code, "2");
    }
}
