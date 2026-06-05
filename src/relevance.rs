//! Relevance scoring — rank functions by topic keyword match.
//!
//! Ported from Python score_relevance() and select_context() in code_index/skill.py.

use crate::extract::FunctionInfo;

/// Score each function's relevance to a topic string.
///
/// Scoring rules (mirroring Python):
/// - Name match: +10 per topic word found in function name
/// - Body match: +0.5 per occurrence of topic word in body
/// - Doc comment match: +2.0 per occurrence in doc comments (higher weight)
/// - Call graph: +3 per topic word found in called function names
///
/// Returns Vec of (score, &FunctionInfo) sorted by descending score.
pub fn score_relevance<'a>(
    functions: &'a [FunctionInfo],
    topic: &str,
) -> Vec<(f64, &'a FunctionInfo)> {
    let topic_words: Vec<String> = topic
        .to_lowercase()
        .split_whitespace()
        .map(|s| s.to_string())
        .collect();

    let mut scored: Vec<(f64, &FunctionInfo)> = functions
        .iter()
        .map(|func| {
            let mut score: f64 = 0.0;
            let name_lower = func.name.to_lowercase();

            // Name match (strongest signal)
            for word in &topic_words {
                if name_lower.contains(word.as_str()) {
                    score += 10.0;
                }
            }

            // Body match (weaker signal)
            let body_lower = func.body.to_lowercase();
            for word in &topic_words {
                score += body_lower.matches(word.as_str()).count() as f64 * 0.5;
            }

            // Doc comment match (higher weight than body)
            let doc_lower = func.doc_comment.to_lowercase();
            for word in &topic_words {
                score += doc_lower.matches(word.as_str()).count() as f64 * 2.0;
            }

            // Call graph boost
            for call in &func.calls {
                let call_lower = call.to_lowercase();
                for word in &topic_words {
                    if call_lower.contains(word.as_str()) {
                        score += 3.0;
                    }
                }
            }

            (score, func)
        })
        .collect();

    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    scored
}

/// Select the most relevant functions within a token budget.
///
/// Walks scored functions in order, accumulating tokens until budget exhausted.
/// Skips functions with score <= 0.
pub fn select_context<'a>(
    scored: &'a [(f64, &'a FunctionInfo)],
    budget_tokens: usize,
) -> Vec<(f64, &'a FunctionInfo)> {
    let mut selected = Vec::new();
    let mut used: usize = 0;

    for &(score, func) in scored {
        if score <= 0.0 {
            continue;
        }
        if used + func.tokens > budget_tokens {
            continue;
        }
        selected.push((score, func));
        used += func.tokens;
    }

    selected
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::extract::FunctionInfo;

    fn make_fn(name: &str, body: &str, calls: Vec<&str>) -> FunctionInfo {
        let clean = crate::strip::strip_boilerplate(body);
        FunctionInfo {
            name: name.to_string(),
            file: "test.rs".to_string(),
            line: 1,
            end_line: 10,
            tokens: body.len() / 4,
            clean_tokens: clean.len() / 4,
            body: body.to_string(),
            clean_body: clean,
            calls: calls.into_iter().map(|s| s.to_string()).collect(),
            doc_comment: String::new(),
        }
    }

    #[test]
    fn test_name_match_scores_highest() {
        let fns = vec![
            make_fn("validate_auth", "check token validity", vec![]),
            make_fn("render_page", "display the auth page with login", vec![]),
            make_fn("unrelated", "does something else entirely", vec![]),
        ];

        let scored = score_relevance(&fns, "auth");
        // validate_auth should score highest (name match + body match)
        assert_eq!(scored[0].1.name, "validate_auth");
        assert!(scored[0].0 > scored[1].0);
    }

    #[test]
    fn test_select_context_budget() {
        let fns = vec![
            make_fn("func_a", &"x".repeat(400), vec![]),  // ~100 tokens
            make_fn("func_b", &"security ".repeat(50), vec![]),  // ~112 tokens
            make_fn("func_c", &"security ".repeat(200), vec![]), // ~450 tokens
        ];

        let scored = score_relevance(&fns, "security");
        let selected = select_context(&scored, 200);

        // Should fit some but not all
        let total: usize = selected.iter().map(|(_, f)| f.tokens).sum();
        assert!(total <= 200);
        assert!(!selected.is_empty());
    }

    #[test]
    fn test_zero_score_skipped() {
        let fns = vec![
            make_fn("unrelated", "nothing relevant here", vec![]),
        ];
        let scored = score_relevance(&fns, "security");
        let selected = select_context(&scored, 10000);
        assert!(selected.is_empty());
    }
}
