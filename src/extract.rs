//! Function extraction — regex-based, multi-language.
//!
//! Ported from Python: ASK-Orchestrator/ask-orc/skills/code_index/skill.py

use regex::Regex;
use crate::strip;

// ── Types ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct FunctionInfo {
    pub name: String,
    pub file: String,
    pub line: usize,       // 1-indexed
    pub end_line: usize,   // 1-indexed
    pub body: String,       // full text for audit
    pub clean_body: String, // stripped of boilerplate
    pub calls: Vec<String>,
    pub tokens: usize,      // estimated from full body
    pub clean_tokens: usize, // estimated from clean body
    pub doc_comment: String, // collected doc comments above signature
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Estimate token count: ~4 chars per token (same as Python).
pub fn estimate_tokens(text: &str) -> usize {
    text.len() / 4
}

/// Get the compiled regex pattern for a language extension.
fn get_pattern(lang: &str) -> Option<Regex> {
    match lang {
        "rs" | "rust" => Some(Regex::new(
            r"(?m)^(?:pub\s+)?(?:async\s+)?fn\s+(\w+)\s*(?:<[^>]*>)?\s*\("
        ).unwrap()),

        "py" | "python" => Some(Regex::new(
            r"(?m)^(?:\s*)(?:async\s+)?def\s+(\w+)\s*\("
        ).unwrap()),

        "tsx" => Some(Regex::new(
            r"(?m)(?:export\s+)?(?:default\s+)?function\s+(\w+)\s*\(|(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s+)?\("
        ).unwrap()),

        "jsx" => Some(Regex::new(
            r"(?m)(?:export\s+)?(?:default\s+)?function\s+(\w+)\s*\("
        ).unwrap()),

        "ts" | "typescript" => Some(Regex::new(
            r"(?m)(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(|(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s+)?\("
        ).unwrap()),

        "js" | "javascript" => Some(Regex::new(
            r"(?m)(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(|(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s+)?\("
        ).unwrap()),

        _ => None,
    }
}

/// Collect doc comment lines walking backwards from a given line.
/// Recognizes `///`, `#`, `/**`, `* `, `"""`.
fn collect_doc_comment(lines: &[&str], start_line: usize) -> (usize, String) {
    let mut doc_start = start_line;
    while doc_start > 0 {
        let prev = lines[doc_start - 1].trim();
        if prev.starts_with("///")
            || prev.starts_with('#')
            || prev.starts_with("/**")
            || prev.starts_with("\"\"\"")
            || prev.starts_with("* ")
        {
            doc_start -= 1;
        } else {
            break;
        }
    }

    let doc_lines: Vec<&str> = lines[doc_start..start_line].to_vec();
    let doc = doc_lines.join("\n");
    (doc_start, doc)
}

/// Extract function calls from body text. Returns up to 10 unique call names.
fn extract_calls(body: &str, self_name: &str) -> Vec<String> {
    let call_re = Regex::new(r"(\w+)\s*\(").unwrap();
    let mut seen = std::collections::HashSet::new();
    let mut calls = Vec::new();

    for cap in call_re.captures_iter(body) {
        let name = &cap[1];
        // Skip self, skip type constructors (uppercase first char)
        if name == self_name {
            continue;
        }
        if name.chars().next().map_or(false, |c| c.is_uppercase()) {
            continue;
        }
        if seen.insert(name.to_string()) {
            calls.push(name.to_string());
            if calls.len() >= 10 {
                break;
            }
        }
    }
    calls
}

// ── Core extraction ─────────────────────────────────────────────────────────

/// Extract functions from source content for a given language.
///
/// `filepath` is stored on each FunctionInfo (relative path or label).
/// `content` is the full source text.
/// `lang` is the file extension without dot (e.g. "rs", "py", "tsx").
pub fn extract_functions(filepath: &str, content: &str, lang: &str) -> Vec<FunctionInfo> {
    let pattern = match get_pattern(lang) {
        Some(p) => p,
        None => return Vec::new(),
    };

    let lines: Vec<&str> = content.split('\n').collect();
    let mut functions = Vec::new();

    for mat in pattern.find_iter(content) {
        // Re-run as captures to get group names
        let caps = match pattern.captures(&content[mat.start()..]) {
            Some(c) => c,
            None => continue,
        };

        // Get function name from first non-None capture group
        let name = (1..=caps.len().saturating_sub(1))
            .filter_map(|i| caps.get(i))
            .next()
            .map(|m| m.as_str().to_string());

        let name = match name {
            Some(n) => n,
            None => continue,
        };

        // Skip private helpers (leading underscore, except __init__)
        if name.starts_with('_') && name != "__init__" {
            continue;
        }

        // Compute 0-indexed line number of match start
        let start_line = content[..mat.start()].matches('\n').count();

        // Collect doc comments above the function signature
        let (doc_start, doc_comment) = collect_doc_comment(&lines, start_line);

        // Function end: heuristic — 50 lines max from signature (same as Python)
        let end_line = std::cmp::min(start_line + 50, lines.len());

        // Build raw body (includes doc comments above)
        let raw_body = lines[doc_start..end_line].join("\n");

        // Strip boilerplate for clean version
        let clean_body = strip::strip_boilerplate(&raw_body);

        // Extract calls
        let calls = extract_calls(&raw_body, &name);

        functions.push(FunctionInfo {
            name,
            file: filepath.to_string(),
            line: start_line + 1,   // 1-indexed
            end_line,               // 1-indexed (already past last line)
            tokens: estimate_tokens(&raw_body),
            clean_tokens: estimate_tokens(&clean_body),
            body: raw_body,
            clean_body,
            calls,
            doc_comment,
        });
    }

    functions
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_rust_functions() {
        let code = r#"
use std::io;

/// Add two numbers together.
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

pub async fn fetch_data(url: &str) -> Result<String, Error> {
    let resp = reqwest::get(url).await?;
    Ok(resp.text().await?)
}

fn private_helper() {
    println!("hi");
}
"#;
        let fns = extract_functions("test.rs", code, "rs");
        assert_eq!(fns.len(), 3);
        assert_eq!(fns[0].name, "add");
        assert!(fns[0].doc_comment.contains("Add two numbers"));
        assert_eq!(fns[1].name, "fetch_data");
        assert_eq!(fns[2].name, "private_helper");
    }

    #[test]
    fn test_extract_python_functions() {
        let code = r#"
import os

def hello(name):
    """Say hello."""
    print(f"Hello {name}")

async def fetch(url):
    resp = await aiohttp.get(url)
    return resp
"#;
        let fns = extract_functions("test.py", code, "py");
        assert_eq!(fns.len(), 2);
        assert_eq!(fns[0].name, "hello");
        assert_eq!(fns[1].name, "fetch");
    }

    #[test]
    fn test_extract_typescript_functions() {
        let code = r#"
import React from 'react';

export function UserList({ users }) {
    return <ul>{users.map(u => <li>{u.name}</li>)}</ul>;
}

export const fetchUsers = async (token) => {
    const resp = await fetch('/api/users', { headers: { Authorization: token } });
    return resp.json();
};

const helper = (x) => x * 2;
"#;
        let fns = extract_functions("app.tsx", code, "tsx");
        assert!(fns.len() >= 2);
        assert!(fns.iter().any(|f| f.name == "UserList"));
        assert!(fns.iter().any(|f| f.name == "fetchUsers"));
    }

    #[test]
    fn test_skip_underscore_functions() {
        let code = "def _internal():\n    pass\n\ndef __init__(self):\n    pass\n\ndef public():\n    pass\n";
        let fns = extract_functions("test.py", code, "py");
        let names: Vec<&str> = fns.iter().map(|f| f.name.as_str()).collect();
        assert!(!names.contains(&"_internal"));
        assert!(names.contains(&"__init__"));
        assert!(names.contains(&"public"));
    }

    #[test]
    fn test_estimate_tokens() {
        assert_eq!(estimate_tokens("12345678"), 2);
        assert_eq!(estimate_tokens(""), 0);
    }
}
