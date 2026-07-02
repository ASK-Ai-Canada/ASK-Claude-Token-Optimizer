# ASK Token Optimizer — Windows Installation (Native, No WSL)

## Prerequisites

1. **PowerShell** (ships with Windows — use PowerShell, not cmd)
2. **Python 3.8+** — the Claude Code hooks are Python (`winget install Python.Python.3.12`)
3. **Claude Code** — installed and working

No Rust, no build step — the installer fetches the pre-built, checksum-verified binary from the latest GitHub Release.

## Install (recommended)

Clone or download this repository, then from PowerShell in the repo folder:

```powershell
.\install.ps1
```

The installer walks you through:

- **License** — clickwrap (Community: free under USD $100K annual revenue · Commercial above).
- **Registration** — email + name; commercial adds company, seats, and a **required billing currency (CAD or USD)**. CAD adds 15% HST as a separate line; USD is a foreign sale, no CA tax. Commercial receives a card-capture link — **first month free**, seat count adjustable right on the checkout page.
- **Binary** — downloaded from `releases/latest` (pin a version with `$env:ATO_VERSION="vX.Y.Z"`), SHA-256 verified against the release sidecar, installed to `%USERPROFILE%\.local\bin` as `ask.exe` + `ask-token-optimizer.exe`, added to your user PATH persistently.
- **Hooks** — staged to `%USERPROFILE%\.claude\hooks` and, with your consent, wired into Claude Code's `settings.json` (a `.bak` is kept).

If registration can't reach the server during install, it is saved to `%USERPROFILE%\.ask\license.json` and the app completes it automatically in the background.

## Manual install (no script)

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null
$u = "https://github.com/ASK-Ai-Canada/ASK-Claude-Token-Optimizer/releases/latest/download/ask-token-optimizer-windows-x86_64.exe"
Invoke-WebRequest -Uri $u -OutFile "$env:USERPROFILE\.local\bin\ask-token-optimizer.exe" -UseBasicParsing
Copy-Item "$env:USERPROFILE\.local\bin\ask-token-optimizer.exe" "$env:USERPROFILE\.local\bin\ask.exe"

$binPath = "$env:USERPROFILE\.local\bin"
$current = [Environment]::GetEnvironmentVariable("Path", "User")
if ($current -notlike "*$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$current;$binPath", "User")
    $env:Path += ";$binPath"
}

ask --version
```

Then wire the hooks — `~/.claude/settings.json`, Windows command form:

```json
{
  "hooks": {
    "PreToolUse":  [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "python %USERPROFILE%\\.claude\\hooks\\ask-rewrite.py" } ] } ],
    "PostToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "python %USERPROFILE%\\.claude\\hooks\\ask-filter.py" } ] } ]
  }
}
```

(The hook scripts live in this repo under `hooks\` — copy them to `%USERPROFILE%\.claude\hooks\`.)

## Verify

Open a **new** PowerShell window (PATH refresh), restart Claude Code, run a few commands, then:

```powershell
ask audit
```

## Updating

```powershell
ask update          # self-update from the latest release, checksum-verified
ask update -check   # see what's available without changing anything
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ask` not recognized | Open a new PowerShell window (PATH refresh) |
| Hooks not firing | Restart Claude Code after wiring `settings.json` |
| `ask audit` shows 0 | Run a few commands in Claude Code first, then re-check |
| `python` not found (hooks) | Install Python 3 and re-open the terminal |
| SmartScreen prompt on first run | Binary is unsigned — verify the SHA-256 against the release `.sha256` sidecar, then allow |

Questions: licensing@ask-ai.ca — ASK-Ai Team Canada
