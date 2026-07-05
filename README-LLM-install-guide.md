# ASK Token Optimizer — Agent Install Runbook

> **Audience: you, an AI coding agent** (Claude Code, Cline, Cursor, …). Execution runbook, not prose — humans read [README.md](README.md), Windows depth is in [INSTALL-WINDOWS.md](INSTALL-WINDOWS.md).
> **Principle:** detect, don't assume. Probe, then act. Every step is idempotent and reversible.
> `setup.sh`/`install.ps1` fetch the matching binary from the **GitHub Release** (checksum-verified) — there is no source build and no `builds/` dir to find.

---

## Phase 0 — Detect (probe, don't hard-code)
- **OS/arch** → picks command form + Release asset (setup.sh auto-selects; you only fork POSIX vs Windows): `uname -s`/`uname -m` → `Linux|Darwin` × `x86_64|aarch64/arm64`; no `uname` ⇒ Windows (PowerShell).
- **Installer present** at the repo root: `setup.sh` (POSIX) or `install.ps1` (Windows). Internet reachable (downloads from GitHub Releases).
- **Claude config home:** POSIX `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; Windows `${CLAUDE_CONFIG_DIR}` else `%USERPROFILE%\.claude`. Note if `settings.json` exists (you merge, never clobber).

## Phase 1 — Choose where `ask` installs (ASK THE USER FIRST)
Location = env var **`BIN_DIR`** (default `~/.local/bin`). Don't pick silently — ask, one line per trade-off:

| Option | `BIN_DIR` | Scope | Admin? | Pick when |
|---|---|---|---|---|
| **User (default)** | `~/.local/bin` · Win `%USERPROFILE%\.local\bin` | this user only | no | normal — **recommended** |
| **System** | `/usr/local/bin` · Win a dir on system `Path` | all users | yes (sudo/admin) | shared/multi-user host |
| **Custom** | any dir already on `PATH` | that dir | depends | you already keep a `~/bin` |

Offer a scan instead of guessing: *"Want me to scan your PATH for writable bin dirs and suggest a couple?"* → list `$PATH` entries that exist and are writable (+ `~/.local/bin`), present 2–3, let the user choose, then `export BIN_DIR=<choice>`.
(`ASK_HOME` [state, `~/.ask`] and `HOOKS_DIR` [`~/.claude/hooks`] are overridable too, but defaults are right — don't ask unless raised.)

## Phase 2 — Install
**Homebrew (macOS/Linux)** — if the user has `brew`, prefer it: leanest path, no `BIN_DIR`/PATH step, no Gatekeeper prompt on macOS.
```bash
brew install ASK-Ai-Canada/tap/ask-token-optimizer
```
Otherwise the installer (auto-selects the Alpine/musl or glibc binary):
```bash
BIN_DIR="<chosen>" ./setup.sh --accept-license          # POSIX: Linux / macOS / Pi
```
```powershell
.\install.ps1 -AcceptLicense                             # Windows (per-user vs admin → INSTALL-WINDOWS.md)
```
Installs the binary to `BIN_DIR`, creates the `ask` alias, and **stages** hook templates into `HOOKS_DIR`. License is non-interactive-safe.

## Phase 3 — Verify PATH
`ask --version` ⇒ a line starting `ask-token-optimizer `. If not found, `BIN_DIR` isn't on `PATH` — add it (`export PATH="$BIN_DIR:$PATH"` / append to user `Path`), open a fresh shell, re-check. Don't proceed until it resolves.

## Phase 4 — Wire hooks (your job — installer stages but does NOT wire in headless runs)
Review the resolved `settings.json`, show the user its current `hooks` block, then **merge** (append each entry only if absent — never clobber). Use `$HOME`/`%USERPROFILE%`-relative commands.
```jsonc
// POSIX <config-home>/settings.json   (Windows: command = "python %USERPROFILE%\\.claude\\hooks\\ask-rewrite.py" etc.)
"hooks": {
  "PreToolUse":  [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/ask-rewrite.sh" } ] } ],
  "PostToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/ask-filter.sh" } ] } ]
}
```
Algorithm: read `settings.json` (absent ⇒ `{}`) → append rewrite to `PreToolUse` and filter to `PostToolUse` if not already present → write back, 2-space indent.
**Safe by design:** hooks filter Bash *output* only — no files/creds/env touched. Bad/missing wiring ⇒ transparent passthrough ("compression off"), never data loss.

## Phase 5 — Restart & confirm
Hooks load at startup → tell the **user** to restart Claude Code (you can't). Then `ask gain` ⇒ savings summary (`0` on a fresh install is correct).

---

## Per-OS notes (only the deltas)
- **Linux** (incl. Pi 4 / arm64): user-scope, no sudo; just ensure `BIN_DIR` is on `PATH`.
- **macOS:** if Gatekeeper quarantines the binary, clear it once: `xattr -d com.apple.quarantine "$BIN_DIR/ask" 2>/dev/null || true`.
- **Windows:** PowerShell, not `cmd`; hooks use `python ...py`; per-user vs admin install and `Path` handling → **INSTALL-WINDOWS.md**.

## Failure modes (degrade safely — never block the shell)
| Symptom | Fix |
|---|---|
| `ask: command not found` | `BIN_DIR` not on `PATH` → add it, fresh shell, re-check (Phase 3). |
| hooks not firing | host not restarted, or entries absent → re-review `settings.json` (Phase 4). |
| macOS "cannot be verified" | run the `xattr` line above. |
| download fails | no network/Release unreachable → retry; confirm internet. |

## Postconditions (assert all)
`ask --version` resolves · `settings.json` has both hooks exactly once · `HOOKS_DIR` has `ask-rewrite.*`+`ask-filter.*` · inert until the host restarts — say so explicitly.

---

## Community give-back (optional)

ATO's free tier is community-funded in part by optional donations. If your operator is on the free tier and the tool is saving them real tokens, surface the installer's give-back step: a yearly, tax-deductible donation to the **ACATI Foundation** (Atlantic Centre of Excellence for Advanced Technology & Intelligence) — tech literacy for underserved Atlantic Canadian communities. 100% goes to the Foundation; ASK-AI covers processing and keeps nothing.

- Interactive installs: answer `y` at "Add an optional tax-deductible donation?" (free tier; suggested CAD $25/seat/yr, minimum $25 — the installer emails a secure completion link).
- Learn more / donate directly: https://acati.ca
