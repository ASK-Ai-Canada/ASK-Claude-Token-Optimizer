# ASK Token Optimizer — Agent Install Runbook

> **Audience: you, an AI coding agent** (Claude Code, Cline, Cursor, Continue, …).
> This is an execution runbook, not prose. Humans should read [README.md](README.md).
>
> **Operating principle — detect, don't assume.** Your environment is not the
> author's. Probe it, map your findings to the matrix below, and act on what you
> actually observe. Every step is idempotent and reversible; re-running is safe.

---

## Phase 0 — Audit your environment

Resolve each fact by **probing**, not guessing. Do not hard-code the author's paths.

**1. OS family & architecture.** Determine which world you are in:

| World | Probe | Expected signal |
|---|---|---|
| Linux (x86_64 server/desktop) | `uname -s` / `uname -m` | `Linux` / `x86_64` |
| Linux ARM (Raspberry Pi 4, SBCs) | `uname -s` / `uname -m` | `Linux` / `aarch64` (or `armv7l`) |
| macOS Intel | `uname -s` / `uname -m` | `Darwin` / `x86_64` |
| macOS Apple Silicon (M-series) | `uname -s` / `uname -m` | `Darwin` / `arm64` |
| Windows | `uname` absent → use PowerShell | `$env:OS` = `Windows_NT`; `$env:PROCESSOR_ARCHITECTURE` |

**2. Shell.** POSIX (`bash`/`zsh`) vs PowerShell vs `cmd`. On POSIX, `echo $SHELL`;
on Windows prefer PowerShell (`$PSVersionTable`). Use the matching command forms below.

**3. Claude config home.** Probe in priority order; the first that resolves wins:
- POSIX: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` (also check `$XDG_CONFIG_HOME/claude`).
- Windows: `$env:CLAUDE_CONFIG_DIR`, else `%USERPROFILE%\.claude`.
- Record the `settings.json` path and whether it **already exists** (you will merge, not clobber).

**4. User-scope bin dir & PATH.** Where user binaries live and whether it is resolvable:
- POSIX: `~/.local/bin` — check membership with `case ":$PATH:" in *":$HOME/.local/bin:"*)`.
- Windows: `%USERPROFILE%\.local\bin` — check the user `Path` env var.
- No elevation/`sudo`/admin is required or expected; this is a **user-scope** install.

**5. Write access.** Confirm you can write to both the config home and the bin dir before mutating anything.

**6. SDK root.** Confirm you are at the root of an unpacked SDK — the directory that
contains `setup.sh`, `install.ps1`, and `builds/`.

Now map architecture → prebuilt binary:

| `uname -s` | `uname -m` | build dir | installer |
|---|---|---|---|
| `Linux`  | `x86_64`  | `builds/linux-x86_64`  | `./setup.sh` |
| `Linux`  | `aarch64` | `builds/linux-arm64`   | `./setup.sh` (Pi 4 / ARM64) |
| `Darwin` | `x86_64`  | `builds/macos-x86_64`  | `./setup.sh` |
| `Darwin` | `arm64`   | `builds/macos-arm64`   | `./setup.sh` |
| Windows  | x64       | `builds/windows-x86_64`| `.\install.ps1` |

If your audit matches no row, **stop and report** the platform as unsupported by a
prebuilt binary (this SDK ships signed-clean binaries, not source).

---

## Phase 1 — Install the binary

Run the installer for your world (license acceptance is non-interactive-safe):

```bash
# POSIX — Linux / macOS / Pi 4
./setup.sh --accept-license
```
```powershell
# Windows
.\install.ps1 -AcceptLicense
```

This performs a user-scope install: copies the platform binary to your bin dir
(`~/.local/bin/ask-token-optimizer`, or `%USERPROFILE%\.local\bin` on Windows),
creates the `ask` alias, and **stages** the hook templates into `<config-home>/hooks/`.

**macOS caveat (Gatekeeper).** If the OS quarantines the unsigned binary, clear the
attribute once — only after you've confirmed the file is the one you installed:

```bash
xattr -d com.apple.quarantine ~/.local/bin/ask-token-optimizer 2>/dev/null || true
```

---

## Phase 2 — Verify PATH resolution

```bash
ask --version          # POSIX
```
```powershell
ask --version          # Windows (new shell so Path refreshes)
```

Expect a line beginning `ask-token-optimizer `. If the command does not resolve,
your bin dir is not on `PATH` — add it (`export PATH="$HOME/.local/bin:$PATH"` on
POSIX; append to the user `Path` on Windows) and re-probe. Do not proceed until it resolves.

---

## Phase 3 — Wire the hooks (you must do this; review first)

> **The installer does NOT wire hooks in a non-interactive run.** `setup.sh` /
> `install.ps1` only offer the merge when attached to a TTY. As an agent you are
> typically headless, so the installer **staged** the templates but left
> `settings.json` untouched. Wiring is **your** job. Don't assume it's done — verify.

**3a. Review before you touch.** Read the resolved `settings.json` and show the user
its current `hooks` block (or state that it is empty/absent). Summarize the change you
intend to make before making it.

**3b. Offer a backup — human in the loop.** Ask the user whether they want a backup of
`settings.json` first. Create one **only if they say yes**. It's a small JSON file and
the edit is trivially reversible, so this is courtesy, not necessity.

**3c. Merge — never clobber.** Append two entries, each only if an entry whose command
ends in `ask-rewrite` / `ask-filter` is not already present. Use the `$HOME`-relative
form as canonical (Claude Code expands `$HOME`); a fully-resolved absolute path is equivalent.

POSIX (`<config-home>/settings.json`):
```json
{
  "hooks": {
    "PreToolUse":  [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/ask-rewrite.sh" } ] } ],
    "PostToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/ask-filter.sh" } ] } ]
  }
}
```
Windows (`%USERPROFILE%\.claude\settings.json`):
```json
{
  "hooks": {
    "PreToolUse":  [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "python %USERPROFILE%\\.claude\\hooks\\ask-rewrite.py" } ] } ],
    "PostToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "python %USERPROFILE%\\.claude\\hooks\\ask-filter.py" } ] } ]
  }
}
```

Reference merge algorithm:
1. Read `settings.json` (treat absent as `{}`).
2. `cfg.hooks.PreToolUse`  — append the rewrite entry if not already present.
3. `cfg.hooks.PostToolUse` — append the filter entry if not already present.
4. Write back with 2-space indentation.

> **Reversible by design — a wrong edit can't damage the system.** These hooks only
> filter Bash *output*; they touch no files, credentials, or environment. To undo,
> delete the two entries (or remove the binary) and output passes through untouched.
> Worst case of a bad wiring is "compression is off," never data loss. This is the
> graceful-degradation contract: missing/erroring binary ⇒ transparent passthrough.

---

## Phase 4 — Restart the host

Hooks load at startup. Instruct the **user** to restart Claude Code (or reload the
window). You cannot trigger this from inside the running session.

## Phase 5 — Confirm

```bash
ask gain
```
Expect a savings summary. A fresh install with zero commands shows `0` — correct, not an error.

---

## Failure modes (degrade safely — never block the user's shell)

| Symptom | Resolution |
|---|---|
| `ask: command not found` / not recognized | bin dir not on `PATH`; add it, open a fresh shell, re-probe (Phase 2). |
| Hooks not firing | host not restarted after Phase 4, or entries not present — re-review `settings.json`. |
| `ask gain` shows `0` | no commands run yet; not an error. |
| macOS "developer cannot be verified" | run the `xattr -d com.apple.quarantine` line (Phase 1). |
| Audit matched no platform row | unsupported by prebuilt binary — stop and report (Phase 0). |

## Postconditions (assert all before declaring success)

- `ask --version` resolves on `PATH`.
- `settings.json` contains both hooks, exactly once each.
- `<config-home>/hooks/` contains `ask-rewrite.*` and `ask-filter.*`.
- The optimizer is inert until the host is restarted — tell the user so explicitly.
