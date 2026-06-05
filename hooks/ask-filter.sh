#!/usr/bin/env bash
# ASK-TO PostToolUse — compresses tool output via Claude Code JSON protocol
# The binary reads {"tool":"Bash","input":{...},"output":"..."} from stdin,
# compresses the output field, and writes modified JSON to stdout.
OPTIMIZER="$HOME/.local/bin/ask"
[ ! -x "$OPTIMIZER" ] && exit 0
exec "$OPTIMIZER" --hook
