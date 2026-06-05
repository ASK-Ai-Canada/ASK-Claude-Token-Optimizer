#!/usr/bin/env bash
# ASK-Token-Optimizer — Setup Script
#
# Installs the token optimizer + companion Claude Code hooks on Linux / macOS / Pi4.
# Windows: see INSTALL-WINDOWS.md (native PowerShell — no WSL needed).
#
# Usage (inside the unpacked SDK directory):
#   ./setup.sh
#
# Optional: point at your own source mirror by exporting REPO_URL before running:
#   REPO_URL=git@github.com:your-org/ASK-Token-Optimizer.git ./setup.sh
#
# What it does:
#   1. Detects platform (Linux / macOS / Pi4)
#   2. Prefers the bundled pre-built binary in builds/<platform>/
#      Falls back to cargo build --release if Rust is installed
#   3. Installs the binary to $HOME/.local/bin/ask
#   4. Copies the hook templates to $HOME/.claude/hooks/
#      You can then merge them into your settings.json or customize them.
#   5. Verifies install with `ask --version` and `ask gain`

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
HOOK_DIR="${HOME}/.claude/hooks"
BINARY_NAME="ask-token-optimizer"
SHORT_ALIAS="ask"
REPO_URL="${REPO_URL:-}"

echo "=== ASK Token Optimizer Setup ==="

# ─── License acceptance (LICENSE §0: display + accept before install) ───────
ACCEPT="${ASK_ACCEPT_LICENSE:-0}"
for a in "$@"; do [ "$a" = "--accept-license" ] && ACCEPT=1; done
if [ "$ACCEPT" != "1" ]; then
  echo
  echo "  ASK Token Optimizer — Dual License (Community + Commercial)"
  echo "  • Free for individuals and companies under USD \$100k annual gross revenue."
  echo "  • Companies at or above USD \$100k need a paid Commercial License for business use."
  echo "  • Full terms: see the LICENSE file in this directory. Governing law: Canada."
  echo
  if [ -t 0 ]; then
    printf "  Type 'accept' to agree to the LICENSE and continue: "
    read -r reply
    [ "$reply" = "accept" ] || { echo "  License not accepted. Aborting."; exit 1; }
  else
    echo "  Non-interactive shell: re-run with --accept-license (or ASK_ACCEPT_LICENSE=1) to agree."
    exit 1
  fi
fi

ARCH=$(uname -m)
OS=$(uname -s)
echo "Platform: ${OS} ${ARCH}"

case "${OS}-${ARCH}" in
  Linux-x86_64)   PLATFORM_DIR="builds/linux-x86_64";   PLATFORM="linux-amd64" ;;
  Linux-aarch64)  PLATFORM_DIR="builds/linux-arm64";    PLATFORM="linux-arm64 (Pi4)" ;;
  Darwin-x86_64)  PLATFORM_DIR="builds/macos-x86_64";   PLATFORM="macos-x86_64 (Intel)" ;;
  Darwin-arm64)   PLATFORM_DIR="builds/macos-arm64";    PLATFORM="macos-arm64 (Apple Silicon)" ;;
  MINGW*|MSYS*)
    echo "Windows detected. Use INSTALL-WINDOWS.md for native PowerShell install."
    exit 1
    ;;
  *)
    echo "Unsupported platform: ${OS}-${ARCH}"
    exit 1
    ;;
esac

mkdir -p "${INSTALL_DIR}"

# 1. Prefer bundled pre-built binary
if [ -x "${PLATFORM_DIR}/${BINARY_NAME}" ]; then
  echo "Using bundled pre-built binary at ${PLATFORM_DIR}/${BINARY_NAME}"
  cp "${PLATFORM_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
  chmod +x "${INSTALL_DIR}/${BINARY_NAME}"

# 2. Fall back to cargo build
elif command -v cargo &>/dev/null; then
  echo "No pre-built binary for ${PLATFORM} — building from source..."
  if [ ! -f "Cargo.toml" ] || ! grep -q "ask-token-optimizer" Cargo.toml; then
    if [ -n "${REPO_URL}" ]; then
      echo "Cloning ${REPO_URL}..."
      TMPDIR=$(mktemp -d)
      git clone --depth 1 "${REPO_URL}" "${TMPDIR}/src"
      cd "${TMPDIR}/src"
    else
      echo "ERROR: Run this from the SDK directory, or export REPO_URL."
      exit 1
    fi
  fi
  cargo build --release 2>&1 | tail -3
  # Cargo emits the binary as `ask` (per [[bin]] in Cargo.toml); rename on copy.
  cp "target/release/ask" "${INSTALL_DIR}/${BINARY_NAME}"
  chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
else
  echo "ERROR: No pre-built binary for ${PLATFORM} and no Rust toolchain."
  echo "Install Rust:  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
  exit 1
fi

# Short-alias symlink for ergonomic invocation: `ask` -> `ask-token-optimizer`
ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "${INSTALL_DIR}/${SHORT_ALIAS}"

# Stage hook templates (the ones in hooks/ are reference templates;
# customers customize and wire them into their own settings.json)
mkdir -p "${HOOK_DIR}"
if [ -d hooks ]; then
  for f in hooks/*.sh hooks/*.py; do
    [ -e "$f" ] || continue
    cp "$f" "${HOOK_DIR}/"
    chmod +x "${HOOK_DIR}/$(basename "$f")"
  done
  echo "Hook templates staged in ${HOOK_DIR}/"
  echo "Wire them into ~/.claude/settings.json — see README.md > 'Hook Wiring'."
fi

echo
echo "=== Verification ==="
"${INSTALL_DIR}/${BINARY_NAME}" --version
echo
echo "Token-savings probe:"
"${INSTALL_DIR}/${BINARY_NAME}" gain || true

# ─── PATH check ──────────────────────────────────────────────────────────────
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *) echo
     echo "  ⚠  ${INSTALL_DIR} is not on your PATH."
     echo "     Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
     echo "       export PATH=\"\$HOME/.local/bin:\$PATH\""
     echo "     Then restart your shell, or run: export PATH=\"\$HOME/.local/bin:\$PATH\""
     ;;
esac

# ─── Hook auto-wire ──────────────────────────────────────────────────────────
SETTINGS_CANDIDATES=(
  "${HOME}/.claude/settings.json"
  "${HOME}/.config/claude/settings.json"
)
SETTINGS=""
for f in "${SETTINGS_CANDIDATES[@]}"; do
  [ -f "$f" ] && SETTINGS="$f" && break
done

echo
echo "=== Claude Code hook wiring ==="
if [ -z "$SETTINGS" ]; then
  echo "  Claude Code settings.json not found."
  echo "  When you start Claude Code it will be created; then re-run:"
  echo "    ${INSTALL_DIR}/${BINARY_NAME} hooks install"
  echo "  Or add the hooks manually — see README.md."
else
  # Check if already wired
  if grep -q "ask-rewrite" "$SETTINGS" 2>/dev/null; then
    echo "  ✓ Hooks already present in ${SETTINGS}"
  else
    if [ -t 0 ]; then
      printf "  Wire the optimizer hooks into %s now? [y/N] " "$SETTINGS"
      read -r wire
    else
      wire="n"
    fi
    if [ "$wire" = "y" ] || [ "$wire" = "Y" ]; then
      # Back up first
      cp "$SETTINGS" "${SETTINGS}.bak.$(date +%s)"
      # Use python3 to merge hooks (safe JSON manipulation)
      python3 - "$SETTINGS" "$HOOK_DIR" <<'PYEOF'
import json, sys, os
settings_path = sys.argv[1]
hook_dir      = sys.argv[2]

with open(settings_path) as f:
    cfg = json.load(f)

hooks = cfg.setdefault("hooks", {})

pre  = hooks.setdefault("PreToolUse",  [])
post = hooks.setdefault("PostToolUse", [])

rewrite_cmd = os.path.join(hook_dir, "ask-rewrite.sh")
filter_cmd  = os.path.join(hook_dir, "ask-filter.sh")

def already_wired(entries, cmd):
    return any(
        h.get("command","").endswith(os.path.basename(cmd))
        for entry in entries
        for h in entry.get("hooks", [])
    )

if not already_wired(pre, rewrite_cmd):
    pre.append({"matcher":"Bash","hooks":[{"type":"command","command":rewrite_cmd}]})

if not already_wired(post, filter_cmd):
    post.append({"matcher":"Bash","hooks":[{"type":"command","command":filter_cmd}]})

with open(settings_path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("  ✓ Hooks wired into", settings_path)
PYEOF
    else
      echo "  Skipped. To wire later, add to ${SETTINGS}:"
      echo "    \"hooks\": {"
      echo "      \"PreToolUse\":  [{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"${HOOK_DIR}/ask-rewrite.sh\"}]}],"
      echo "      \"PostToolUse\": [{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"${HOOK_DIR}/ask-filter.sh\"}]}]"
      echo "    }"
    fi
  fi
fi

echo
echo "=== Done ==="
echo "  Binary:       ${INSTALL_DIR}/${BINARY_NAME}"
echo "  Alias:        ${INSTALL_DIR}/${SHORT_ALIAS}"
echo "  Hooks:        ${HOOK_DIR}/"
echo
echo "  Restart Claude Code, then run: ask gain"
