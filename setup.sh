#!/usr/bin/env bash
# ASK Token Optimizer — installer (macOS / Linux / Pi4).
# Gate: clickwrap + register → binary fetch → PATH + hook wire.
set -euo pipefail

ASK_HOME="${ASK_HOME:-$HOME/.ask}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HOOKS_DIR="${HOOKS_DIR:-$HOME/.claude/hooks}"
LICENSE_JSON="$ASK_HOME/license.json"
REGISTER_URL="${ATO_REGISTER_URL:-https://api.ask-ai.ca/v1/ato}"
GITHUB_RAW="https://raw.githubusercontent.com/ASK-Ai-Canada/ASK-Claude-Token-Optimizer/main"
REPO_SLUG="ASK-Ai-Canada/ASK-Claude-Token-Optimizer"
EULA_VERSION="1.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say(){ printf '%s\n' "$*"; }
err(){ printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok(){ printf '\033[32m✓\033[0m %s\n' "$*"; }

# 1. EULA clickwrap ----------------------------------------------------------------
LIC="$SCRIPT_DIR/LICENSE"
[ -f "$LIC" ] || LIC="$SCRIPT_DIR/../LICENSE-current-v1.1.txt"
if [ -f "$LIC" ]; then ${PAGER:-less} "$LIC" 2>/dev/null || cat "$LIC"; fi
say ""
read -r -p "Do you accept the ASK Token Optimizer license? Type 'I AGREE' to continue: " A
[ "$A" = "I AGREE" ] || { err "Declined — not installed."; exit 1; }

# 2. identity + revenue self-attestation -------------------------------------------
read -r -p "Work email (for your free license + weekly savings report): " EMAIL
[ -n "$EMAIL" ] && [[ "$EMAIL" == *@* ]] || { err "A valid email is required."; exit 1; }
read -r -p "Full name (optional, press Enter to skip): " FULLNAME
read -r -p "Is your organization's annual gross revenue UNDER USD \$100,000? [Y/n]: " R
if [[ "${R:-Y}" =~ ^[Nn] ]]; then
  TIER="commercial"
  say ""
  say "→ Business use at or above \$100k runs on a commercial subscription:"
  say "  ASK Token Optimizer — CAD \$25 per seat / year (first month FREE)."
  read -r -p "Company / organization name: " COMPANY
  read -r -p "Number of seats: " SEATS
  [[ "$SEATS" =~ ^[0-9]+$ ]] || SEATS=1
  # Mandatory billing currency — CAD (adds 15% HST) or USD (foreign sale, no CA tax). No default.
  CURRENCY=""
  while [ "$CURRENCY" != "cad" ] && [ "$CURRENCY" != "usd" ]; do
    read -r -p "Billing currency — type CAD or USD (required): " _C
    CURRENCY="$(printf '%s' "$_C" | tr '[:upper:]' '[:lower:]')"
    [ "$CURRENCY" != "cad" ] && [ "$CURRENCY" != "usd" ] && say "  Please type CAD or USD."
  done
  YEARLY=$(( 25 * SEATS ))
  say ""
  if [ "$CURRENCY" = "cad" ]; then
    say "  Plan: CAD \$25 / seat / year x ${SEATS} seat(s) = CAD \$${YEARLY} + 15% HST / year."
  else
    say "  Plan: USD \$25 / seat / year x ${SEATS} seat(s) = USD \$${YEARLY} / year (no CA tax)."
  fi
  say "  ★ Your first month is FREE — no charge for 30 days; cancel anytime before then."
  say "  You're active immediately — no card needed to use it. We'll email ${EMAIL} a billing-setup link (forwardable to your billing team; invoicing available). Questions: licensing@ask-ai.ca."
else
  TIER="free"
  COMPANY=""; SEATS=""; CURRENCY=""
fi

# 3. telemetry — community: always on (the exchange for free use); paid: optional, default on
if [ "$TIER" = "free" ]; then
  TELEMETRY="on"
  say ""
  say "  Help us improve — anonymous savings stats keep the free tier free."
  say "  Private by design: only the totals you save are shared. (opt-out is a commercial-license benefit)"
else
  # default ON; soft opt-out (Enter keeps it enabled)
  TELEMETRY="on"
  say ""
  say "  [x] Help us improve — share anonymous savings stats. Private by design: only the totals you save."
  read -r -p "      Press Enter to keep enabled, or type 'no' to opt out: " _TO
  [[ "${_TO}" =~ ^[Nn] ]] && TELEMETRY="off"
fi

# 4. register (POST → ZoneMTA email + record; non-fatal if offline) ----------------
# machine id — hash-tool fallback chain (shasum is perl, absent on minimal Linux)
MACHINE_ID="$( (hostname; uname -a) 2>/dev/null | { shasum 2>/dev/null || sha1sum 2>/dev/null || md5sum 2>/dev/null || cat; } | cut -c1-16 | tr -cd 'a-zA-Z0-9._-' )"
[ -n "$MACHINE_ID" ] || MACHINE_ID="unknown"
OS="$(uname -s)"; NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
PLAN="$([ "$TIER" = commercial ] && echo seat-25-yearly || echo free)"
PAYLOAD=$(printf '{"email":"%s","name":"%s","tier":"%s","company":"%s","seats":"%s","currency":"%s","plan":"%s","telemetry":"%s","eula_version":"%s","accepted_at":"%s","machine_id":"%s","os":"%s","ver":"INSTALLER"}' \
  "$EMAIL" "$FULLNAME" "$TIER" "${COMPANY:-}" "${SEATS:-}" "${CURRENCY:-}" "$PLAN" "$TELEMETRY" "$EULA_VERSION" "$NOW" "$MACHINE_ID" "$OS")
INSTALL_TOKEN=""
CHECKOUT_URL=""
if command -v curl >/dev/null; then
  # 3 attempts with short backoff; if all fail, the app self-heals the
  # registration in the background (license.json keeps the payload).
  RESP=""
  for _try in 1 2 3; do
    RESP="$(curl -fsS -m 12 -X POST "$REGISTER_URL/register" \
      -H 'content-type: application/json' -d "$PAYLOAD" 2>/dev/null || true)"
    [ -n "$RESP" ] && break
    [ "$_try" -lt 3 ] && sleep $(( _try * 2 ))
  done
  if [ -n "$RESP" ]; then
    INSTALL_TOKEN="$(printf '%s' "$RESP" | sed -n 's/.*"install_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    CHECKOUT_URL="$(printf '%s' "$RESP" | sed -n 's/.*"checkout_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    ok "registered"
    if [ -n "$CHECKOUT_URL" ]; then
      say ""
      say "  ★ Your free month is active — nothing is blocked. Set up billing when convenient"
      say "    (you or your billing team — the link is forwardable; invoicing available):"
      say "      $CHECKOUT_URL"
      say "      Then CAD \$25 / seat / year, auto-renewing. (link also emailed to $EMAIL)"
      say ""
    fi
  else
    say "• registration deferred (offline) — the app completes it automatically in the background"
  fi
fi

# 5. local license record ----------------------------------------------------------
mkdir -p "$ASK_HOME" "$BIN_DIR"
cat > "$LICENSE_JSON" <<EOF
{"email":"$EMAIL","name":"$FULLNAME","tier":"$TIER","company":"${COMPANY:-}","seats":"${SEATS:-}","currency":"${CURRENCY:-}","telemetry":"$TELEMETRY","eula_version":"$EULA_VERSION","accepted_at":"$NOW","machine_id":"$MACHINE_ID","install_token":"$INSTALL_TOKEN"}
EOF
ok "license record written to $LICENSE_JSON"

# persist telemetry opt-out to the binary's config (paid opt-out only; free stays on)
if [ "$TELEMETRY" = "off" ]; then
  CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ask"
  [ "$(uname -s)" = "Darwin" ] && CFG_DIR="$HOME/Library/Application Support/ask"
  mkdir -p "$CFG_DIR"
  if ! grep -q '^\[telemetry\]' "$CFG_DIR/config.toml" 2>/dev/null; then
    printf '\n[telemetry]\nenabled = false\n' >> "$CFG_DIR/config.toml"
  fi
fi

# 6. binary fetch ------------------------------------------------------------------
_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
_arch="$(uname -m)"
case "$_os-$_arch" in
  linux-x86_64)   PLATFORM="linux-x86_64"  ;;
  linux-aarch64)  PLATFORM="linux-arm64"   ;;
  linux-armv*)    PLATFORM="linux-arm64"   ;;
  darwin-x86_64)  PLATFORM="macos-x86_64"  ;;
  darwin-arm64)   PLATFORM="macos-arm64"   ;;
  *)
    err "No pre-built binary for $_os-$_arch."
    if command -v cargo >/dev/null; then
      say "Building from source (Rust detected)..."
      cargo build --release --manifest-path "$SCRIPT_DIR/Cargo.toml" 2>/dev/null \
        && install -m 0755 "$SCRIPT_DIR/target/release/ask-token-optimizer" "$BIN_DIR/ask"
    else
      err "Install Rust (rustup.rs) and re-run, or download a binary manually."; exit 1
    fi
    PLATFORM=""
    ;;
esac

if [ -n "$PLATFORM" ]; then
  # Binaries ship via GitHub RELEASES (checksum-verified) — never from the repo tree.
  ASSET="ask-token-optimizer-$PLATFORM"
  TAG="${ATO_VERSION:-latest}"
  if [ "$TAG" = "latest" ]; then
    BASE_URL="https://github.com/$REPO_SLUG/releases/latest/download"
  else
    BASE_URL="https://github.com/$REPO_SLUG/releases/download/$TAG"
  fi
  say "Downloading $ASSET ($TAG)..."
  DL_OK=""
  for _a in 1 2 3; do
    if command -v curl >/dev/null; then
      curl -fsSL --connect-timeout 15 -o "$BIN_DIR/ask" "$BASE_URL/$ASSET" && DL_OK=1 && break
    elif command -v wget >/dev/null; then
      wget -qO "$BIN_DIR/ask" "$BASE_URL/$ASSET" && DL_OK=1 && break
    else
      err "curl or wget required to download the binary."; exit 1
    fi
    [ "$_a" -lt 3 ] && sleep $(( _a * 2 ))
  done
  [ -n "$DL_OK" ] || { err "Download failed after 3 attempts — check your connection and re-run."; exit 1; }
  # Verify against the .sha256 sidecar (sha256sum on Linux; shasum -a 256 on macOS)
  WANT="$( { curl -fsSL --connect-timeout 15 "$BASE_URL/$ASSET.sha256" 2>/dev/null || true; } | awk '{print tolower($1)}' | head -1 )"
  if printf '%s' "$WANT" | grep -qE '^[0-9a-f]{64}$'; then
    if command -v sha256sum >/dev/null; then HAVE="$(sha256sum "$BIN_DIR/ask" | awk '{print $1}')"
    elif command -v shasum >/dev/null;   then HAVE="$(shasum -a 256 "$BIN_DIR/ask" | awk '{print $1}')"
    else HAVE=""; fi
    if [ -n "$HAVE" ]; then
      if [ "$HAVE" != "$WANT" ]; then err "Checksum mismatch — aborting."; rm -f "$BIN_DIR/ask"; exit 1; fi
      ok "checksum verified"
    else
      say "• no sha256 tool found — continuing without verification"
    fi
  else
    say "• checksum sidecar unavailable — continuing without verification"
  fi
  chmod +x "$BIN_DIR/ask"
  # also expose as ask-token-optimizer for direct invocation
  ln -sf "$BIN_DIR/ask" "$BIN_DIR/ask-token-optimizer" 2>/dev/null || true
  ok "binary installed → $BIN_DIR/ask"
fi

# 7. verify binary -----------------------------------------------------------------
if "$BIN_DIR/ask" --version >/dev/null 2>&1; then
  VER="$("$BIN_DIR/ask" --version 2>/dev/null)"
  ok "binary OK: $VER"
else
  err "Binary installed but failed to run — check $BIN_DIR/ask"; exit 1
fi

# 8. wire Claude Code hooks (optional, asks first) ---------------------------------
if [ -d "$HOME/.claude" ]; then
  say ""
  read -r -p "Wire ASK Token Optimizer hooks into Claude Code? [Y/n]: " W
  if [[ "${W:-Y}" =~ ^[Yy] ]]; then
    mkdir -p "$HOOKS_DIR"
    # copy hook scripts from SDK if present, else download
    for HK in ask-rewrite.sh ask-filter.sh ask-rewrite.py ask-filter.py ato_telemetry.py; do
      SRC="$SCRIPT_DIR/../hooks/$HK"
      if [ -f "$SRC" ]; then
        install -m 0755 "$SRC" "$HOOKS_DIR/$HK"
      else
        curl -fsSL -o "$HOOKS_DIR/$HK" "$GITHUB_RAW/hooks/$HK" 2>/dev/null && chmod +x "$HOOKS_DIR/$HK" || true
      fi
    done
    SETTINGS="$HOME/.claude/settings.json"
    if [ ! -f "$SETTINGS" ]; then
      cat > "$SETTINGS" <<'SETTINGSEOF'
{
  "hooks": {
    "PreToolUse":  [{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/ask-rewrite.sh"}]}],
    "PostToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/ask-filter.sh"}]}]
  }
}
SETTINGSEOF
      ok "hooks wired in $SETTINGS"
    else
      say "• $SETTINGS already exists — add hooks manually (see README)"
    fi
  fi
fi

# 9. PATH notice + platform notes --------------------------------------------------
case ":${PATH}:" in *":$BIN_DIR:"*) ;; *)
  say ""
  say "Add to PATH (append to ~/.bashrc or ~/.zshrc):"
  say "  export PATH=\"$BIN_DIR:\$PATH\""
  ;; esac

if [ "$OS" = "Darwin" ]; then
  say ""
  say "macOS — binary is unsigned (by design, no Apple dependency)."
  say "  If Gatekeeper blocks it:  xattr -d com.apple.quarantine \"$BIN_DIR/ask\""
fi

say ""
ok "Done.  Run: ask --version · ask audit · ask telemetry"
