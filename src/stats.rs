//! Stats tracking — SQLite database for token savings metrics.
//! Located at ~/.ask-token-optimizer/stats.db

use rusqlite::Connection;
use std::path::PathBuf;

/// Detect current model from environment, Claude Code config, or default.
fn detect_model() -> String {
    // 1. Explicit env var (user can set CLAUDE_MODEL=claude-sonnet-4-6)
    if let Ok(m) = std::env::var("CLAUDE_MODEL") {
        if !m.is_empty() { return m; }
    }
    // 2. Read from Claude Code config if available
    if let Ok(home) = std::env::var("HOME") {
        let config = std::path::Path::new(&home).join(".claude").join(".model");
        if let Ok(m) = std::fs::read_to_string(config) {
            let m = m.trim().to_string();
            if !m.is_empty() { return m; }
        }
    }
    // 3. Default to Opus (most expensive = conservative savings estimate)
    "claude-opus-4-6".to_string()
}

/// Real input price per million tokens. Source: platform.claude.com/docs 2026-03-29.
/// Returns (input_$/MTok, output_$/MTok).
fn model_pricing(model: &str) -> (f64, f64) {
    match model {
        // ═══ Claude 4.6 (current) ═══
        "claude-opus-4-6"               => (5.00, 25.00),
        "claude-sonnet-4-6"             => (3.00, 15.00),
        "claude-haiku-4-5-20251001" | "claude-haiku-4-5" => (1.00, 5.00),

        // ═══ Claude 4.5 (legacy) ═══
        "claude-sonnet-4-5-20250929" | "claude-sonnet-4-5" => (3.00, 15.00),
        "claude-opus-4-5-20251101" | "claude-opus-4-5"     => (5.00, 25.00),

        // ═══ Claude 4.1 (legacy) ═══
        "claude-opus-4-1-20250805" | "claude-opus-4-1"     => (15.00, 75.00),

        // ═══ Claude 4.0 (legacy) ═══
        "claude-sonnet-4-20250514" | "claude-sonnet-4-0"   => (3.00, 15.00),
        "claude-opus-4-20250514" | "claude-opus-4-0"       => (15.00, 75.00),

        // ═══ Claude 3 (deprecated) ═══
        "claude-3-haiku-20240307"       => (0.25, 1.25),

        // Default: current Opus (most common for Claude Code)
        _ => (5.00, 25.00),
    }
}

/// Input price per million tokens for a model.
fn model_input_price(model: &str) -> f64 {
    model_pricing(model).0
}

fn db_path() -> PathBuf {
    let dir = dirs_home().join(".ask-token-optimizer");
    std::fs::create_dir_all(&dir).ok();
    dir.join("stats.db")
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn open_db() -> Option<Connection> {
    let conn = Connection::open(db_path()).ok()?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS compressions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL DEFAULT (datetime('now')),
            content_type TEXT NOT NULL,
            tokens_in INTEGER NOT NULL,
            tokens_out INTEGER NOT NULL,
            savings_pct REAL NOT NULL,
            session_id TEXT
        );
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            started TEXT NOT NULL DEFAULT (datetime('now')),
            total_in INTEGER NOT NULL DEFAULT 0,
            total_out INTEGER NOT NULL DEFAULT 0,
            compressions INTEGER NOT NULL DEFAULT 0
        );"
    ).ok()?;
    Some(conn)
}

/// Record a compression event.
pub fn record(content_type: &str, tokens_in: usize, tokens_out: usize, savings_pct: f64) {
    let Some(conn) = open_db() else { return };
    let session = std::env::var("CLAUDE_SESSION_ID").unwrap_or_default();
    let model = detect_model();
    // Add model column if it doesn't exist (migration)
    conn.execute("ALTER TABLE compressions ADD COLUMN model TEXT DEFAULT ''", []).ok();
    conn.execute(
        "INSERT INTO compressions (content_type, tokens_in, tokens_out, savings_pct, session_id, model) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![content_type, tokens_in as i64, tokens_out as i64, savings_pct, session, model],
    ).ok();
}

/// Print lifetime stats to stdout.
pub fn print_stats() {
    let Some(conn) = open_db() else {
        println!("No stats database found.");
        return;
    };

    let total_in: i64 = conn
        .query_row("SELECT COALESCE(SUM(tokens_in), 0) FROM compressions", [], |r| r.get(0))
        .unwrap_or(0);
    let total_out: i64 = conn
        .query_row("SELECT COALESCE(SUM(tokens_out), 0) FROM compressions", [], |r| r.get(0))
        .unwrap_or(0);
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM compressions", [], |r| r.get(0))
        .unwrap_or(0);
    let saved = total_in - total_out;
    let pct = if total_in > 0 { (saved as f64 / total_in as f64) * 100.0 } else { 0.0 };

    // Dynamic pricing per model — detect from env or config
    let model = detect_model();
    let price_per_mtok = model_input_price(&model);
    let cost_saved = (saved as f64 / 1_000_000.0) * price_per_mtok;

    // Last 24h
    let today_in: i64 = conn
        .query_row("SELECT COALESCE(SUM(tokens_in), 0) FROM compressions WHERE timestamp > datetime('now', '-1 day')", [], |r| r.get(0))
        .unwrap_or(0);
    let today_out: i64 = conn
        .query_row("SELECT COALESCE(SUM(tokens_out), 0) FROM compressions WHERE timestamp > datetime('now', '-1 day')", [], |r| r.get(0))
        .unwrap_or(0);
    let today_saved = today_in - today_out;

    println!("═══════════════════════════════════════════════");
    println!(" ASK-Token-Optimizer — Savings Report");
    println!("═══════════════════════════════════════════════");
    println!("  Model:           {} (${:.2}/MTok)", model, price_per_mtok);
    println!("  Compressions:    {}", count);
    println!("  Tokens In:       {}", total_in);
    println!("  Tokens Out:      {}", total_out);
    println!("  Tokens Saved:    {} ({:.1}%)", saved, pct);
    println!("  Est. Cost Saved: ${:.4} USD", cost_saved);
    println!();
    println!("  Last 24h:        {} → {} ({} saved)", today_in, today_out, today_saved);
    println!("  Database:        {}", db_path().display());
    println!();
    println!("  Set CLAUDE_MODEL env var or ~/.claude/.model to change pricing.");
    println!("═══════════════════════════════════════════════");
}
