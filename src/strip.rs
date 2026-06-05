//! Boilerplate stripping — remove noise lines from function bodies.
//!
//! Ported from Python NOISE_PATTERNS in code_index/skill.py.

use regex::Regex;
use std::sync::LazyLock;

/// Combined noise pattern — lines matching any of these are stripped.
///
/// Matches:
/// - Empty / whitespace-only lines
/// - Lone closing braces `}`
/// - Lone closing parens `)` with optional `;`
/// - Bare `.await` lines
/// - `.bind(` / `.execute(` / `.fetch` chains (sqlx boilerplate)
/// - `use` / `import` / `from ... import` statements
/// - `#[derive(` / `#[serde(` / `#[sqlx(` attributes
/// - `impl` block headers
/// - `pub struct` definitions
static NOISE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?x)
          ^\s*$                         # empty lines
        | ^\s*\}\s*;?\s*$              # lone closing braces
        | ^\s*\)\s*;?\s*$             # lone closing parens
        | ^\s*\.await\??\s*;?\s*$     # bare .await lines
        | ^\s*\.bind\(                 # sqlx .bind() chains
        | ^\s*\.execute\(              # sqlx .execute()
        | ^\s*\.fetch                  # sqlx .fetch_one/all/optional
        | ^\s*use\s+                   # Rust use statements
        | ^\s*import\s+               # JS/TS/Python import
        | ^\s*from\s+\S+\s+import     # Python from...import
        | ^\s*\#\[derive              # derive macros
        | ^\s*\#\[serde               # serde macros
        | ^\s*\#\[sqlx                # sqlx macros
        | ^\s*impl\s+                 # impl block headers
        | ^\s*pub\s+struct\s+         # struct definitions
        "
    ).unwrap()
});

/// Strip boilerplate lines from source code.
///
/// Returns a new string with noise lines removed. Preserves line ordering
/// of non-noise lines.
pub fn strip_boilerplate(content: &str) -> String {
    content
        .lines()
        .filter(|line| !NOISE_RE.is_match(line))
        .collect::<Vec<&str>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strip_empty_and_braces() {
        let input = "let x = 1;\n\n}\n  }\n);";
        let result = strip_boilerplate(input);
        assert_eq!(result, "let x = 1;");
    }

    #[test]
    fn test_strip_use_import() {
        let input = "use std::io;\nimport React from 'react';\nfrom os import path\nlet x = 42;";
        let result = strip_boilerplate(input);
        assert_eq!(result, "let x = 42;");
    }

    #[test]
    fn test_strip_derive() {
        let input = "#[derive(Debug, Clone)]\n#[serde(rename_all = \"camelCase\")]\npub struct Foo {\n    name: String,\n}";
        let result = strip_boilerplate(input);
        assert_eq!(result, "    name: String,");
    }

    #[test]
    fn test_strip_await_bind() {
        let input = "let row = sqlx::query(sql)\n    .bind(id)\n    .bind(name)\n    .fetch_one(&pool)\n    .await?;";
        let result = strip_boilerplate(input);
        assert_eq!(result, "let row = sqlx::query(sql)");
    }

    #[test]
    fn test_preserves_logic() {
        let input = "if x > 0 {\n    return x * 2;\n}\nlet y = compute(x);";
        let result = strip_boilerplate(input);
        // Should keep the logic lines, strip only the closing brace
        assert!(result.contains("if x > 0 {"));
        assert!(result.contains("return x * 2;"));
        assert!(result.contains("let y = compute(x);"));
    }
}
