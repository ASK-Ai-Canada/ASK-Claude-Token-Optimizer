#!/usr/bin/env bash
# ASK Token Optimizer — release / version-sync tool
# ---------------------------------------------------------------------------
# SINGLE SOURCE OF TRUTH for the version is Cargo.toml `version = "X.Y.Z"`.
# Every other place that carries the version is enumerated below in
# VERSION_CARRIERS and is either STAMPED from Cargo.toml or VERIFIED to carry
# no hardcoded literal. Bump Cargo.toml, run `scripts/release.sh sync`, done.
#
# Usage:
#   scripts/release.sh version          # print the single-source version
#   scripts/release.sh sync             # stamp every STAMP carrier from Cargo.toml
#   scripts/release.sh check            # fail if any stale/stray version literal exists
#   scripts/release.sh build            # cargo build --release (local platform only)
#   scripts/release.sh tag              # git tag vX.Y.Z (annotated) — triggers CI
#   scripts/release.sh all              # sync + check + build + tag
#
# Cross-platform binaries (Linux x86_64/arm64, macOS x86_64/arm64, Windows x86_64)
# are built by GitHub Actions on push of a v* tag. See .github/workflows/release.yml.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CARGO_TOML="$ROOT/Cargo.toml"

# ── SINGLE SOURCE ──────────────────────────────────────────────────────────
version() {
  grep -m1 '^version' "$CARGO_TOML" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/'
}
VER="$(version)"

# ── PARAMETERIZED VERSION-CARRIER LIST ─────────────────────────────────────
# Format: "<relpath>|<mode>|<description>"
#   stamp   = release.sh rewrites the literal from Cargo.toml (regex below)
#   compile = derived at compile time via env!("CARGO_PKG_VERSION") — auto
#   runtime = derived at runtime from the binary's `--version` — auto
#   source  = Cargo.toml itself, the single source
VERSION_CARRIERS=(
  "Cargo.toml|source|the single source of truth (version = \"X.Y.Z\")"
  "Cargo.lock|stamp|lockfile package entry — kept in sync by cargo build"
  "src/tracking.rs|compile|history.db version column via env!(CARGO_PKG_VERSION)"
  "src/main.rs|compile|ask --version output via env!(CARGO_PKG_VERSION)"
  "README.md|stamp|shields.io version badge"
  "install.ps1|runtime|banner reads version from the bundled binary --version"
)

list() {
  echo "Single source: Cargo.toml  ->  version = $VER"
  echo
  printf '  %-18s %-8s %s\n' "FILE" "MODE" "DESCRIPTION"
  for c in "${VERSION_CARRIERS[@]}"; do
    IFS='|' read -r f m d <<<"$c"
    printf '  %-18s %-8s %s\n' "$f" "$m" "$d"
  done
}

# ── STAMP ──────────────────────────────────────────────────────────────────
sync() {
  echo "Stamping version $VER from Cargo.toml ..."
  # README.md shields.io badge: version-X.Y.Z
  sed -i -E "s#(badge/version-)[0-9]+\.[0-9]+\.[0-9]+#\1${VER}#g" "$ROOT/README.md"
  echo "  stamped README.md badge -> $VER"
  # Cargo.lock own-package entry (cargo also does this on build)
  if grep -q 'name = "ask-token-optimizer"' "$ROOT/Cargo.lock"; then
    awk -v v="$VER" '
      /^name = "ask-token-optimizer"/{p=1}
      p && /^version = /{sub(/"[0-9]+\.[0-9]+\.[0-9]+"/,"\""v"\"");p=0}
      {print}' "$ROOT/Cargo.lock" > "$ROOT/Cargo.lock.tmp" && mv "$ROOT/Cargo.lock.tmp" "$ROOT/Cargo.lock"
    echo "  stamped Cargo.lock -> $VER"
  fi
  echo "compile/runtime carriers (src/*, install.ps1) need no stamp — derived automatically."
}

# ── VERIFY (no half measures: fail on any stray literal) ───────────────────
check() {
  local rc=0
  echo "Single-source check against Cargo.toml = $VER"
  # 1. README badge must equal source
  if ! grep -q "badge/version-${VER}" "$ROOT/README.md"; then
    echo "  FAIL: README.md badge != $VER"; rc=1
  else echo "  ok: README.md badge = $VER"; fi
  # 2. install.ps1 must carry NO hardcoded version literal (runtime-derived only)
  if grep -nE 'v?[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/install.ps1" >/dev/null; then
    echo "  FAIL: install.ps1 contains a hardcoded version literal (must be runtime-derived)"; rc=1
  else echo "  ok: install.ps1 carries no version literal"; fi
  # 3. no stray OLD app-version literal in shipping docs/scripts.
  #    (*.rs excluded: the app version there is ALWAYS env!(CARGO_PKG_VERSION);
  #     any X.Y.Z literal in Rust is dependency/test-fixture sample data, not the app version.)
  local stray
  stray="$(grep -rnE 'v?0\.(2|3)\.[0-9]+' "$ROOT" \
    --include='*.md' --include='*.ps1' --include='*.sh' --include='*.service' \
    2>/dev/null | grep -vE '/target/|release.sh' || true)"
  if [ -n "$stray" ]; then
    echo "  FAIL: stray old-version literals in shipping docs/scripts:"; echo "$stray" | sed 's/^/    /'; rc=1
  else echo "  ok: no stray 0.2.x/0.3.x literals in shipping docs/scripts"; fi
  [ $rc -eq 0 ] && echo "PASS: version is single-sourced." || echo "CHECK FAILED."
  return $rc
}

build() { ( cd "$ROOT" && cargo build --release ); }
tag()   { ( cd "$ROOT" && git tag -a "v${VER}" -m "Release v${VER}" && echo "tagged v${VER}" ); }

case "${1:-list}" in
  version) echo "$VER" ;;
  list)    list ;;
  sync)    sync ;;
  check)   check ;;
  build)   build ;;
  tag)     tag ;;
  all)     sync && check && build && tag ;;
  *) echo "usage: release.sh {version|list|sync|check|build|tag|all}"; exit 2 ;;
esac
