# Changelog

All notable changes to ASK Token Optimizer. Dates UTC.


## [0.4.6] — 2026-06-26
### Added
- **Weekly telemetry sender** — lean, opportunistic, **no timer/daemon**. Piggybacks the per-command hook: once ≥7 days since the last send it stamps `~/.ask/.telemetry_sent` and spawns a detached child that POSTs only anonymous totals (tokens saved · run count · OS · version). Honors `DO_NOT_TRACK`, `[telemetry] enabled = false`, and per-install opt-out.
- **Install-time telemetry consent.** Free/community tier keeps telemetry on (the exchange for free use); commercial license is **opt-out, default on**, persisted to `~/.config/ask/config.toml`. Positive framing — "private by design: only the totals you save."
- **Commercial = real subscription.** First month **free**, then **CAD $25 / seat / year, auto-renewing**; a **valid card is required** at signup (captured up front, $0 for 30 days, first charge at day 30, recurs yearly). Pay by card (USD/CAD) or BTC; receipt, activation, and a "billed tomorrow" reminder are sent by email.
### Changed
- Built + published entirely via our automated CI/CD pipeline (all 5 platforms incl. macOS arm64/x86_64).

## [0.4.5] — 2026-06-24
### Fixed
- **npm `install` / `ci` / `i` now optimized** (#5). The rewrite matcher was `^npm (run|exec)`, so the highest-output npm commands (`npm install`, `npm ci`) slipped past unoptimized while `npm run build` was handled. Extended to `(run|exec|install|ci|i|update|audit)`. Reported by @Offbeatmammal.
### Added
- **Commercial subscription: CAD $25 / seat / year** — licensing table + install-time capture (company + seats) in `setup.sh`; plan `seat-25-yearly`.
- **"Updating" section** in the README (answers "how do we update?", #6) — re-run `setup.sh` / `install.ps1`, or grab the latest release; `ask --version`.
### Notes
- Enterprise installs + activates without hard-block (honor-system + auto invoice).
- README + setup.sh changes are already live on `main`; the binary release ships with this version.

## [0.4.4] — 2026-06-20
### Added
- Welcome email across all tiers; `api.ask-ai.ca` registration endpoint live.
- CAD pricing; per-command savings SVG in the README.
### Changed
- Docs/infra release (binaries carried from 0.4.3).

## [0.4.3] — 2026-06-20
### Added
- First public binary release: linux x86_64/arm64, macOS x86_64/arm64, windows x86_64.

## [0.4.2] — prior
- Baseline public release.
