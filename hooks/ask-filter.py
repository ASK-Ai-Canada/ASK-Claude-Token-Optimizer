#!/usr/bin/env python3
"""ASK-TO PostToolUse hook — compresses large tool output.
All processing in Python — zero shell escaping issues."""

import json
import subprocess
import sys

ASK = "/home/inzideai/.local/bin/ask"
MIN_OUTPUT_LEN = 500  # Don't compress small outputs

try:
    data = json.load(sys.stdin)
except (json.JSONDecodeError, ValueError):
    sys.exit(0)

output = data.get("output", "")
if not output or len(output) < MIN_OUTPUT_LEN:
    sys.exit(0)

try:
    result = subprocess.run(
        [ASK, "smart"],
        input=output, capture_output=True, text=True, timeout=5,
    )
except Exception:
    sys.exit(0)

if result.returncode != 0 or not result.stdout.strip():
    sys.exit(0)

# Only use compressed version if it's actually shorter
compressed = result.stdout.strip()
if len(compressed) < len(output):
    data["output"] = compressed
    json.dump(data, sys.stdout)
