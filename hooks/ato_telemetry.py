#!/usr/bin/env python3
"""ato_telemetry.py — weekly telemetry flush hook (ships in the SDK).

Cheap + idempotent: safe to call on every `ask` run. Only sends once per 7 days.
Reads ~/.ask/license.json (email, tier) + history.db (savings, schema-introspected).
Keeps the Rust binary untouched — the binary just writes history.db as it already does.

Opt-out policy (THE DEAL):
  free tier        → savings + usage always on (the exchange for free use)
  commercial tier  → ASK_TELEMETRY_SAVINGS=off / ASK_TELEMETRY_USAGE=off honored
  any tier         → DO_NOT_TRACK=1 hard-stops everything

NEVER sends: command/prompt/file content, code, company/project/repo names, paths,
or any PII beyond the registered email. history.db stays local.
"""
import json, os, sqlite3, time, urllib.request

ASK_HOME     = os.environ.get("ASK_HOME", os.path.expanduser("~/.ask"))
LICENSE_JSON = os.path.join(ASK_HOME, "license.json")
HISTORY_DB   = os.environ.get("ASK_HISTORY_DB", os.path.join(ASK_HOME, "history.db"))
LAST_FILE    = os.path.join(ASK_HOME, ".telemetry_last")
REGISTER_URL = os.environ.get("ATO_REGISTER_URL", "https://api.ask-ai.ca/v1/ato")
WEEK_SECS    = 7 * 86400


def _off(name):  # env truthy-off
    return os.environ.get(name, "").lower() in ("1", "true", "on", "yes")


def _load_license():
    try:
        with open(LICENSE_JSON) as f:
            return json.load(f)
    except Exception:
        return {}


def _due():
    try:
        return (time.time() - os.path.getmtime(LAST_FILE)) >= WEEK_SECS
    except OSError:
        return True  # never sent


def _mark():
    open(LAST_FILE, "w").write(str(int(time.time())))


def _savings_from_history():
    """Introspect history.db; sum the most likely numeric 'saved' column over the last week.
    No schema assumption — find a table with a tokens/saved-ish integer column."""
    if not os.path.exists(HISTORY_DB):
        return {"tokens_saved": 0, "invocations": 0}
    try:
        c = sqlite3.connect(HISTORY_DB, timeout=5)
        tables = [r[0] for r in c.execute(
            "SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
        best = {"tokens_saved": 0, "invocations": 0}
        for t in tables:
            cols = [r[1].lower() for r in c.execute(f"PRAGMA table_info('{t}')").fetchall()]
            saved_col = next((r[1] for r in c.execute(f"PRAGMA table_info('{t}')").fetchall()
                              if r[1].lower() in
                              ("tokens_saved", "saved", "savings", "saved_tokens", "delta")), None)
            if not saved_col:
                continue
            try:
                total = c.execute(f"SELECT COALESCE(SUM({saved_col}),0), COUNT(*) FROM '{t}'").fetchone()
                if total and total[0] and total[0] > best["tokens_saved"]:
                    best = {"tokens_saved": int(total[0]), "invocations": int(total[1])}
            except Exception:
                continue
        c.close()
        return best
    except Exception:
        return {"tokens_saved": 0, "invocations": 0}


def main():
    if _off("DO_NOT_TRACK"):
        return
    if not _due():
        return
    lic = _load_license()
    email = (lic.get("email") or "").strip().lower()
    tier = lic.get("tier", "free")
    commercial = tier == "commercial"

    send_savings = not (commercial and _off("ASK_TELEMETRY_SAVINGS"))
    send_usage = not (commercial and _off("ASK_TELEMETRY_USAGE"))
    if not (send_savings or send_usage):
        _mark(); return

    s = _savings_from_history()
    if s["tokens_saved"] <= 0:
        _mark(); return

    week = time.strftime("%G-W%V", time.gmtime())
    os_name = (os.uname().sysname if hasattr(os, "uname") else os.environ.get("OS", "unknown"))
    token = lic.get("install_token", "")
    if not token:
        return  # not registered yet — telemetry is token-gated; nothing to send
    payload = {"install_token": token}
    if send_savings:
        payload["savings"] = {"tokens_saved": s["tokens_saved"], "ver": lic.get("ver", ""), "os": os_name}
    if send_usage and email:
        payload["usage"] = {"week": week, "invocations": s["invocations"],
                            "tokens_saved": s["tokens_saved"], "ver": lic.get("ver", ""), "os": os_name}

    try:
        req = urllib.request.Request(f"{REGISTER_URL}/telemetry",
                                     data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=8).read()
        _mark()
    except Exception:
        pass  # silent; retry next run after the 7-day window still elapsed (mark only on success)


if __name__ == "__main__":
    main()
