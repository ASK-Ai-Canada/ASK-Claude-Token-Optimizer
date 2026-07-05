# ASK Token Optimizer — Windows Installer
# Brand: ASK-Ai · 2026 Executive Style
#
# Run from PowerShell (NOT cmd):
#   .\install.ps1
# (If downloaded as a single file and blocked by policy:  powershell -ExecutionPolicy Bypass -File .\install.ps1 )
#
# What this does (no admin required):
#   1. License clickwrap + registration (free / commercial - seats, CAD or USD)
#   2. Downloads the latest binary from GitHub Releases (checksum-verified, retried)
#   3. Installs to %USERPROFILE%\.local\bin\ + adds to user PATH (persistent)
#   4. Stages hook templates (fetched from the repo if not local) + offers to wire them

param(
  [switch]$AcceptLicense,
  [string]$Email = "",
  [string]$FullName = "",
  [ValidateSet("", "free", "commercial")][string]$Tier = "",
  [string]$Seats = "",
  [string]$Currency = "",
  [switch]$TelemetryOptOut,
  [switch]$NonInteractive
)
# Headless = agent/CI mode: identity via params, zero prompts, fail fast on missing input.
$Headless = $NonInteractive.IsPresent -or ($Email -ne "")

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Older Windows defaults to TLS 1.0 - GitHub requires 1.2+. Harmless where already set.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$EulaVersion = "1.2"
$RegisterUrl = if ($env:ATO_REGISTER_URL) { $env:ATO_REGISTER_URL } else { "https://api.ask-ai.ca/v1/ato" }
$Repo        = "ASK-Ai-Canada/ASK-Claude-Token-Optimizer"
$AssetName   = "ask-token-optimizer-windows-x86_64.exe"

# ==ATO-STRINGS BEGIN== (generated from installer-strings.toml - edit there, run tools/gen_installer_strings.py)
$S_TAGLINE = 'token filtering for Claude Code'
$S_LIC_FREE = 'Free for individuals and companies under CAD $100,000/year revenue.'
$S_LIC_COMMERCIAL = 'Companies at or above CAD $100,000/year revenue need a paid Commercial License.'
$S_LIC_TERMS = 'Full terms: LICENSE in the repository. Governing law: Canada.'
$S_REVENUE_PROMPT = 'Is your organization''s annual gross revenue UNDER CAD $100,000? [Y/n]'
$S_NEXT_SHELL = 'Open a new PowerShell window'
$S_NEXT_CLAUDE = 'Restart Claude Code'
# ==ATO-STRINGS END==

# Brand colors - closest 24-bit ANSI to the 2026 Executive Style spec.
$gold     = "$([char]27)[38;2;198;161;91m"   # #C6A15B Sovereign gold
$paleGold = "$([char]27)[38;2;232;215;168m"  # #E8D7A8 Pale gold
$charcoal = "$([char]27)[38;2;43;47;54m"     # #2B2F36 Charcoal text
$dim      = "$([char]27)[2m"
$reset    = "$([char]27)[0m"

# Console capability: Unicode box art on Windows Terminal / PS7 / UTF-8 codepages;
# clean ASCII everywhere else (legacy conhost, ssh sessions, OEM codepages).
$uni = $false
try {
  if ($env:WT_SESSION) { $uni = $true }
  elseif ($PSVersionTable.PSVersion.Major -ge 7) { $uni = $true }
  elseif ([Console]::OutputEncoding.CodePage -eq 65001) { $uni = $true }
} catch { $uni = $false }
if ($uni) {
  $gTL = [string][char]0x250C; $gTR = [string][char]0x2510
  $gBL = [string][char]0x2514; $gBR = [string][char]0x2518
  $gH  = [string][char]0x2500; $gV  = [string][char]0x2502
  $gTick = [string][char]0x2713; $gDot = [string][char]0x25CF
  $gStar = [string][char]0x2605; $gMid = [string][char]0x00B7
} else {
  $gTL = "+"; $gTR = "+"; $gBL = "+"; $gBR = "+"
  $gH = "-"; $gV = "|"; $gTick = "OK"; $gDot = "*"; $gStar = "*"; $gMid = "-"
}
$gBar = $gH * 57

function Banner {
  Write-Host ""
  Write-Host "   ${gold}${gTL}${gBar}${gTR}${reset}"
  Write-Host "   ${gold}${gV}${reset}                                                         ${gold}${gV}${reset}"
  Write-Host "   ${gold}${gV}${reset}     ${gold}A S K${reset}   ${paleGold}Token Optimizer${reset}                       ${gold}${gV}${reset}"
  Write-Host "   ${gold}${gV}${reset}     ${dim}$($S_TAGLINE.PadRight(49))${reset}${gold}${gV}${reset}"
  Write-Host "   ${gold}${gV}${reset}                                                         ${gold}${gV}${reset}"
  Write-Host "   ${gold}${gBL}${gBar}${gBR}${reset}"
  Write-Host ""
  Write-Host "   ${dim}Windows x86_64   ${gMid}   Executive Edition${reset}"
  Write-Host ""
}

function Step([int]$n, [string]$msg) {
  Write-Host "   ${gold}${gDot}${reset} ${charcoal}Step $n${reset}  ${msg}"
}

function Tick([string]$msg) {
  Write-Host "     ${gold}${gTick}${reset} $msg"
}

# Download with 3 attempts + backoff. Returns $true on success.
function Save-Remote([string]$Uri, [string]$OutFile) {
  for ($i = 1; $i -le 3; $i++) {
    try {
      Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 180
      return $true
    } catch {
      if ($i -lt 3) { Start-Sleep -Seconds (2 * $i) }
    }
  }
  return $false
}

$installDir = "$env:USERPROFILE\.local\bin"
$hookDir    = "$env:USERPROFILE\.claude\hooks"
$askHome    = "$env:USERPROFILE\.ask"

Banner

# ─── 1. License acceptance (clickwrap, before anything else) ────────────────
if (-not $AcceptLicense) {
  if ($Headless) { Write-Host "   Headless install requires -AcceptLicense. Aborting."; exit 1 }
  Write-Host "   ${charcoal}ASK Token Optimizer - Dual License (Community + Commercial)${reset}"
  Write-Host "     ${dim}- $S_LIC_FREE${reset}"
  Write-Host "     ${dim}- $S_LIC_COMMERCIAL${reset}"
  Write-Host "     ${dim}- $S_LIC_TERMS${reset}"
  Write-Host ""
  $reply = Read-Host "   Type 'accept' to agree to the LICENSE and continue"
  if ($reply -ne 'accept') { Write-Host "   License not accepted. Aborting."; exit 1 }
}

# ─── 2. Registration - identical contract to setup.sh ──────────────────────
# Upgrade re-runs never re-interview a registered box (deployment-report fix #2).
$SkipReg = $false; $existingLic = $null
$licPath = Join-Path $askHome "license.json"
if ((Test-Path $licPath) -and -not $Email) {
  try { $existingLic = Get-Content $licPath -Raw | ConvertFrom-Json } catch {}
  if ($existingLic -and $existingLic.email -and $existingLic.install_token) { $SkipReg = $true }
}
Write-Host ""
Step 1 "Registration"
$Company = ""
if ($SkipReg) {
  $Email = "$($existingLic.email)"; $FullName = "$($existingLic.name)"
  $Tier = "$($existingLic.tier)"; $Company = "$($existingLic.company)"
  $Seats = "$($existingLic.seats)"; $Currency = "$($existingLic.currency)"
  if (-not $Tier) { $Tier = "free" }
  Tick "already registered as $Email ($Tier) - skipping registration"
}
if (-not $SkipReg) {
while ($Email -notmatch '@') {
  if ($Headless) { Write-Host "     Headless install requires a valid -Email. Aborting."; exit 1 }
  $Email = (Read-Host "     Work email (for your free license + weekly savings report)").Trim()
}
if (-not $Headless -and -not $FullName) { $FullName = (Read-Host "     Full name (optional, press Enter to skip)").Trim() }

if (-not $Tier) { $Tier = "free" }
if ($Headless) {
  if ($Tier -eq 'commercial') {
    if ($Seats -notmatch '^\d+$') { $Seats = "1" }
    $Currency = $Currency.ToLower()
    if ($Currency -ne 'cad' -and $Currency -ne 'usd') { Write-Host "     Headless commercial requires -Currency CAD or USD. Aborting."; exit 1 }
  }
} else {
$Tier = "free"; $Company = ""; $Seats = ""; $Currency = ""
$r = (Read-Host "     $S_REVENUE_PROMPT").Trim()
if ($r -match '^[Nn]') {
  $Tier = "commercial"
  Write-Host ""
  Write-Host "     ${paleGold}Business use at or above `$100k runs on a commercial subscription:${reset}"
  Write-Host "     ${paleGold}ASK Token Optimizer - `$25 per seat / year (first month FREE).${reset}"
  $Company = (Read-Host "     Company / organization name").Trim()
  $Seats = (Read-Host "     Number of seats").Trim()
  if ($Seats -notmatch '^\d+$') { $Seats = "1" }
  # Mandatory billing currency - CAD (adds 15% HST) or USD (foreign sale, no CA tax). No default.
  while ($Currency -ne 'cad' -and $Currency -ne 'usd') {
    $Currency = (Read-Host "     Billing currency - type CAD or USD (required)").Trim().ToLower()
    if ($Currency -ne 'cad' -and $Currency -ne 'usd') { Write-Host "     ${dim}Please type CAD or USD.${reset}" }
  }
  $yearly = 25 * [int]$Seats
  if ($Currency -eq 'cad') {
    Write-Host "     Plan: CAD `$25 / seat / year x $Seats seat(s) = CAD `$$yearly + 15% HST / year."
  } else {
    Write-Host "     Plan: USD `$25 / seat / year x $Seats seat(s) = USD `$$yearly / year (no CA tax)."
  }
  Write-Host "     ${dim}${gStar} First month FREE - no charge for 30 days; cancel anytime before then.${reset}"
}
}

# Telemetry - community: always on (the exchange for free use); paid: optional, default on.
$Telemetry = "on"
if ($Tier -eq 'free') {
  Write-Host ""
  Write-Host "     ${dim}Help us improve - anonymous savings stats keep the free tier free.${reset}"
  Write-Host "     ${dim}Private by design: only the totals you save are shared.${reset}"
} else {
  if ($Headless) {
    if ($TelemetryOptOut) { $Telemetry = "off" }
  } else {
    Write-Host ""
    Write-Host "     [x] Help us improve - share anonymous savings stats. Private by design."
    $to = (Read-Host "         Press Enter to keep enabled, or type 'no' to opt out").Trim()
    if ($to -match '^[Nn]') { $Telemetry = "off" }
  }
}
# end of first-registration interview
}

# ==ATO-CARD donation BEGIN== (generated from installer-strings.toml - edit there, run tools/gen_installer_strings.py)
$DonateAmount = ""; $DonateSeats = ""; $DonateTarget = ""
if ($Tier -eq 'free' -and -not $Headless -and -not $SkipReg) {
  Write-Host ""
  Write-Host "  ${dim}★ Give back (optional) — you're on the free community tier.${reset}"
  Write-Host "  ${dim}  ASK Token Optimizer is free for you. If it's helping, consider a yearly gift to the${reset}"
  Write-Host "  ${dim}  Atlantic Centre of Excellence for Advanced Technology & Intelligence (ACATI)${reset}"
  Write-Host "  ${dim}  Foundation — a registered non-profit bringing tech literacy to community and business${reset}"
  Write-Host "  ${dim}  leaders in underserved Atlantic Canadian communities.${reset}"
  Write-Host "  ${dim}  100% goes to the Foundation — ASK-AI covers the processing and keeps nothing.${reset}"
  Write-Host "  ${dim}  Suggested CAD `$25 / seat / year; give any amount you like (minimum `$25).${reset}"
  Write-Host "  ${dim}  Learn more: https://acati.ca${reset}"
  $d = (Read-Host "  Add an optional tax-deductible donation? [y/N]").Trim()
  if ($d -match '^[Yy]') {
    $DonateSeats = (Read-Host "    Seats to sponsor [1]").Trim()
    if ($DonateSeats -notmatch '^[0-9]+$' -or [int]$DonateSeats -lt 1) { $DonateSeats = "1" }
    $sug = 25 * [int]$DonateSeats
    while ($true) {
      $DonateAmount = (Read-Host "    Annual gift in CAD (suggested `$$sug, minimum `$25)").Trim()
      if ($DonateAmount -match '^[0-9]+$' -and [int]$DonateAmount -ge 25) { break }
      Write-Host "      Please enter a whole dollar amount of `$25 or more."
    }
    $DonateTarget = "acati-foundation"
    Write-Host ""
    Write-Host "  ★ Thank you! We'll email $Email a secure link to complete your CAD `$$DonateAmount gift"
    Write-Host "    to the ACATI Foundation — 100% to the Foundation, and your receipt is tax-deductible."
    Write-Host ""
  }
}
# ==ATO-CARD donation END==

# Stable machine id: CIM product UUID, registry MachineGuid fallback, then hostname-only.
$hwid = ""
try { $hwid = (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch {}
if (-not $hwid) {
  try { $hwid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -ErrorAction Stop).MachineGuid } catch {}
}
$MachineId = "unknown"
try {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  $rawId = "$env:COMPUTERNAME|$env:USERNAME|$hwid"
  $MachineId = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rawId))) -replace '-', '').ToLower().Substring(0, 16)
} catch {}
$Now  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$Plan = if ($Tier -eq 'commercial') { "seat-25-yearly" } else { "free" }

if ($SkipReg) {
  $InstallToken = "$($existingLic.install_token)"; $CheckoutUrl = ""
  Tick "existing license kept ($licPath)"
} else {
$payload = @{
  email = $Email; name = $FullName; tier = $Tier; company = $Company; seats = $Seats
  currency = $Currency; plan = $Plan; telemetry = $Telemetry; eula_version = $EulaVersion
  donate_amount = $DonateAmount; donate_seats = $DonateSeats; donate_target = $DonateTarget
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
    Write-Host "     ${gold}${gStar} Your free month is active - nothing is blocked. Set up billing when convenient${reset}"
    Write-Host "     ${gold}  (you or your billing team - the link is forwardable; invoicing available):${reset}"
    Write-Host "       $CheckoutUrl"
    Write-Host "       ${dim}(link also emailed to $Email)${reset}"
    Write-Host ""
  }
} else {
  Write-Host "     ${dim}- registration deferred (offline) - the app completes it automatically in the background${reset}"
}

# Local license record - written unconditionally; the binary self-heals an
# empty install_token from this file.
New-Item -ItemType Directory -Force -Path $askHome | Out-Null
@{
  email = $Email; name = $FullName; tier = $Tier; company = $Company; seats = $Seats
  currency = $Currency; telemetry = $Telemetry; eula_version = $EulaVersion
  accepted_at = $Now; machine_id = $MachineId; install_token = $InstallToken
} | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $askHome "license.json") -Encoding UTF8
Tick "license record written to $askHome\license.json"
}

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

# ─── 3. Binary - latest GitHub Release, checksum-verified, retried ──────────
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
  if (-not (Save-Remote "$base/$AssetName" $exeTmp)) {
    Write-Host "     ${gold}!${reset} download failed after 3 attempts - check your connection and re-run."
    exit 1
  }
  # Verify against the .sha256 sidecar (format: "<hex>  <name>").
  # GitHub serves assets as octet-stream -> .Content is byte[]; decode before parsing.
  try {
    $shaRaw = (Invoke-WebRequest -Uri "$base/$AssetName.sha256" -UseBasicParsing -TimeoutSec 60).Content
    if ($shaRaw -is [byte[]]) { $shaRaw = [Text.Encoding]::ASCII.GetString($shaRaw) }
    $want = "$shaRaw".Trim().Split(' ')[0].ToLower()
    if ($want -match '^[0-9a-f]{64}$') {
      $have = (Get-FileHash $exeTmp -Algorithm SHA256).Hash.ToLower()
      if ($want -ne $have) {
        Write-Host "     ${gold}!${reset} checksum mismatch - aborting install."
        Remove-Item $exeTmp -Force; exit 1
      }
      Tick "checksum verified"
    } else {
      Write-Host "     ${dim}checksum sidecar unreadable - continuing without verification${reset}"
    }
  } catch {
    Write-Host "     ${dim}checksum sidecar unavailable - continuing without verification${reset}"
  }
}

Copy-Item $exeTmp (Join-Path $installDir "ask-token-optimizer.exe") -Force
Copy-Item $exeTmp (Join-Path $installDir "ask.exe")                 -Force
Remove-Item $exeTmp -Force -ErrorAction SilentlyContinue
$Version = ""
try { $Version = ((& "$installDir\ask.exe" --version) -replace '[^0-9.]', '').Trim() } catch { $Version = "" }
Tick "ask-token-optimizer.exe  ->  $installDir  $(if ($Version) { "(v$Version)" })"
Tick "ask.exe                  ->  short alias"

# Git Bash entry: a 4-line sh shim, NOT a PE copy. MSYS2_ARG_CONV_EXCL='*' stops
# Git Bash path-conversion from mangling args (the C:/Program ssh bug). Written via
# .NET file APIs (LF, no BOM) - writing it from MSYS would clobber ask.exe.
$shimPath = Join-Path $installDir "ask"
$shim = "#!/bin/sh`n# ASK Token Optimizer - Git Bash entry (do not edit; installer-owned)`nMSYS2_ARG_CONV_EXCL='*' exec `"`$(dirname `"`$0`")/ask.exe`" `"`$@`"`n"
[IO.File]::WriteAllText($shimPath, $shim, (New-Object System.Text.UTF8Encoding($false)))
$shimLen = (Get-Item $shimPath).Length
$exeLen  = (Get-Item (Join-Path $installDir "ask.exe")).Length
if ($shimLen -lt 1KB -and $exeLen -gt 1MB) {
  Tick "ask (Git Bash shim)      ->  MSYS-safe entry ($shimLen B)"
} else {
  Write-Host "   ! shim/exe size check failed (shim=$shimLen exe=$exeLen) - Git Bash entry may be wrong"
}

# ─── 4. PATH (persistent, current-user scope - no elevation needed) ────────
Step 3 "Adding to user PATH"
$current = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $current) { $current = "" }
# Exact-segment, case-insensitive dedupe (Windows paths are case-insensitive).
# A plain substring/-like check would also true-positive on e.g. an unrelated
# "...\.local\bin2" sibling folder, so split on ';' and compare segments.
$pathSegments = $current -split ';' | Where-Object { $_ -ne '' }
$alreadyOnPath = $pathSegments | Where-Object { $_.TrimEnd('\') -ieq $installDir.TrimEnd('\') }
if (-not $alreadyOnPath) {
  $newPath = (@($pathSegments) + $installDir) -join ';'
  [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
  $env:Path += ";$installDir"
  Tick "appended $installDir to your User PATH"
  Write-Host "     ${dim}restart your terminal (or open a new shell) for 'ask' to be found on PATH${reset}"
} else {
  Tick "already on PATH"
}

# ─── 5. Hook templates (local repo copy, or fetched from GitHub) ────────────
Step 4 "Staging hook templates"
New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
if (Test-Path "hooks") {
  Get-ChildItem "hooks\*" -File | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $hookDir $_.Name) -Force
  }
  Tick "templates -> $hookDir"
} else {
  # Standalone install.ps1 (no repo folder) - fetch the Windows hooks from GitHub.
  $fetched = 0
  foreach ($hf in @("ask-rewrite.py", "ask-filter.py", "ato_telemetry.py")) {
    if (Save-Remote "https://raw.githubusercontent.com/$Repo/main/hooks/$hf" (Join-Path $hookDir $hf)) { $fetched++ }
  }
  if ($fetched -eq 3) { Tick "hooks fetched from GitHub -> $hookDir" }
  else { Write-Host "     ${dim}could not fetch all hooks ($fetched/3) - clone the repo and re-run, or copy hooks\ manually${reset}" }
}

# Windows-readable docs: stage plain-text copies the OS opens natively
$docsDir = Join-Path $env:USERPROFILE ".ask\docs"
New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
foreach ($doc in @(@("INSTALL-WINDOWS.md","INSTALL-WINDOWS.txt"), @("README.md","README.txt"))) {
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri "https://raw.githubusercontent.com/$Repo/main/$($doc[0])" -OutFile (Join-Path $docsDir $doc[1])
  } catch {}
}
if (Test-Path (Join-Path $docsDir "INSTALL-WINDOWS.txt")) { Tick "docs staged -> $docsDir (plain text)" }

# ─── Verification ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}$($gH * 3) Verification $($gH * 44)${reset}"
Write-Host ""
& "$installDir\ask-token-optimizer.exe" --version
Write-Host ""

# ─── Hook auto-wire ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}$($gH * 3) Claude Code hook wiring $($gH * 33)${reset}"
Write-Host ""
$settingsCandidates = @(
  "$env:USERPROFILE\.claude\settings.json",
  "$env:APPDATA\claude\settings.json"
)
$settingsPath = $null
foreach ($c in $settingsCandidates) { if (Test-Path $c) { $settingsPath = $c; break } }
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $settingsPath) {
  Write-Host "   ${dim}settings.json not found. Wire hooks manually after first Claude Code launch.${reset}"
  Write-Host "   See README.md for the JSON snippet."
} elseif (-not $python) {
  Write-Host "   ${dim}Python not found - the hooks need it. Install Python 3, then wire manually (README.md).${reset}"
} else {
  $content = Get-Content $settingsPath -Raw
  if ($content -like "*ask-rewrite*") {
    Tick "Hooks already wired in $settingsPath"
  } else {
    $wire = if ($Headless) { "n" } else { Read-Host "   Wire optimizer hooks into settings.json now? [y/N]" }
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
      else { Write-Host "   ${gold}!${reset} Auto-wire failed - add manually (see README.md): $result" }
    } else {
      Write-Host "   ${dim}Skipped. See README.md > 'Activate the hooks' for the JSON snippet.${reset}"
    }
  }
}

# ─── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "   ${gold}$($gH * 3) You are set up $($gH * 42)${reset}"
Write-Host ""
Write-Host "   1.  $S_NEXT_SHELL  (so PATH refreshes)"
Write-Host "   2.  $S_NEXT_CLAUDE"
Write-Host "   3.  Run  ${gold}ask audit${reset}  after a few commands to see your savings"
Write-Host ""
Write-Host "   ${dim}Docs:${reset}  $docsDir\INSTALL-WINDOWS.txt  $gMid  README.txt"
Write-Host ""
