# Changelog

What's improved, version by version. Check the version you're on with `ask --version`, then read up from there to see everything that's changed since. Newest first.

---

## 0.5.2 — 2026-07-04
- **Install with Homebrew.** `brew install ASK-Ai-Canada/tap/ask-token-optimizer` on macOS and Linux — and on macOS it installs with no Gatekeeper warning.
- **Runs on Alpine and every Linux distro now.** New static builds work on musl systems (Alpine, minimal containers) as well as glibc (Debian, Ubuntu, Fedora, Arch); the installer picks the right one for you.
- **Community & non-profit support.** Free-tier installs can add an optional, tax-deductible donation to the Atlantic Centre of Excellence for Advanced Technology & Intelligence (ACATI) Foundation — 100% goes to the Foundation, funding tech literacy in underserved Atlantic Canadian communities.
- `ask gain` works again — it now runs `ask audit` (its name since 0.5.0) instead of erroring, in case the old command is in your muscle memory.

## 0.5.1 — 2026-07-02
- **Refined install flow** — registration retries and self-completes in the background if the first run hits a network blip, so you are never left half-installed.
- `ask gain` is now `ask audit` — clearer name for the savings command (same flags).

## 0.5.0 — 2026-07-01

- **New: `ask update`.** One command pulls the latest release (checksum-verified) and installs it. It also compares the release's hooks against yours and **asks before changing anything** — nothing is ever wired behind your back.
- **Large files are handled losslessly now.** `cat` / `read` on a huge log or data dump (`.jsonl`, build output) returns a head-and-tail summary that names the full file on disk, so nothing is lost — while **source code passes through byte-for-byte, never trimmed.** Around **84% less context** on big files.
- `ask gain` is now **`ask audit`** (same flags: `--graph`, `--by-version`, `--project`). Command surface tidied up.

## 0.4.6 — 2026-06-26

- **Restored optimization on common flag forms** — `grep -E`, `grep -i`, `grep -r`, and similar — that an earlier build had begun passing through unfiltered. **If your savings dipped on 0.4.3–0.4.5, upgrading brings them back.**
- Now built and shipped through a full CI pipeline for all five targets: Linux x86_64/arm64, macOS x86_64/arm64, Windows x86_64.
- Lean, opt-out weekly telemetry — anonymous **totals only**, never your commands or their output.

## 0.4.5 — 2026-06-25

- **Wider coverage:** `npm install` / `ci` / `i` and siblings are now optimized — previously the highest-output npm commands slipped through unfiltered.
- Added an in-README "Updating" guide.

## 0.4.4 — 2026-06-20

- Registration + welcome flow, and CAD pricing.
- Added the per-command savings chart to the README so you can see exactly where the tokens go.

## 0.4.3 — 2026-06-20

- **First prebuilt binary release** — Linux x86_64/arm64, macOS x86_64/arm64, Windows x86_64. Download and run; no build step.

## 0.4.2 — 2026-06-05

- First public release. The core: catch high-output commands, filter the noise before it reaches your model, and log every saving locally so you can audit your own numbers.
