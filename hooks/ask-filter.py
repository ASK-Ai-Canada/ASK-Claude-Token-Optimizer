#!/usr/bin/env python3
"""ASK-TO PostToolUse hook — compresses large tool output.
All processing in Python — zero shell escaping issues."""

import os
import subprocess
import sys

ASK = os.path.expanduser("~/.local/bin/ask")

if not os.path.isfile(ASK):
    sys.exit(0)

try:
    raw = sys.stdin.read()
except Exception:
    sys.exit(0)

if len(raw) < 500:
    sys.exit(0)

try:
    result = subprocess.run(
        [ASK, "--hook"],
        input=raw, capture_output=True, text=True, timeout=5,
    )
except Exception:
    sys.exit(0)

if result.returncode == 0 and result.stdout.strip():
    sys.stdout.write(result.stdout)
