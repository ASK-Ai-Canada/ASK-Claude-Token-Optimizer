//! Output filtering — rule-based compression for CLI, log, and JSON content.
//!
//! The OMNI concept: strip noise from structured output without inference calls.

use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

/// Request body for POST /v1/compress/output
#[derive(Debug, Deserialize)]
pub struct CompressOutputRequest {
    pub content: String,
    pub content_type: String, // "cli" | "log" | "json"
}

/// Metrics for output compression
#[derive(Debug, Serialize)]
pub struct OutputMetrics {
    pub original_tokens: usize,
    pub compressed_tokens: usize,
    pub savings_pct: String,
}

/// Response body for POST /v1/compress/output
#[derive(Debug, Serialize)]
pub struct CompressOutputResponse {
    pub content: String,
    pub metrics: OutputMetrics,
}

/// Estimate tokens (~4 chars per token)
fn estimate_tokens(text: &str) -> usize {
    text.len() / 4
}

// ── ANSI / CLI patterns ────────────────────────────────────────────────────

static ANSI_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\x1b\[[0-9;]*[a-zA-Z]").unwrap()
});

static PROGRESS_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?m)^.*[\|/\-\\]?\s*\d+%.*$|^.*\[=+>?\s*\].*$|^.*\.\.\.\s*$").unwrap()
});

static MULTI_BLANK_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\n{3,}").unwrap()
});

static MULTI_SPACE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"[ \t]{2,}").unwrap()
});

// ── Log patterns ───────────────────────────────────────────────────────────

static LOG_DEBUG_TRACE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?mi)^\s*\d{4}[-/]\d{2}[-/]\d{2}[T ]?\d{2}:\d{2}:\d{2}.*?\b(DEBUG|TRACE)\b.*$|(?mi)^\s*(DEBUG|TRACE)\b.*$").unwrap()
});

static LOG_TIMESTAMP_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?m)^\s*\d{4}[-/]\d{2}[-/]\d{2}[T ]?\d{2}:\d{2}:\d{2}").unwrap()
});

// ── Compress dispatcher ────────────────────────────────────────────────────

pub fn compress_output(request: &CompressOutputRequest) -> CompressOutputResponse {
    let original_tokens = estimate_tokens(&request.content);

    let compressed = match request.content_type.as_str() {
        "cli" => compress_cli(&request.content),
        "log" => compress_log(&request.content),
        "json" => compress_json(&request.content),
        _ => request.content.clone(), // unknown type — passthrough
    };

    let compressed_tokens = estimate_tokens(&compressed);
    let savings = if original_tokens == 0 {
        0.0
    } else {
        (1.0 - (compressed_tokens as f64 / original_tokens as f64)) * 100.0
    };

    CompressOutputResponse {
        content: compressed,
        metrics: OutputMetrics {
            original_tokens,
            compressed_tokens,
            savings_pct: format!("{:.1}", savings),
        },
    }
}

// ── CLI compression ────────────────────────────────────────────────────────

/// Strip ANSI codes, progress bars, empty lines, repeated whitespace.
fn compress_cli(content: &str) -> String {
    // Strip ANSI escape codes
    let clean = ANSI_RE.replace_all(content, "");

    // Strip progress bar lines
    let clean = PROGRESS_RE.replace_all(&clean, "");

    // Collapse multiple blank lines to one
    let clean = MULTI_BLANK_RE.replace_all(&clean, "\n\n");

    // Collapse repeated whitespace within lines
    let lines: Vec<String> = clean
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| MULTI_SPACE_RE.replace_all(line, " ").to_string())
        .collect();

    lines.join("\n")
}

// ── Log compression ────────────────────────────────────────────────────────

/// Keep ERROR/WARN/INFO lines, strip DEBUG/TRACE, deduplicate repeated messages.
fn compress_log(content: &str) -> String {
    // Remove DEBUG/TRACE lines
    let clean = LOG_DEBUG_TRACE_RE.replace_all(content, "");

    // Deduplicate consecutive identical messages (ignoring timestamps)
    let mut result_lines: Vec<String> = Vec::new();
    let mut prev_message = String::new();
    let mut dup_count: usize = 0;

    for line in clean.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        // Extract message part (strip timestamp prefix if present)
        let message_part = if LOG_TIMESTAMP_RE.is_match(trimmed) {
            // Find the end of the timestamp+level and get the message
            let parts: Vec<&str> = trimmed.splitn(4, ' ').collect();
            if parts.len() >= 4 {
                parts[3..].join(" ")
            } else {
                trimmed.to_string()
            }
        } else {
            trimmed.to_string()
        };

        if message_part == prev_message && !prev_message.is_empty() {
            dup_count += 1;
        } else {
            if dup_count > 0 {
                result_lines.push(format!("  ... repeated {} more time(s)", dup_count));
            }
            result_lines.push(line.to_string());
            prev_message = message_part;
            dup_count = 0;
        }
    }

    if dup_count > 0 {
        result_lines.push(format!("  ... repeated {} more time(s)", dup_count));
    }

    result_lines.join("\n")
}

// ── JSON compression ───────────────────────────────────────────────────────

/// Strip null values, empty arrays/objects, flatten deeply nested structures.
fn compress_json(content: &str) -> String {
    match serde_json::from_str::<serde_json::Value>(content) {
        Ok(value) => {
            let cleaned = strip_json_nulls(&value, 0);
            serde_json::to_string(&cleaned).unwrap_or_else(|_| content.to_string())
        }
        Err(_) => content.to_string(), // not valid JSON — passthrough
    }
}

/// Recursively strip null values, empty arrays, and empty objects from JSON.
fn strip_json_nulls(value: &serde_json::Value, depth: usize) -> serde_json::Value {
    match value {
        serde_json::Value::Null => serde_json::Value::Null,
        serde_json::Value::Object(map) => {
            let cleaned: serde_json::Map<String, serde_json::Value> = map
                .iter()
                .filter(|(_, v)| !v.is_null())
                .filter(|(_, v)| !is_empty_collection(v))
                .map(|(k, v)| (k.clone(), strip_json_nulls(v, depth + 1)))
                .collect();
            serde_json::Value::Object(cleaned)
        }
        serde_json::Value::Array(arr) => {
            let cleaned: Vec<serde_json::Value> = arr
                .iter()
                .filter(|v| !v.is_null())
                .filter(|v| !is_empty_collection(v))
                .map(|v| strip_json_nulls(v, depth + 1))
                .collect();
            serde_json::Value::Array(cleaned)
        }
        other => other.clone(),
    }
}

/// Check if a value is an empty array or empty object.
fn is_empty_collection(value: &serde_json::Value) -> bool {
    match value {
        serde_json::Value::Array(arr) => arr.is_empty(),
        serde_json::Value::Object(map) => map.is_empty(),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compress_cli_strips_ansi() {
        let input = "\x1b[32mSuccess\x1b[0m: built project\n\n\n\nDone.";
        let req = CompressOutputRequest {
            content: input.to_string(),
            content_type: "cli".to_string(),
        };
        let resp = compress_output(&req);
        assert!(!resp.content.contains("\x1b["));
        assert!(resp.content.contains("Success"));
        assert!(resp.content.contains("Done."));
    }

    #[test]
    fn test_compress_cli_strips_progress() {
        let input = "Building...\nProgress: 50%\n[=====>     ] 50%\nCompiling main.rs";
        let req = CompressOutputRequest {
            content: input.to_string(),
            content_type: "cli".to_string(),
        };
        let resp = compress_output(&req);
        assert!(resp.content.contains("Compiling main.rs"));
    }

    #[test]
    fn test_compress_log_strips_debug() {
        let input = "2026-03-27 10:00:00 INFO Starting server\n2026-03-27 10:00:01 DEBUG Connection pool init\n2026-03-27 10:00:02 ERROR Failed to bind port";
        let req = CompressOutputRequest {
            content: input.to_string(),
            content_type: "log".to_string(),
        };
        let resp = compress_output(&req);
        assert!(resp.content.contains("INFO"));
        assert!(resp.content.contains("ERROR"));
        assert!(!resp.content.contains("DEBUG Connection pool"));
    }

    #[test]
    fn test_compress_json_strips_nulls() {
        let input = r#"{"name": "test", "value": null, "items": [], "data": {"key": "val", "empty": {}}}"#;
        let req = CompressOutputRequest {
            content: input.to_string(),
            content_type: "json".to_string(),
        };
        let resp = compress_output(&req);
        let parsed: serde_json::Value = serde_json::from_str(&resp.content).unwrap();
        assert!(parsed.get("value").is_none());
        assert!(parsed.get("items").is_none());
        assert!(parsed.get("name").is_some());
        let data = parsed.get("data").unwrap().as_object().unwrap();
        assert!(data.get("empty").is_none());
        assert!(data.get("key").is_some());
    }

    #[test]
    fn test_compress_json_invalid_passthrough() {
        let input = "this is not json";
        let req = CompressOutputRequest {
            content: input.to_string(),
            content_type: "json".to_string(),
        };
        let resp = compress_output(&req);
        assert_eq!(resp.content, input);
    }

    #[test]
    fn test_unknown_type_passthrough() {
        let input = "some content";
        let req = CompressOutputRequest {
            content: input.to_string(),
            content_type: "unknown".to_string(),
        };
        let resp = compress_output(&req);
        assert_eq!(resp.content, input);
    }

    #[test]
    fn test_metrics_calculation() {
        let input = "\x1b[31m".repeat(100) + "hello";
        let req = CompressOutputRequest {
            content: input,
            content_type: "cli".to_string(),
        };
        let resp = compress_output(&req);
        assert!(resp.metrics.compressed_tokens < resp.metrics.original_tokens);
    }
}
