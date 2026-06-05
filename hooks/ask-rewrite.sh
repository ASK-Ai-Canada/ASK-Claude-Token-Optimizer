#!/usr/bin/env bash
# ASK Token Optimizer — PreToolUse hook
# Rewrites Bash commands so output is routed through the optimizer's filters
# before Claude Code sees it. Returns Claude Code's canonical
# hookSpecificOutput envelope so the rewritten command runs in place.
exec python3 "$HOME/.claude/hooks/ask-rewrite.py"
