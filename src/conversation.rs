//! Conversation compression — summarize older chat messages via local inference.
//!
//! Adapted from ASK-APIArena/src/compress.rs (legacy module).
//! Uses OpenAI-compatible /v1/chat/completions endpoint (TabbyAPI, Ollama, vLLM).

use crate::config::Config;
use crate::tokens::estimate_message_tokens;
use reqwest::Client;
use serde::{Deserialize, Serialize};

/// Compression metrics — returned regardless of whether compression happened.
#[derive(Debug, Clone, Serialize)]
pub struct CompressionMetrics {
    /// Original token count (estimated, 4 chars ~ 1 token)
    pub tokens_original: i32,
    /// Token count after compression
    pub tokens_compressed: i32,
    /// Percentage savings
    pub savings_pct: String,
    /// Whether compression actually ran
    pub compressed: bool,
}

/// Request body for POST /v1/compress/conversation
#[derive(Debug, Deserialize)]
pub struct CompressConversationRequest {
    pub messages: Vec<serde_json::Value>,
    #[serde(default = "default_keep_recent")]
    pub keep_recent: usize,
    #[serde(default = "default_threshold")]
    pub threshold: i32,
}

fn default_keep_recent() -> usize { 4 }
fn default_threshold() -> i32 { 2000 }

/// Response body for POST /v1/compress/conversation
#[derive(Debug, Serialize)]
pub struct CompressConversationResponse {
    pub messages: Vec<serde_json::Value>,
    pub metrics: CompressionMetrics,
}

/// Compress a conversation if token count exceeds threshold.
pub async fn compress_conversation(
    client: &Client,
    config: &Config,
    request: &CompressConversationRequest,
) -> CompressConversationResponse {
    let tokens_original = estimate_message_tokens(&request.messages);
    let messages_count = request.messages.len();

    let keep_recent = if request.keep_recent > 0 {
        request.keep_recent
    } else {
        config.server.keep_recent
    };

    let threshold = if request.threshold > 0 {
        request.threshold
    } else {
        config.server.compress_threshold as i32
    };

    // If below threshold or not enough messages, return original
    if tokens_original < threshold || messages_count <= keep_recent + 1 {
        return CompressConversationResponse {
            messages: request.messages.clone(),
            metrics: CompressionMetrics {
                tokens_original,
                tokens_compressed: tokens_original,
                savings_pct: "0.0".to_string(),
                compressed: false,
            },
        };
    }

    // Split messages: keep system prompt + last N messages, compress the rest
    let mut system_msg: Option<&serde_json::Value> = None;
    let mut history: Vec<&serde_json::Value> = Vec::new();

    for msg in &request.messages {
        let role = msg.get("role").and_then(|r| r.as_str()).unwrap_or("");
        if role == "system" {
            system_msg = Some(msg);
        } else {
            history.push(msg);
        }
    }

    if history.len() <= keep_recent {
        return CompressConversationResponse {
            messages: request.messages.clone(),
            metrics: CompressionMetrics {
                tokens_original,
                tokens_compressed: tokens_original,
                savings_pct: "0.0".to_string(),
                compressed: false,
            },
        };
    }

    // Messages to compress (older ones) vs keep (recent ones)
    let split = history.len() - keep_recent;
    let to_compress = &history[..split];
    let to_keep = &history[split..];

    // Build summary prompt for inference
    let history_text: String = to_compress
        .iter()
        .map(|m| {
            let role = m.get("role").and_then(|r| r.as_str()).unwrap_or("unknown");
            let content = match m.get("content") {
                Some(serde_json::Value::String(s)) => s.clone(),
                Some(other) => other.to_string(),
                None => String::new(),
            };
            format!("{}: {}", role, content)
        })
        .collect::<Vec<_>>()
        .join("\n");

    let summary = match summarize_via_inference(client, config, &history_text).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Conversation compression failed, passing through: {e}");
            return CompressConversationResponse {
                messages: request.messages.clone(),
                metrics: CompressionMetrics {
                    tokens_original,
                    tokens_compressed: tokens_original,
                    savings_pct: "0.0".to_string(),
                    compressed: false,
                },
            };
        }
    };

    // Build compressed message list
    let mut compressed_messages: Vec<serde_json::Value> = Vec::new();

    if let Some(sys) = system_msg {
        compressed_messages.push(sys.clone());
    }

    // Insert summary as a user/assistant pair
    compressed_messages.push(serde_json::json!({
        "role": "user",
        "content": format!("[Previous conversation summary]\n{summary}")
    }));
    compressed_messages.push(serde_json::json!({
        "role": "assistant",
        "content": "Understood. I have the conversation context. Please continue."
    }));

    // Append recent messages
    for msg in to_keep {
        compressed_messages.push((*msg).clone());
    }

    let tokens_compressed = estimate_message_tokens(&compressed_messages);
    let savings_pct = if tokens_original == 0 {
        0.0
    } else {
        (1.0 - (tokens_compressed as f64 / tokens_original as f64)) * 100.0
    };

    CompressConversationResponse {
        messages: compressed_messages,
        metrics: CompressionMetrics {
            tokens_original,
            tokens_compressed,
            savings_pct: format!("{:.1}", savings_pct),
            compressed: true,
        },
    }
}

/// Call local inference engine to summarize conversation history.
/// Uses OpenAI-compatible /v1/chat/completions endpoint.
async fn summarize_via_inference(
    client: &Client,
    config: &Config,
    history: &str,
) -> anyhow::Result<String> {
    let url = format!("{}/v1/chat/completions", config.server.inference_url);

    let body = serde_json::json!({
        "model": config.server.inference_model,
        "messages": [
            {
                "role": "system",
                "content": "You are a conversation summarizer. Compress the following conversation into a dense summary that preserves all key facts, decisions, questions asked, and context needed to continue the conversation. Be concise but complete. Output only the summary, no preamble."
            },
            {
                "role": "user",
                "content": history
            }
        ],
        "stream": false,
        "temperature": 0.3,
        "max_tokens": 1024,
    });

    let resp = client
        .post(&url)
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .await?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        anyhow::bail!("Inference engine returned {status}: {text}");
    }

    #[derive(Deserialize)]
    struct Choice {
        message: ChoiceMessage,
    }
    #[derive(Deserialize)]
    struct ChoiceMessage {
        content: String,
    }
    #[derive(Deserialize)]
    struct CompletionResponse {
        choices: Vec<Choice>,
    }

    let parsed: CompletionResponse = resp.json().await?;
    let summary = parsed
        .choices
        .first()
        .map(|c| c.message.content.clone())
        .unwrap_or_else(|| "[Summary unavailable]".to_string());

    Ok(summary)
}
