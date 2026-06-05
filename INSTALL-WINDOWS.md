# ASK-Token-Optimizer — Windows Installation (Native, No WSL)

## Prerequisites

1. **Rust toolchain** — Install from https://rustup.rs
   - Download and run `rustup-init.exe`
   - Choose "Proceed with standard installation"
   - Restart your terminal after install

2. **Git** — Install from https://git-scm.com/download/win
   - Or use `winget install Git.Git`

3. **Claude Code** — Must be installed and working

## Install (Pre-Built Binary — recommended)

The SDK ships a release binary at `builds\windows-x86_64\ask-token-optimizer.exe`. From PowerShell, in the unpacked SDK directory:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null

# Copy the canonical binary
Copy-Item "builds\windows-x86_64\ask-token-optimizer.exe" "$env:USERPROFILE\.local\bin\ask-token-optimizer.exe"

# Short-alias copy for ergonomic invocation: type `ask` instead of `ask-token-optimizer`
Copy-Item "builds\windows-x86_64\ask-token-optimizer.exe" "$env:USERPROFILE\.local\bin\ask.exe"

# Add to PATH (persistent, user-level)
$binPath = "$env:USERPROFILE\.local\bin"
$current = [Environment]::GetEnvironmentVariable("Path", "User")
if ($current -notlike "*$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$current;$binPath", "User")
    $env:Path += ";$binPath"
}

# Verify
ask-token-optimizer --version
ask gain
```

## Install from Source (optional)

Open **PowerShell** (not CMD):

```powershell
# Clone the repo (replace <repo-url> with the URL you received from your provider)
git clone <repo-url>
cd ASK-Token-Optimizer

# Build release binary
cargo build --release

# Create install directory
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin"

# Copy binary
Copy-Item "target\release\ask-token-optimizer.exe" "$env:USERPROFILE\.local\bin\ask-token-optimizer.exe"

# Add to PATH (persistent, user-level)
$binPath = "$env:USERPROFILE\.local\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "User")
    $env:Path += ";$binPath"
}

# Verify
ask-token-optimizer --version
```

## Configure Claude Code Hook

### PostToolUse Hook (output compression)

Create the hook directory and script:

```powershell
# Create hooks directory
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.claude\hooks"

# Create the PostToolUse hook (PowerShell script)
@'
#!/usr/bin/env pwsh
# ASK-Token-Optimizer — PostToolUse hook (Windows)
# Filters command output through semantic compression

$optimizer = "$env:USERPROFILE\.local\bin\ask-token-optimizer.exe"
if (Test-Path $optimizer) {
    $input | & $optimizer --hook
} else {
    $input
}
'@ | Set-Content "$env:USERPROFILE\.claude\hooks\ask-filter.ps1"
```

Then add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File %USERPROFILE%\\.claude\\hooks\\ask-filter.ps1"
          }
        ]
      }
    ]
  }
}
```

### PreToolUse Hook (command rewriting)

The PreToolUse rewrite hook requires `jq`. Install it:

```powershell
winget install jqlang.jq
```

Create the rewrite hook:

```powershell
@'
#!/usr/bin/env pwsh
# ASK-Token-Optimizer — PreToolUse hook (Windows)
# Rewrites commands to use ask-token-optimizer for token savings

$input_json = $input | ConvertFrom-Json
$cmd = $input_json.tool_input.command

if (-not $cmd) { exit 0 }

$optimizer = "$env:USERPROFILE\.local\bin\ask-token-optimizer.exe"
if (-not (Test-Path $optimizer)) { exit 0 }

try {
    $rewritten = & $optimizer rewrite $cmd 2>$null
    if ($LASTEXITCODE -ne 0 -or $rewritten -eq $cmd) { exit 0 }

    $input_json.tool_input.command = $rewritten
    @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "allow"
            permissionDecisionReason = "ASK auto-rewrite"
            updatedInput = $input_json.tool_input
        }
    } | ConvertTo-Json -Depth 5
} catch {
    exit 0
}
'@ | Set-Content "$env:USERPROFILE\.claude\hooks\ask-rewrite.ps1"
```

Add to settings:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File %USERPROFILE%\\.claude\\hooks\\ask-rewrite.ps1"
          }
        ]
      }
    ]
  }
}
```

## Verify Installation

```powershell
# Check binary
ask-token-optimizer --version

# Test compression
echo "test output with ANSI codes and noise" | ask-token-optimizer --hook

# Check Claude Code sees the hook
# Restart Claude Code, then run any command — check if output is compressed
```

## Serve Mode (run as HTTP service)

```powershell
# Run the optimizer as an HTTP service on port 8095
ask-token-optimizer serve --port 8095

# Test
Invoke-RestMethod -Method POST -Uri "http://localhost:8095/v1/compress/output" `
  -ContentType "application/json" `
  -Body '{"content": "test content with noise", "language": "text"}'
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `cargo` not found | Restart terminal after Rust install, or run `$env:Path += ";$env:USERPROFILE\.cargo\bin"` |
| Link errors during build | Install Visual Studio Build Tools: `winget install Microsoft.VisualStudio.2022.BuildTools` |
| Hook not firing | Restart Claude Code after adding hooks to settings.json |
| Binary not found | Verify `$env:USERPROFILE\.local\bin` is in your PATH |
| Permission denied on hook | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |

## Notes

- No WSL required — builds and runs natively on Windows
- Uses MSVC toolchain (default Rust on Windows)
- Stats DB stored at `%USERPROFILE%\.ask-token-optimizer\stats.db`
- Config at `%USERPROFILE%\.ask-token-optimizer\config.toml`
