#!/usr/bin/env python3
"""ASK-TO PreToolUse hook — rewrites commands to use ASK filters.
Based on RTK's proven hookSpecificOutput format (60-90% savings).
"""
import json, sys, subprocess, os

ASK = os.path.expanduser("~/.local/bin/ask")

try:
    data = json.load(sys.stdin)
except:
    sys.exit(0)

# Claude Code sends tool_input.command (RTK/older) or input.command (newer)
cmd = None
input_key = None
if "tool_input" in data:
    cmd = data.get("tool_input", {}).get("command", "")
    input_key = "tool_input"
elif "input" in data:
    cmd = data.get("input", {}).get("command", "")
    input_key = "input"

if not cmd or not input_key:
    sys.exit(0)

# Skip if already rewritten or absolute path
if cmd.startswith("ask ") or cmd.startswith("/home/") or cmd.startswith("/usr/"):
    sys.exit(0)

# Pass the command as a single arg so pipes/quotes/spaces are preserved.
try:
    result = subprocess.run(
        [ASK, "rewrite", cmd],
        capture_output=True, text=True, timeout=2,
    )
except:
    sys.exit(0)

if result.returncode != 0 or not result.stdout.strip():
    sys.exit(0)

rewritten = result.stdout.strip()
if rewritten == cmd:
    sys.exit(0)

# Only substitute a valid ASK-wrapped command — never banners, help text, or stray output.
if not rewritten.startswith("ask "):
    sys.exit(0)

# Build hookSpecificOutput (RTK proven format)
updated_input = dict(data[input_key])
updated_input["command"] = rewritten

json.dump({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "ASK-TO auto-rewrite",
        "updatedInput": updated_input,
    }
}, sys.stdout)
