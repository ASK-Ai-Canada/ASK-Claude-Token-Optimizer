# ASK Token Optimizer — Windows Installer
# Brand: ASK-Ai · 2026 Executive Style
#
# Run from PowerShell (NOT cmd):
#   .\install.ps1
#
# What this does (no admin required):
#   1. License clickwrap + registration (free / commercial — seats, CAD or USD)
#   2. Downloads the latest binary from GitHub Releases (checksum-verified)
#   3. Installs to %USERPROFILE%\.local\bin\ + adds to user PATH (persistent)
#   4. Stages hook templates to %USERPROFILE%\.claude\hooks\ + offers to wire them

param([switch]$AcceptLicense)

$ErrorActionPreference = 'Stop'

$EulaVersion = "1.1"
$RegisterUrl = if ($env:ATO_REGISTER_URL) { $env:ATO_REGISTER_URL } else { "https://api.ask-ai.ca/v1/ato" }
$Repo        = "ASK-Ai-Canada/ASK-Claude-Token-Optimizer"
$AssetName   = "ask-token-optimizer-windows-x86_64.exe"

# Brand colors — closest 24-bit ANSI to the 2026 Executive Style spec.
$gold     = "$([char]27)[38;2;198;161;91m"   # #C6A15B Sovereign gold
$paleGold = "$([char]27)[38;2;232;215;168m"  # #E8D7A8 Pale gold
$charcoal = "$([char]27)[38;2;43;47;54m"     # #2B2F36 Charcoal text
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

$installDir = "$env:USERPROFILE\.local\bin"
$hookDir    = "$env:USERPROFILE\.claude\hooks"
$askHome    = "$env:USERPROFILE\.ask"

Banner ""

# ─── 1. License acceptance (clickwrap, before anything else) ────────────────
if (-not $AcceptLicense) {
  Write-Host "   ${charcoal}ASK Token Optimizer — Dual License (Community + Commercial)${reset}"
  Write-Host "     ${dim}• Free for individuals and companies under USD `$100k annual gross revenue.${reset}"
  Write-Host "     ${dim}• Companies at or above USD `$100k need a paid Commercial License.${reset}"
  Write-Host "     ${dim}• Full terms: LICENSE in the repository. Governing law: Canada.${reset}"
  Write-Host ""
  $reply = Read-Host "   Type 'accept' to agree to the LICENSE and continue"
  if ($reply -ne 'accept') { Write-Host "   License not accepted. Aborting."; exit 1 }
}

# ─── 2. Registration — identical contract to setup.sh ──────────────────────
Write-Host ""
Step 1 "Registration"
$Email = ""
while ($Email -notmatch '@') {
  $Email = (Read-Host "     Work email (for your free license + weekly savings report)").Trim()
}
$FullName = (Read-Host "     Full name (optional, press Enter to skip)").Trim()

$Tier = "free"; $Company = ""; $Seats = ""; $Currency = ""
$r = (Read-Host "     Is your organization's annual gross revenue UNDER USD `$100,000? [Y/n]").Trim()
if ($r -match '^[Nn]') {
  $Tier = "commercial"
  Write-Host ""
  Write-Host "     ${paleGold}Business use at or above `$100k runs on a commercial subscription:${reset}"
  Write-Host "     ${paleGold}ASK Token Optimizer — `$25 per seat / year (first month FREE).${reset}"
  $Company = (Read-Host "     Company / organization name").Trim()
  $Seats = (Read-Host "     Number of seats").Trim()
  if ($Seats -notmatch '^\d+$') { $Seats = "1" }
  # Mandatory billing currency — CAD (adds 15% HST) or USD (foreign sale, no CA tax). No default.
  while ($Currency -ne 'cad' -and $Currency -ne 'usd') {
    $Currency = (Read-Host "     Billing currency — type CAD or USD (required)").Trim().ToLower()
    if ($Currency -ne 'cad' -and $Currency -ne 'usd') { Write-Host "     ${dim}Please type CAD or USD.${reset}" }
  }
  $yearly = 25 * [int]$Seats
  if ($Currency -eq 'cad') {
    Write-Host "     Plan: CAD `$25 / seat / year x $Seats seat(s) = CAD `$$yearly + 15% HST / year."
  } else {
    Write-Host "     Plan: USD `$25 / seat / year x $Seats seat(s) = USD `$$yearly / year (no CA tax)."
  }
  Write-Host "     ${dim}★ First month FREE — no charge for 30 days; cancel anytime before then.${reset}"
}

# Telemetry — community: always on (the exchange for free use); paid: optional, default on.
$Telemetry = "on"
if ($Tier -eq 'free') {
  Write-Host ""
  Write-Host "     ${dim}Help us improve — anonymous savings stats keep the free tier free.${reset}"
  Write-Host "     ${dim}Private by design: only the totals you save are shared.${reset}"
} else {
  Write-Host ""
  Write-Host "     [x] Help us improve — share anonymous savings stats. Private by design."
  $to = (Read-Host "         Press Enter to keep enabled, or type 'no' to opt out").Trim()
  if ($to -match '^[Nn]') { $Telemetry = "off" }
}

$MachineId = ""
try {
  $raw = "$env:COMPUTERNAME|$env:USERNAME|$((Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID)"
  $sha = [System.Security.Cryptography.SHA1]::Create()
  $MachineId = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))) -replace '-', '').ToLower().Substring(0, 16)
} catch { $MachineId = "unknown" }
$Now  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$Plan = if ($Tier -eq 'commercial') { "seat-25-yearly" } else { "free" }

$payload = @{
  email = $Email; name = $FullName; tier = $Tier; company = $Company; seats = $Seats
  currency = $Currency; plan = $Plan; telemetry = $Telemetry; eula_version = $EulaVersion
  accepted_at = $Now; machine_id = $MachineId; os = "Windows"; ver = "INSTALLER"
} | ConvertTo-Json -Compress

# 3 attempts with short backoff; if all fail, the app self-heals the
# registration in the background (license.json keeps the payload).
$InstallToken = ""; $CheckoutUrl = ""
for ($try = 1; $try -le 3; $try++) {
  try {
    $resp = Invoke-RestMethod -Method Post -Uri "$RegisterUrl/register" -ContentType 'application/json' -Body $payload -TimeoutSec 12
    if ($resp.install_token) { $InstallToken = $resp.install_token }
    if ($resp.checkout_url)  { $CheckoutUrl  = $resp.checkout_url }
    break
  } catch {
    if ($try -lt 3) { Start-Sleep -Seconds (2 * $try) }
  }
}
if ($InstallToken) {
  Tick "registered"
  if ($CheckoutUrl) {
    Write-Host ""
    Write-Host "     ${gold}★ Start your FREE month — add your card (no charge for 30 days):${reset}"
    Write-Host "       $CheckoutUrl"
    Write-Host "       ${dim}(link also emailed to $Email)${reset}"
    Write-Host ""
  }
} else {
  Write-Host "     ${dim}• registration deferred (offline) — the app completes it automatically in the background${reset}"
}

# Local license record — written unconditionally; the binary self-heals an
# empty install_token from this file (see README).
New-Item -ItemType Directory -Force -Path $askHome | Out-Null
@{
  email = $Email; name = $FullName; tier = $Tier; company = $Company; seats = $Seats
  currency = $Currency; telemetry = $Telemetry; eula_version = $EulaVersion
  accepted_at = $Now; machine_id = $MachineId; install_token = $InstallToken
} | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $askHome "license.json") -Encoding UTF8
Tick "license record written to $askHome\license.json"

# Paid opt-out persisted to the binary's config (%APPDATA%\ask\config.toml).
if ($Telemetry -eq 'off') {
  $cfgDir = Join-Path $env:APPDATA "ask"
  New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
  $cfgFile = Join-Path $cfgDir "config.toml"
  $existing = if (Test-Path $cfgFile) { Get-Content $cfgFile -Raw } else { "" }
  if ($existing -notmatch '\[telemetry\]') {
    Add-Content -Path $cfgFile -Value "`n[telemetry]`nenabled = false"
  }
}

# ─── 3. Binary — download from the latest GitHub Release, checksum-verified ─
Write-Host ""
Step 2 "Installing the binary"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$localSdk = Join-Path (Get-Location) "builds\windows-x86_64\ask-token-optimizer.exe"
$exeTmp = Join-Path $env:TEMP "ato-download.exe"

if (Test-Path $localSdk) {
  Copy-Item $localSdk $exeTmp -Force
  Tick "using bundled SDK binary"
} else {
  $tag = if ($env:ATO_VERSION) { $env:ATO_VERSION } else { "latest" }
  $base = if ($tag -eq "latest") { "https://github.com/$Repo/releases/latest/download" } else { "https://github.com/$Repo/releases/download/$tag" }
  Write-Host "     ${dim}downloading $AssetName ($tag)...${reset}"
  Invoke-WebRequest -Uri "$base/$AssetName" -OutFile $exeTmp -UseBasicParsing
  # Verify against the .sha256 sidecar (format: "<hex>  <name>")
  try {
    $shaLine = (Invoke-WebRequest -Uri "$base/$AssetName.sha256" -UseBasicParsing).Content
    $want = ([string]$shaLine).Trim().Split(' ')[0].ToLower()
    $have = (Get-FileHash $exeTmp -Algorithm SHA256).Hash.ToLower()
    if ($want -and ($want -ne $have)) {
      Write-Host "     ${gold}!${reset} checksum mismatch — aborting install."
      Remove-Item $exeTmp -Force; exit 1
    }
    Tick "checksum verified"
  } catch {
    Write-Host "     ${dim}checksum sidecar unavailable — continuing without verification${reset}"
  }
}

Copy-Item $exeTmp (Join-Path $installDir "ask-token-optimizer.exe") -Force
Copy-Item $exeTmp (Join-Path $installDir "ask.exe")                 -Force
Remove-Item $exeTmp -Force -ErrorAction SilentlyContinue
$Version = ""
try { $Version = ((& "$installDir\ask.exe" --version) -replace '[^0-9.]', '').Trim() } catch { $Version = "" }
Tick "ask-token-optimizer.exe  ->  $installDir  $(if ($Version) { "(v$Version)" })"
Tick "ask.exe                  ->  short alias"

# ─── 4. PATH ────────────────────────────────────────────────────────────────
Step 3 "Adding to user PATH"
$current = [Environment]::GetEnvironmentVariable("Path", "User")
if ($current -notlike "*$installDir*") {
  [Environment]::SetEnvironmentVariable("Path", "$current;$installDir", "User")
  $env:Path += ";$installDir"
  Tick "appended $installDir"
} else {
  Tick "already on PATH"
}

# ─── 5. Hook templates ──────────────────────────────────────────────────────
Step 4 "Staging hook templates"
New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
if (Test-Path "hooks") {
  Get-ChildItem "hooks\*" -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $hookDir $_.Name) -Force
  }
  Tick "templates -> $hookDir"
} else {
  Write-Host "     ${dim}no hooks\ folder here — clone the repo or fetch hooks/ from GitHub, then re-run${reset}"
}

# ─── Verification ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}─── Verification ──────────────────────────────────────────${reset}"
Write-Host ""
& "$installDir\ask-token-optimizer.exe" --version
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
Write-Host "   3.  Run  ${gold}ask audit${reset}  after a few commands to see your savings"
Write-Host ""
Write-Host "   ${dim}Docs:${reset}  README.md  ·  INSTALL-WINDOWS.md"
Write-Host ""
