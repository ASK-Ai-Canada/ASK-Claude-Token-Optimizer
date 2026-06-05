/// Estimate token count for a text string (~4 chars per token).
pub fn estimate_tokens(text: &str) -> usize {
    (text.len() as f64 / 4.0).ceil() as usize
}

/// Estimate total token count for an array of chat messages.
///
/// Each message is expected to be a JSON object with a "content" field.
pub fn estimate_message_tokens(messages: &[serde_json::Value]) -> i32 {
    let chars: usize = messages
        .iter()
        .map(|m| match m.get("content") {
            Some(serde_json::Value::String(s)) => s.len(),
            Some(other) => other.to_string().len(),
            None => 0,
        })
        .sum();
    (chars / 4) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_estimate_tokens() {
        assert_eq!(estimate_tokens("12345678"), 2);
        assert_eq!(estimate_tokens(""), 0);
        assert_eq!(estimate_tokens("hello world!!"), 4); // 13 chars, ceil(13/4) = 4
        assert_eq!(estimate_tokens("abcd"), 1);          // exact boundary
    }

    #[test]
    fn test_estimate_message_tokens() {
        let msgs = vec![
            serde_json::json!({"role": "user", "content": "Hello world"}),
            serde_json::json!({"role": "assistant", "content": "Hi there!"}),
        ];
        let tokens = estimate_message_tokens(&msgs);
        // "Hello world" = 11 chars, "Hi there!" = 9 chars => 20/4 = 5
        assert_eq!(tokens, 5);
    }

    #[test]
    fn test_estimate_message_tokens_empty() {
        let msgs: Vec<serde_json::Value> = vec![];
        assert_eq!(estimate_message_tokens(&msgs), 0);
    }

    #[test]
    fn test_estimate_message_tokens_no_content() {
        let msgs = vec![serde_json::json!({"role": "system"})];
        assert_eq!(estimate_message_tokens(&msgs), 0);
    }
}
