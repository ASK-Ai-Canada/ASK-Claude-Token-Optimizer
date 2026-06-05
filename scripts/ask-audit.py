#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════════════╗
║  ASK TOKEN OPTIMIZER — MASTER AUDIT SCRIPT                                  ║
║  ask-audit.py  ·  v1.0  ·  ships in scripts/                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  MAINTAINER NOTES FOR CLAUDE CODE (READ BEFORE EDITING)                      ║
║                                                                              ║
║  PURPOSE                                                                     ║
║  Produces a 9-section verbose token-savings audit from history.db.           ║
║  Also supports --by-version (requires version column, added in v0.4.1).      ║
║                                                                              ║
║  DB SCHEMA (history.db · SQLite)                                             ║
║  ─────────────────────────────────────────────────────────────────────────   ║
║  Table: commands                                                             ║
║    id           INTEGER  PRIMARY KEY                                         ║
║    timestamp    TEXT     ISO-8601 UTC  e.g. "2026-06-04T12:00:00Z"          ║
║    original_cmd TEXT     raw command   e.g. "git status"                    ║
║    rtk_cmd      TEXT     wrapped form  e.g. "ask git status"                ║
║    input_tokens INTEGER  estimated raw output token count                   ║
║    output_tokens INTEGER filtered output token count                        ║
║    saved_tokens  INTEGER input - output  (never negative)                   ║
║    savings_pct   REAL    100 * saved / input  (0.0 if input = 0)            ║
║    exec_time_ms  INTEGER wall-clock ms (may be 0 on older rows)             ║
║    project_path  TEXT    cwd at time of command ('' on older rows)          ║
║    version       TEXT    ATO binary version that recorded the row           ║
║                          e.g. "0.4.2" · '' on rows from before v0.4.1      ║
║                                                                              ║
║  Table: parse_failures                                                       ║
║    id                   INTEGER  PRIMARY KEY                                ║
║    timestamp            TEXT                                                 ║
║    raw_command          TEXT     the command that failed to parse           ║
║    error_message        TEXT                                                 ║
║    fallback_succeeded   INTEGER  1 = passthrough worked, 0 = errored        ║
║                                                                              ║
║  PARAMETERS (all CLI flags — see argparse section below)                    ║
║  ─────────────────────────────────────────────────────────────────────────   ║
║  --db PATH          path to history.db  (default: platform-detected)        ║
║  --days N           look-back window in days  (default: 30)                 ║
║  --cap N            max tokens/command for inflation detection  (250 000)   ║
║  --ratio N          chars-per-token estimate  (default: 4.0)                ║
║  --format           text | json | csv  (default: text)                      ║
║  --sections         comma-list of section numbers, or "all"  (default: all) ║
║  --by-version       add §10 version-epoch breakdown (requires v col)        ║
║  --tenant-id        tag audit events pushed to RuVector                     ║
║  --user-id          tag for RuVector push                                   ║
║  --device-id        tag for RuVector push                                   ║
║  --agent-id         tag for RuVector push                                   ║
║  --push-ruvector URL  push audit to RuVector at URL (requires --tenant-id)  ║
║                                                                              ║
║  9 SECTIONS (+ optional §10)                                                ║
║  ─────────────────────────────────────────────────────────────────────────   ║
║  §1  Scorecard              overall headline numbers                         ║
║  §2  Commands by tokens     ranked list, * = raw > 1.5× cap                ║
║  §3  Daily breakdown        14-day rolling window                           ║
║  §4  Savings by category    Filesystem / Network / Git / Other              ║
║  §5  Hour-of-day heatmap    when your savings peak                          ║
║  §6  Zero-savings commands  optimization targets                            ║
║  §7  Last 20 commands       most recent, with ▲/■/• tier markers           ║
║  §8  Commands over cap      inflation check                                 ║
║  §9  Inflation analysis     v0.2.0 claimed vs v0.2.1 honest (cap-aware)    ║
║  §10 Version-epoch timeline requires --by-version; needs version column     ║
║                             (added in v0.4.1 · earlier rows version='')    ║
║                                                                              ║
║  HONEST AUDIT REASONING (shown in §9 / §10 · do not remove)                ║
║  ─────────────────────────────────────────────────────────────────────────   ║
║  The headline savings % is often skewed by a single high-volume command     ║
║  (e.g. one grep on a large codebase).  §9 detects cap-overflow inflation.  ║
║  --by-version §10 adds the steady-state rate (top-1 outlier removed) per   ║
║  version epoch so operators can see true improvement across releases.       ║
║                                                                              ║
║  ADDING A NEW SECTION                                                        ║
║  ─────────────────────────────────────────────────────────────────────────   ║
║  1. Add section number + title to SECTION_TITLES dict below                 ║
║  2. Add a show_sections gate:  if N in show_sections: <render>              ║
║  3. Use the box() helper for consistent borders                             ║
║  4. Bump the script version comment at top                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
"""
import argparse, csv, io, json, os, platform, sqlite3, sys
from datetime import datetime, timedelta, timezone
from collections import defaultdict

# ── CLI ────────────────────────────────────────────────────────────────────────
def default_db_path() -> str:
    if platform.system() == "Windows":
        return os.path.expandvars(r"%LOCALAPPDATA%\ask\history.db")
    return os.path.expanduser("~/.local/share/ask/history.db")

parser = argparse.ArgumentParser(
    description="ASK Token Optimizer — master verbose audit",
    formatter_class=argparse.RawDescriptionHelpFormatter,
)
parser.add_argument("--db",           default=default_db_path(),    metavar="PATH",
                    help="Path to history.db (default: platform-detected)")
parser.add_argument("--cap",          type=int,   default=250_000,  metavar="N",
                    help="Per-command token cap for inflation detection (default: 250000)")
parser.add_argument("--days",         type=int,   default=30,       metavar="N",
                    help="Look-back window in days (default: 30)")
parser.add_argument("--format",       choices=["text","json","csv"], default="text",
                    help="Output format (default: text)")
parser.add_argument("--ratio",        type=float, default=4.0,      metavar="N",
                    help="Chars-per-token estimate used only in legend (default: 4.0)")
parser.add_argument("--sections",     default="all",
                    help="Comma-separated section numbers to show, or 'all' (default: all)")
parser.add_argument("--by-version",   action="store_true",
                    help="Add §10: version-epoch timeline (requires version column, v0.4.1+)")
parser.add_argument("--tenant-id",    default=None, metavar="ID")
parser.add_argument("--user-id",      default=None, metavar="ID")
parser.add_argument("--device-id",    default=None, metavar="ID")
parser.add_argument("--agent-id",     default=None, metavar="ID")
parser.add_argument("--push-ruvector",default=None, metavar="URL",
                    help="Push audit JSON to RuVector at URL (requires --tenant-id)")
args = parser.parse_args()

# ── Section filter ─────────────────────────────────────────────────────────────
if args.sections == "all":
    show_sections = set(range(1, 11))
else:
    show_sections = {int(s.strip()) for s in args.sections.split(",") if s.strip().isdigit()}

db_path = args.db
CAP     = args.cap
WINDOW_DAYS = args.days
OUTPUT_FORMAT = args.format

# ── DB ─────────────────────────────────────────────────────────────────────────
if not os.path.exists(db_path):
    print(f"history.db not found at: {db_path}", file=sys.stderr)
    print("Run a few commands through Claude Code first, then re-run this audit.", file=sys.stderr)
    sys.exit(1)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cur  = conn.cursor()

cutoff = (datetime.now(timezone.utc) - timedelta(days=WINDOW_DAYS)).isoformat()
rows_all = cur.execute(
    "SELECT * FROM commands ORDER BY timestamp ASC"
).fetchall()
rows = [r for r in rows_all if (r["timestamp"] or "") >= cutoff]

# ── Helpers ────────────────────────────────────────────────────────────────────
W = 108  # box width

def box_top(title=""):
    if title:
        return f"╔══  {title}  {'═' * max(0, W - len(title) - 6)}╗"
    return "╔" + "═" * W + "╗"

def box_sep():  return "╠" + "─" * W + "╣"
def box_bot():  return "╚" + "═" * W + "╝"

def row(text="", width=W):
    pad = width - len(text)
    return f"║  {text}{' ' * max(0, pad - 2)}║"

def bar(pct, width=30):
    filled = int(pct / 100 * width)
    return "▓" * filled + "·" * (width - filled)

def fmt_k(n):
    if n >= 1_000_000: return f"{n/1_000_000:.1f}M"
    if n >= 1_000:     return f"{n/1_000:.1f}K"
    return str(n)

def category(cmd):
    c = (cmd or "").lower()
    if any(c.startswith(x) for x in ("ask git","ask gh","ask gt")): return "Git"
    if any(c.startswith(x) for x in ("ask curl","ask wget","ask http")): return "Network"
    if any(c.startswith(x) for x in ("ask ls","ask find","ask tree","ask read","ask grep","ask cat")): return "Filesystem"
    return "Other"

# ── Aggregate ──────────────────────────────────────────────────────────────────
total_cmds   = len(rows)
total_in     = sum(r["input_tokens"]  or 0 for r in rows)
total_in_cap = sum(min(r["input_tokens"] or 0, CAP) for r in rows)
total_out    = sum(r["output_tokens"] or 0 for r in rows)
total_sav    = sum(r["saved_tokens"]  or 0 for r in rows)
total_ms     = sum(r["exec_time_ms"]  or 0 for r in rows)
overall_pct  = 100 * total_sav / total_in if total_in else 0.0

# ── Command-level aggregation ─────────────────────────────────────────────────
cmd_stats: dict = defaultdict(lambda: {"runs":0,"in_raw":0,"in_cap":0,"out":0,"sav":0,"ms":0})
for r in rows:
    k = r["rtk_cmd"] or r["original_cmd"] or "?"
    s = cmd_stats[k]
    s["runs"]   += 1
    s["in_raw"] += r["input_tokens"]  or 0
    s["in_cap"] += min(r["input_tokens"] or 0, CAP)
    s["out"]    += r["output_tokens"] or 0
    s["sav"]    += r["saved_tokens"]  or 0
    s["ms"]     += r["exec_time_ms"]  or 0

sorted_cmds = sorted(cmd_stats.items(), key=lambda x: x[1]["sav"], reverse=True)

# ── Render (text mode) ─────────────────────────────────────────────────────────
if OUTPUT_FORMAT == "text":

    # §1 Scorecard
    if 1 in show_sections:
        print(box_top(f"1 · SCORECARD"))
        print(box_sep())
        print(row(f"Total commands               {total_cmds}"))
        print(row(f"Input  (raw)              {fmt_k(total_in):>8}  ← what v0.2.0 reported"))
        print(row(f"Input  (capped @{fmt_k(CAP)})  {fmt_k(total_in_cap):>8}  ← honest ceiling"))
        print(row(f"Output (filtered)          {fmt_k(total_out):>6}"))
        print(row(f"Tokens saved              {fmt_k(total_sav):>8}  ({overall_pct:.1f}%)"))
        print(row(f"Exec time                   {total_ms//1000}s  (avg {total_ms//max(1,total_cmds)}ms/cmd)"))
        print(row())
        print(row(f"Overall efficiency   {overall_pct:.1f}%  {bar(overall_pct)}"))
        print(box_bot())
        print()

    # §2 Commands by savings
    if 2 in show_sections:
        print(box_top(f"2 · ALL COMMANDS BY TOKENS SAVED (capped)  [* = raw exceeded 1.5× cap]"))
        print(box_sep())
        print(row(f"{'#':>5}  {'Command':<38} {'Runs':>5}   {'In(raw)':>7}   {'In(cap)':>7}    {'Output':>6}     {'Saved':>6}      {'%':>5}  {'Bar':<30}"))
        print(box_sep())
        for i, (cmd, s) in enumerate(sorted_cmds, 1):
            pct   = 100 * s["sav"] / s["in_raw"] if s["in_raw"] else 0
            star  = "*" if s["in_raw"] > 1.5 * CAP else " "
            label = (cmd[:36] + "..") if len(cmd) > 38 else cmd
            print(row(f"{i:>5}  {label:<38} {s['runs']:>5}   {fmt_k(s['in_raw']):>7}   {fmt_k(s['in_cap']):>7}    {fmt_k(s['out']):>6}     {fmt_k(s['sav']):>6}  {pct:>5.1f}%  {bar(pct)}{star}"))
        print(box_sep())
        print(row(f"       {'TOTAL':<38} {total_cmds:>5}      {fmt_k(total_in):>7}   {fmt_k(total_in_cap):>7}    {fmt_k(total_out):>6}     {fmt_k(total_sav):>6}  {overall_pct:>5.1f}%"))
        print(box_bot())
        print()

    # §3 Daily breakdown (last 14 days)
    if 3 in show_sections:
        daily: dict = defaultdict(lambda: {"cmds":0,"in":0,"out":0,"sav":0,"ms":0})
        for r in rows:
            d = (r["timestamp"] or "")[:10]
            daily[d]["cmds"] += 1
            daily[d]["in"]   += r["input_tokens"]  or 0
            daily[d]["out"]  += r["output_tokens"] or 0
            daily[d]["sav"]  += r["saved_tokens"]  or 0
            daily[d]["ms"]   += r["exec_time_ms"]  or 0
        print(box_top(f"3 · DAILY BREAKDOWN (14 days)"))
        print(box_sep())
        print(row(f"  {'Date':<12} {'Cmds':>5}     {'In(raw)':>8}     {'In(cap)':>8}    {'Output':>7}     {'Saved':>6}  {'Save%':>6}     {'AvgMs':>6}  Note"))
        print(box_sep())
        sav_vals = [v["sav"] for v in daily.values()]
        mx = max(sav_vals) if sav_vals else 1
        for d in sorted(daily)[-14:]:
            v  = daily[d]
            p  = 100 * v["sav"] / v["in"] if v["in"] else 0
            av = v["ms"] // max(1, v["cmds"])
            in_cap = min(v["in"], CAP * v["cmds"])
            print(row(f"  {d:<12} {v['cmds']:>5}     {fmt_k(v['in']):>8}     {fmt_k(in_cap):>8}    {fmt_k(v['out']):>7}     {fmt_k(v['sav']):>6}  {p:>5.1f}%     {av:>5}ms"))
        print(box_sep())
        print(row(f"  {'TOTAL':<12} {total_cmds:>5}     {fmt_k(total_in):>8}     {fmt_k(total_in_cap):>8}    {fmt_k(total_out):>7}     {fmt_k(total_sav):>6}  {overall_pct:>5.1f}%     {total_ms//max(1,total_cmds):>5}ms"))
        print(box_bot())
        print()

    # §4 Savings by category
    if 4 in show_sections:
        cat_stats: dict = defaultdict(lambda: {"cmds":0,"in":0,"sav":0})
        for r in rows:
            cat = category(r["rtk_cmd"] or "")
            cat_stats[cat]["cmds"] += 1
            cat_stats[cat]["in"]   += r["input_tokens"] or 0
            cat_stats[cat]["sav"]  += r["saved_tokens"] or 0
        print(box_top(f"4 · SAVINGS BY CATEGORY"))
        print(box_sep())
        print(row(f"  {'Category':<14} {'Cmds':>7}       {'Input':>8}       {'Saved':>6}  {'Save%':>6}  {'Share':>6}  Share bar"))
        print(box_sep())
        for cat, s in sorted(cat_stats.items(), key=lambda x: x[1]["sav"], reverse=True):
            p     = 100 * s["sav"] / s["in"]            if s["in"]    else 0
            share = 100 * s["sav"] / total_sav           if total_sav  else 0
            print(row(f"  {cat:<14} {s['cmds']:>7}       {fmt_k(s['in']):>8}       {fmt_k(s['sav']):>6}  {p:>5.1f}%  {share:>5.1f}%  {bar(share)}"))
        print(box_bot())
        print()

    # §5 Hour-of-day heatmap
    if 5 in show_sections:
        hourly: dict = defaultdict(int)
        for r in rows:
            try:
                h = int((r["timestamp"] or "00")[-8:-6].replace("T","").replace("-",""))
                h = datetime.fromisoformat((r["timestamp"] or "").replace("Z","+00:00")).hour
            except Exception:
                h = 0
            hourly[h] += r["saved_tokens"] or 0
        print(box_top(f"5 · HOUR-OF-DAY HEATMAP  (tokens saved, all sessions)"))
        print(box_sep())
        hmax = max(hourly.values()) if hourly else 1
        cells = [("█" if hourly.get(h,0)/hmax > 0.6 else "▄" if hourly.get(h,0)/hmax > 0.2 else " ") for h in range(24)]
        print(row(f"  00h {'─'*22} 23h"))
        print(row(f"  [{''.join(cells)}]"))
        top5 = sorted(hourly.items(), key=lambda x: x[1], reverse=True)[:5]
        print(row(f"  Peak hours: " + "   ".join(f"{h}h={fmt_k(v)}" for h,v in top5)))
        print(box_bot())
        print()

    # §6 Zero-savings commands
    if 6 in show_sections:
        zero = [(cmd, s) for cmd, s in sorted_cmds if s["sav"] == 0 and s["in_raw"] > 0]
        print(box_top(f"6 · ZERO-SAVINGS COMMANDS — optimization targets"))
        print(box_sep())
        print(row(f"  {'Command':<42} {'Runs':>5}  {'Wasted input':>12}  Action"))
        print(box_sep())
        for cmd, s in zero[:15]:
            label = (cmd[:40]+"..") if len(cmd) > 42 else cmd
            print(row(f"  {label:<42} {s['runs']:>5}  {fmt_k(s['in_raw']):>12}  needs filter rule"))
        if not zero:
            print(row("  All commands saving at least some tokens. Good."))
        print(box_bot())
        print()

    # §7 Last 20 commands
    if 7 in show_sections:
        recent = list(reversed(rows_all[-20:]))
        print(box_top(f"7 · LAST 20 COMMANDS  [▲=saved≥70%  ■=saved≥30%  •=low]"))
        print(box_sep())
        print(row(f"  {'Timestamp':<20} F  {'Command':<44} {'In(cap)':>8}       {'Out':>6}     {'Saved':>6}      {'%':>4}"))
        print(box_sep())
        for r in recent:
            inp = min(r["input_tokens"] or 0, CAP)
            sav = r["saved_tokens"] or 0
            out = r["output_tokens"] or 0
            pct = 100 * sav / inp if inp else 0
            flag = "▲" if pct >= 70 else "■" if pct >= 30 else "•"
            ts   = (r["timestamp"] or "")[:20]
            cmd  = (r["rtk_cmd"] or r["original_cmd"] or "?")[:44]
            print(row(f"  {ts:<20} {flag}  {cmd:<44} {fmt_k(inp):>8}       {fmt_k(out):>6}     {fmt_k(sav):>6}      {pct:>4.0f}%"))
        print(box_bot())
        print()

    # §8 Commands over cap
    if 8 in show_sections:
        over = [(cmd, s) for cmd, s in sorted_cmds if s["in_raw"] > CAP]
        print(box_top(f"8 · COMMANDS OVER {fmt_k(CAP)} CAP"))
        print(box_sep())
        if not over:
            print(row(f"  None — all {total_cmds} commands under {fmt_k(CAP)} cap. No inflation."))
        else:
            for cmd, s in over:
                label = (cmd[:40]+"..") if len(cmd) > 42 else cmd
                inflation = s["in_raw"] / CAP
                print(row(f"  {label:<42}  {fmt_k(s['in_raw'])} raw  ({inflation:.1f}× cap)  runs={s['runs']}"))
        print(box_bot())
        print()

    # §9 Inflation analysis — HONEST AUDIT
    if 9 in show_sections:
        claimed_in  = total_in
        claimed_sav = total_sav
        claimed_pct = 100 * claimed_sav / claimed_in if claimed_in else 0
        honest_in   = total_in_cap
        honest_sav  = sum(min(r["saved_tokens"] or 0, max(0, min(r["input_tokens"] or 0, CAP) - (r["output_tokens"] or 0))) for r in rows)
        honest_pct  = 100 * honest_sav / honest_in if honest_in else 0
        inflation   = claimed_in / honest_in if honest_in else 1.0
        n_over      = sum(1 for cmd, s in sorted_cmds if s["in_raw"] > CAP)

        print(box_top(f"9 · INFLATION ANALYSIS — headline vs honest (cap={fmt_k(CAP)})"))
        print(box_sep())
        print(row(f"  Headline (raw):  input={fmt_k(claimed_in)}  saved={fmt_k(claimed_sav)}  ({claimed_pct:.1f}%)"))
        print(row(f"  Honest (capped): input={fmt_k(honest_in)}  saved={fmt_k(honest_sav)}  ({honest_pct:.1f}%)"))
        print(row(f"  Inflation factor: {inflation:.2f}×  ({n_over} of {total_cmds} commands exceeded {fmt_k(CAP)} cap)"))
        print(row())
        verdict = "✔ clean — no inflation detected" if n_over == 0 else f"⚠ {n_over} command(s) exceeded cap — capped figure is the honest number"
        print(row(f"  Verdict: {verdict}"))
        print(row())
        # ── HONEST AUDIT REASONING ──────────────────────────────────────────
        print(row(f"  ── Honest audit reasoning ─────────────────────────────────────────────────"))
        print(row(f"  The headline % can be dominated by a single high-volume command (e.g. a"))
        print(row(f"  250K-token grep). §8 shows commands that exceeded {fmt_k(CAP)} cap."))
        print(row(f"  To see steady-state performance, run:"))
        print(row(f"    python ask-audit.py --sections 2 --cap 100000"))
        print(row(f"  Or use --by-version to compare across ATO releases."))
        print(box_bot())
        print()

    # §10 Version-epoch timeline (--by-version)
    if 10 in show_sections and args.by_version:
        # Check if version column exists
        cols = [r[1] for r in cur.execute("PRAGMA table_info(commands)").fetchall()]
        if "version" not in cols:
            print(box_top("10 · VERSION-EPOCH TIMELINE"))
            print(box_sep())
            print(row("  version column not present. Upgrade to ATO v0.4.1+ to enable this section."))
            print(row("  Existing rows will show version='' (blank = pre-v0.4.1)."))
            print(box_bot())
            print()
        else:
            ver_stats: dict = defaultdict(lambda: {"cmds":0,"in":0,"sav":0,"first":"","last":""})
            for r in rows_all:  # use ALL rows, not just the window
                v  = r["version"] or "pre-0.4.1"
                ts = (r["timestamp"] or "")[:10]
                s  = ver_stats[v]
                s["cmds"] += 1
                s["in"]   += r["input_tokens"] or 0
                s["sav"]  += r["saved_tokens"]  or 0
                if not s["first"] or ts < s["first"]: s["first"] = ts
                if not s["last"]  or ts > s["last"]:  s["last"]  = ts
            # Steady-state: remove single largest outlier per version
            print(box_top("10 · VERSION-EPOCH TIMELINE"))
            print(box_sep())
            print(row(f"  {'Version':<14} {'Cmds':>6}  {'Window':<22} {'Input':>8}  {'Saved':>8}  {'Rate':>6}  {'Steady-state':>12}"))
            print(row(f"  {'':<14} {'':<6}  {'':<22} {'':<8}  {'':<8}  {'':<6}  (excl top-1 outlier)"))
            print(box_sep())
            for ver in sorted(ver_stats):
                s    = ver_stats[ver]
                pct  = 100 * s["sav"] / s["in"] if s["in"] else 0
                window = f"{s['first']} → {s['last']}"
                # Steady-state: find largest single-command savings for this version
                ver_cmds = [r for r in rows_all if (r["version"] or "pre-0.4.1") == ver]
                if len(ver_cmds) > 1:
                    max_sav  = max(r["saved_tokens"] or 0 for r in ver_cmds)
                    clean_in = sum(r["input_tokens"] or 0 for r in ver_cmds if (r["saved_tokens"] or 0) < max_sav)
                    clean_sv = sum(r["saved_tokens"] or 0 for r in ver_cmds if (r["saved_tokens"] or 0) < max_sav)
                    ss_pct   = f"{100*clean_sv/clean_in:.1f}%" if clean_in else "n/a"
                else:
                    ss_pct = "n/a"
                print(row(f"  {ver:<14} {s['cmds']:>6}  {window:<22} {fmt_k(s['in']):>8}  {fmt_k(s['sav']):>8}  {pct:>5.1f}%  {ss_pct:>12}"))
            print(box_sep())
            print(row("  Steady-state = all commands minus the single highest-savings outlier per version."))
            print(row("  Use this figure when comparing releases — the headline can be skewed by one grep."))
            print(box_bot())
            print()

# ── JSON / CSV output ──────────────────────────────────────────────────────────
elif OUTPUT_FORMAT == "json":
    out = {
        "meta": {
            "window_days": WINDOW_DAYS,
            "cap":         CAP,
            "db":          db_path,
            "rows_total":  len(rows_all),
            "rows_window": total_cmds,
            "tenant_id":   args.tenant_id,
            "user_id":     args.user_id,
            "device_id":   args.device_id,
            "agent_id":    args.agent_id,
        },
        "scorecard": {
            "total_commands":  total_cmds,
            "input_raw":       total_in,
            "input_capped":    total_in_cap,
            "output":          total_out,
            "saved":           total_sav,
            "savings_pct":     round(overall_pct, 2),
            "exec_time_ms":    total_ms,
        },
        "by_command": [
            {
                "command":    cmd,
                "runs":       s["runs"],
                "input_raw":  s["in_raw"],
                "input_cap":  s["in_cap"],
                "output":     s["out"],
                "saved":      s["sav"],
                "savings_pct": round(100*s["sav"]/s["in_raw"],2) if s["in_raw"] else 0,
            }
            for cmd, s in sorted_cmds
        ],
    }
    print(json.dumps(out, indent=2))

elif OUTPUT_FORMAT == "csv":
    writer = csv.writer(sys.stdout)
    writer.writerow(["command","runs","input_raw","input_cap","output","saved","savings_pct"])
    for cmd, s in sorted_cmds:
        pct = round(100*s["sav"]/s["in_raw"],2) if s["in_raw"] else 0
        writer.writerow([cmd, s["runs"], s["in_raw"], s["in_cap"], s["out"], s["sav"], pct])

# ── RuVector push ──────────────────────────────────────────────────────────────
if args.push_ruvector and args.tenant_id:
    import urllib.request
    rv_url  = args.push_ruvector.rstrip("/")
    payload = json.dumps({
        "tenant_id":  args.tenant_id,
        "user_id":    args.user_id or "unknown",
        "device_id":  args.device_id or platform.node(),
        "agent_id":   args.agent_id or "unknown",
        "event":      "ato-audit",
        "saved_pct":  round(overall_pct, 2),
        "saved_tokens": total_sav,
        "total_commands": total_cmds,
        "window_days": WINDOW_DAYS,
    }).encode()
    req = urllib.request.Request(
        f"{rv_url}/v1/ingest",
        data=payload, method="POST",
        headers={"Content-Type":"application/json","x-tenant-id": args.tenant_id}
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        print("Audit event pushed to RuVector.", file=sys.stderr)
    except Exception as e:
        print(f"RuVector push failed: {e}", file=sys.stderr)
elif args.push_ruvector:
    print("--push-ruvector requires --tenant-id", file=sys.stderr)
