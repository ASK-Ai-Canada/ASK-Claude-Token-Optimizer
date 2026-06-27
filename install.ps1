# ASK Token Optimizer — Windows Installer
# Brand: ASK AI · 2026 Executive Style
#
# Run from PowerShell (NOT cmd) inside the unpacked SDK directory:
#   .\install.ps1
#
# What this does (3 steps, no admin required):
#   1. Copies the pre-built binary to %USERPROFILE%\.local\bin\
#   2. Adds that directory to your user PATH (persistent)
#   3. Stages hook templates to %USERPROFILE%\.claude\hooks\

param([switch]$AcceptLicense)

$ErrorActionPreference = 'Stop'

# Brand colors — closest 24-bit ANSI to the 2026 Executive Style spec.
$gold     = "$([char]27)[38;2;198;161;91m"   # #C6A15B Sovereign gold
$paleGold = "$([char]27)[38;2;232;215;168m"  # #E8D7A8 Pale gold
$charcoal = "$([char]27)[38;2;43;47;54m"     # #2B2F36 Charcoal text
$slate    = "$([char]27)[38;2;31;38;48m"     # #1F2630 Deep slate
$dim      = "$([char]27)[2m"
$reset    = "$([char]27)[0m"

function Banner([string]$Version) {
  $verLine = if ($Version) { "v$Version" } else { "Windows x86_64" }
  Write-Host ""
  Write-Host "   ${gold}┌─────────────────────────────────────────────────────────┐${reset}"
  Write-Host "   ${gold}│${reset}                                                         ${gold}│${reset}"
  Write-Host "   ${gold}│${reset}     ${gold}A S K${reset}   ${paleGold}Token Optimizer${reset}                       ${gold}│${reset}"
  Write-Host "   ${gold}│${reset}     ${dim}token compression for Claude Code${reset}                ${gold}│${reset}"
  Write-Host "   ${gold}│${reset}                                                         ${gold}│${reset}"
  Write-Host "   ${gold}└─────────────────────────────────────────────────────────┘${reset}"
  Write-Host ""
  Write-Host "   ${dim}${verLine}   ·   Windows x86_64   ·   Executive Edition${reset}"
  Write-Host ""
}

function Step([int]$n, [string]$msg) {
  Write-Host "   ${gold}●${reset} ${charcoal}Step $n${reset}  ${msg}"
}

function Tick([string]$msg) {
  Write-Host "     ${gold}✓${reset} $msg"
}

# ─── Locate bundled binary ─────────────────────────────────────────────────
$installDir = "$env:USERPROFILE\.local\bin"
$hookDir    = "$env:USERPROFILE\.claude\hooks"
$srcExe     = Join-Path (Get-Location) "builds\windows-x86_64\ask-token-optimizer.exe"

if (-not (Test-Path $srcExe)) {
  Write-Host "     ${gold}!${reset} Could not find $srcExe"
  Write-Host "       Run this script from inside the unpacked SDK directory."
  exit 1
}

# Version is read from the bundled binary — never hardcoded.
# Single source of truth: Cargo.toml -> compiled into the binary via env!("CARGO_PKG_VERSION").
$Version = ""
try { $Version = ((& $srcExe --version) -replace '[^0-9.]', '').Trim() } catch { $Version = "" }

# ─── Banner ──────────────────────────────────────────────────────────────
Banner $Version

# ─── License acceptance (LICENSE §0: display + accept before install) ──────
if (-not $AcceptLicense) {
  Write-Host ""
  Write-Host "   ${charcoal}ASK Token Optimizer — Dual License (Community + Commercial)${reset}"
  Write-Host "     ${dim}• Free for individuals and companies under USD `$100k annual gross revenue.${reset}"
  Write-Host "     ${dim}• Companies at or above USD `$100k need a paid Commercial License.${reset}"
  Write-Host "     ${dim}• Full terms: see LICENSE in this directory. Governing law: Canada.${reset}"
  Write-Host ""
  $reply = Read-Host "   Type 'accept' to agree to the LICENSE and continue"
  if ($reply -ne 'accept') { Write-Host "   License not accepted. Aborting."; exit 1 }
}

# ─── Step 1: copy binary ─────────────────────────────────────────────────
Step 1 "Installing the binary"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item $srcExe (Join-Path $installDir "ask-token-optimizer.exe") -Force
Copy-Item $srcExe (Join-Path $installDir "ask.exe")                 -Force
Tick "ask-token-optimizer.exe  ->  $installDir"
Tick "ask.exe                  ->  short alias"

# ─── Step 2: PATH ────────────────────────────────────────────────────────
Step 2 "Adding to user PATH"
$current = [Environment]::GetEnvironmentVariable("Path", "User")
if ($current -notlike "*$installDir*") {
  [Environment]::SetEnvironmentVariable("Path", "$current;$installDir", "User")
  $env:Path += ";$installDir"
  Tick "appended $installDir"
} else {
  Tick "already on PATH"
}

# ─── Step 3: hook templates ──────────────────────────────────────────────
Step 3 "Staging hook templates"
New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
if (Test-Path "hooks") {
  Get-ChildItem "hooks\*" -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $hookDir $_.Name) -Force
  }
  Tick "templates -> $hookDir"
} else {
  Tick "no hooks/ folder in SDK; skipped"
}

# ─── Verification ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}─── Verification ──────────────────────────────────────────${reset}"
Write-Host ""
& "$installDir\ask-token-optimizer.exe" --version
Write-Host ""
& "$installDir\ask-token-optimizer.exe" gain
Write-Host ""

# ─── Hook auto-wire ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}─── Claude Code hook wiring ───────────────────────────────${reset}"
Write-Host ""
$settingsCandidates = @(
  "$env:USERPROFILE\.claude\settings.json",
  "$env:APPDATA\claude\settings.json"
)
$settingsPath = $null
foreach ($c in $settingsCandidates) { if (Test-Path $c) { $settingsPath = $c; break } }

if (-not $settingsPath) {
  Write-Host "   ${dim}settings.json not found. Wire hooks manually after first Claude Code launch.${reset}"
  Write-Host "   See README.md for the JSON snippet."
} else {
  $content = Get-Content $settingsPath -Raw
  if ($content -like "*ask-rewrite*") {
    Tick "Hooks already wired in $settingsPath"
  } else {
    $wire = Read-Host "   Wire optimizer hooks into settings.json now? [y/N]"
    if ($wire -eq 'y' -or $wire -eq 'Y') {
      Copy-Item $settingsPath "$settingsPath.bak"
      $rw = "$hookDir\ask-rewrite.py"
      $fi = "$hookDir\ask-filter.py"
      $pyCode = @"
import json, sys
path = sys.argv[1]; rw = sys.argv[2]; fi = sys.argv[3]
with open(path) as f: cfg = json.load(f)
h = cfg.setdefault('hooks', {})
pre  = h.setdefault('PreToolUse',  [])
post = h.setdefault('PostToolUse', [])
def wired(lst, n):
    return any(n in hk.get('command','') for e in lst for hk in e.get('hooks',[]))
if not wired(pre,  'ask-rewrite'): pre.append( {'matcher':'Bash','hooks':[{'type':'command','command':'python '+rw}]})
if not wired(post, 'ask-filter'):  post.append({'matcher':'Bash','hooks':[{'type':'command','command':'python '+fi}]})
with open(path,'w') as f: json.dump(cfg,f,indent=2); f.write('\n')
print('ok')
"@
      $tmp = [System.IO.Path]::GetTempFileName() + ".py"
      Set-Content $tmp $pyCode
      $result = python $tmp $settingsPath $rw $fi 2>&1
      Remove-Item $tmp -Force
      if ($result -eq 'ok') { Tick "Hooks wired into $settingsPath" }
      else { Write-Host "   ${gold}!${reset} Auto-wire failed — add manually (see README.md): $result" }
    } else {
      Write-Host "   ${dim}Skipped. See README.md > 'Activate the hooks' for the JSON snippet.${reset}"
    }
  }
}

# ─── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}─── You are set up ────────────────────────────────────────${reset}"
Write-Host ""
Write-Host "   1.  ${charcoal}Open a new PowerShell window${reset}  (so PATH refreshes)"
Write-Host "   2.  ${charcoal}Restart Claude Code${reset}"
Write-Host "   3.  Run  ${gold}ask gain${reset}  after a few commands to see your savings"
Write-Host ""
Write-Host "   ${dim}Docs:${reset}  README.md  ·  INSTALL-WINDOWS.md"
Write-Host ""
