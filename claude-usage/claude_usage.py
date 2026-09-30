#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
"""Claude Code plan limits and session context, for a terminal, a widget or another session.

Claude Code hands its status line command a JSON snapshot of the session on stdin: the context
window and, for claude.ai Pro/Max logins, the 5-hour and 7-day plan limits. It is the only
documented place those limits appear, and it runs locally without spending tokens. This script
is that status line command: it keeps the newest snapshot of every session on disk, and reports
all of them at once: as text for a terminal or a Claude session, as JSON for a desktop widget
(https://github.com/pe7ro/claude-usage-widget has one for KDE Plasma and one for Windows).

  claude_usage.py statusline [--print]  status line command: stdin JSON -> session file
  claude_usage.py session-end           SessionEnd hook: mark the session ended
  claude_usage.py report [--json]       plan limits + every recent session (the default)
  claude_usage.py configure             add the two commands above to ~/.claude/settings.json
  claude_usage.py unconfigure           remove them again

Standard library only, Python 3.10+, Linux, macOS and Windows. Files live in
$XDG_STATE_HOME/claude-usage/sessions/<session_id>.json, on Windows in
%LOCALAPPDATA%\\claude-usage\\sessions (override with CLAUDE_USAGE_STATE_DIR).
"""

import argparse
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import time
from pathlib import Path

RECORD_VERSION = 1

# A session with no API response for this long is shown as idle rather than active.
IDLE_AFTER = 30 * 60
# Sessions listed in the report: ended ones for a while, others while they have been used lately.
LIST_ENDED_FOR = 6 * 3600
LIST_IDLE_FOR = 24 * 3600
# Files are kept longer than they are listed: an old session's reading of the 7-day window is
# still the newest reading there is when nothing ran for days.
KEEP_FILES_FOR = 8 * 86400
# Two readings belong to the same limit window when their resets_at differ by less than this.
SAME_WINDOW = 10 * 60
# Readings of one window taken this close together are compared by value, not by time: parallel
# sessions report in the order their responses end, which need not be the order of the numbers.
CONCURRENT = 5 * 60

LIMIT_WINDOWS = ("five_hour", "seven_day", "spend_limit")

SESSION_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")

ON_WINDOWS = sys.platform == "win32"


# --- files -------------------------------------------------------------------------------------

def state_dir() -> Path:
    override = os.environ.get("CLAUDE_USAGE_STATE_DIR")
    if override:
        return Path(override)
    if ON_WINDOWS:
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~/AppData/Local")
    else:
        base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "claude-usage"


def sessions_dir() -> Path:
    return state_dir() / "sessions"


def session_path(session_id: str) -> Path:
    return sessions_dir() / f"{session_id}.json"


def safe_session_id(value) -> str | None:
    """The session id becomes a file name, so anything but a plain token is refused."""
    if isinstance(value, str) and SESSION_ID.fullmatch(value):
        return value
    return None


def read_json(path: Path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def write_json_atomic(path: Path, obj, indent=None, mode=None) -> None:
    """Readers never see a half-written file: write a temp file beside it, then rename.

    The file is 0600 unless `mode` says otherwise (settings.json keeps the mode it had).
    """
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".json")
    try:
        if mode is not None and hasattr(os, "fchmod"):  # Windows has it only from Python 3.13
            os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=indent, ensure_ascii=False)
            if indent is not None:
                f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_records() -> dict[str, dict]:
    records = {}
    try:
        paths = list(sessions_dir().glob("*.json"))
    except OSError:
        return records
    for path in paths:
        if path.name.startswith("."):
            continue
        rec = read_json(path)
        if isinstance(rec, dict) and isinstance(rec.get("status"), dict):
            records[path.stem] = rec
    return records


# --- values ------------------------------------------------------------------------------------

def num(value) -> float | None:
    """A JSON number, or None. The status line's numbers can be null early in a session."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def as_dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def response_fingerprint(status: dict) -> list:
    """Changes when the snapshot reflects a new API response.

    The status line also re-runs without one (a prompt cache expiring, a limit window resetting),
    so the time a file was written is not the time its numbers were measured.
    """
    cost = as_dict(status.get("cost"))
    ctx = as_dict(status.get("context_window"))
    return [
        cost.get("total_api_duration_ms"),
        ctx.get("total_input_tokens"),
        ctx.get("total_output_tokens"),
        status.get("prompt_id"),
    ]


def transcript_mtime(status: dict) -> float | None:
    """When the session last wrote its transcript. Only the file's time is read, never its
    contents: the transcript format is internal to Claude Code."""
    path = status.get("transcript_path")
    if not isinstance(path, str) or not path:
        return None
    try:
        return os.stat(path).st_mtime
    except OSError:
        return None


def context_view(ctx: dict) -> dict:
    size = num(ctx.get("context_window_size"))
    used = num(ctx.get("used_percentage"))
    remaining = num(ctx.get("remaining_percentage"))
    if used is None and remaining is not None:
        used = 100.0 - remaining
    if used is None and size:
        usage = as_dict(ctx.get("current_usage"))
        parts = [num(usage.get(k)) for k in
                 ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")]
        if any(p is not None for p in parts):
            used = sum(p or 0.0 for p in parts) / size * 100.0
    if remaining is None and used is not None:
        remaining = 100.0 - used
    return {
        "size": size,
        "used_percentage": used,
        "remaining_percentage": remaining,
        "free_tokens": size * remaining / 100.0 if size and remaining is not None else None,
    }


# --- writing -----------------------------------------------------------------------------------

def record_status(status: dict, now: float) -> Path | None:
    """Store one status line snapshot as the newest state of its session."""
    session_id = safe_session_id(status.get("session_id"))
    if session_id is None:
        return None
    path = session_path(session_id)
    old = read_json(path)
    old = old if isinstance(old, dict) else {}

    fingerprint = response_fingerprint(status)
    response_at = old.get("response_at")
    if not isinstance(response_at, (int, float)):
        # First sight of a session that may have been idle for hours (every open session runs
        # its status line when the command is first configured): its transcript knows better.
        response_at = min(now, transcript_mtime(status) or now)
    elif old.get("fingerprint") != fingerprint:
        response_at = now

    # Claude Code drops a window from the JSON once its resets_at passes. The last reading of it
    # is kept, so the widget can say "reset at 16:40" instead of "no data".
    limits = {name: w for name, w in as_dict(old.get("limits")).items()
              if isinstance(w, dict) and (num(w.get("resets_at")) or now) > now - KEEP_FILES_FOR}
    for name, window in as_dict(status.get("rate_limits")).items():
        window = as_dict(window)
        used = num(window.get("used_percentage"))
        if used is not None:
            limits[name] = {
                "used_percentage": used,
                "resets_at": num(window.get("resets_at")),
                "seen_at": response_at,
            }

    write_json_atomic(path, {
        "version": RECORD_VERSION,
        "written_at": now,
        "response_at": response_at,
        "fingerprint": fingerprint,
        "limits": limits,
        "status": status,
    })
    return path


def mark_ended(hook: dict, now: float) -> Path | None:
    session_id = safe_session_id(hook.get("session_id"))
    if session_id is None:
        return None
    path = session_path(session_id)
    rec = read_json(path)
    if not isinstance(rec, dict):
        return None  # no status line ever ran for it, so there is nothing to show as ended
    rec["ended_at"] = now
    rec["end_reason"] = hook.get("reason")
    write_json_atomic(path, rec)
    return path


# --- reading -----------------------------------------------------------------------------------

def best_limit(name: str, records: dict[str, dict], now: float) -> dict | None:
    """The current reading of one limit window across all sessions.

    Every session sees the same account-wide limit, each as of its own last response. The newest
    window is the one with the latest resets_at. Within one window usage normally only goes up,
    but a usage reset brings it back down and keeps resets_at, so the newest reading wins; of
    readings taken within CONCURRENT of it, the highest.
    """
    readings = []
    for session_id, rec in records.items():
        window = as_dict(as_dict(rec.get("limits")).get(name))
        used = num(window.get("used_percentage"))
        if used is not None:
            readings.append((session_id, used, num(window.get("resets_at")),
                             num(window.get("seen_at")) or 0.0))
    if not readings:
        return None
    newest_reset = max(r[2] or 0.0 for r in readings)
    same_window = [r for r in readings if (r[2] or 0.0) >= newest_reset - SAME_WINDOW]
    newest_seen = max(r[3] for r in same_window)
    recent = [r for r in same_window if r[3] >= newest_seen - CONCURRENT]
    session_id, used, resets_at, seen_at = max(recent, key=lambda r: (r[1], r[3]))
    return {
        "used_percentage": used,
        "resets_at": resets_at,
        "as_of": seen_at,
        "expired": resets_at is not None and resets_at <= now,
        "session_id": session_id,
    }


def display_path(path: str) -> str:
    home = os.path.expanduser("~")
    if path == home or path.startswith(home + os.sep):
        return "~" + path[len(home):]
    return path


def session_view(session_id: str, rec: dict, now: float) -> dict:
    status = rec["status"]
    workspace = as_dict(status.get("workspace"))
    model = as_dict(status.get("model"))
    project_dir = workspace.get("project_dir") or status.get("cwd") or ""
    cwd = workspace.get("current_dir") or status.get("cwd") or project_dir
    last = num(rec.get("response_at")) or num(rec.get("written_at")) or 0.0
    ended_at = num(rec.get("ended_at"))
    if ended_at is not None:
        state = "ended"
    elif now - last > IDLE_AFTER:
        state = "idle"
    else:
        state = "active"
    return {
        "session_id": session_id,
        "title": status.get("session_name") or (Path(project_dir).name if project_dir else session_id[:8]),
        "project_dir": project_dir,
        "cwd": cwd,
        "cwd_display": display_path(cwd),
        "model": model.get("display_name") or model.get("id"),
        "model_short": re.sub(r"\s*\(.*\)$", "", model.get("display_name") or model.get("id") or ""),
        "context": context_view(as_dict(status.get("context_window"))),
        "cost_usd": num(as_dict(status.get("cost")).get("total_cost_usd")),
        "last_response_at": last,
        "ended_at": ended_at,
        "end_reason": rec.get("end_reason"),
        "state": state,
        "claude_version": status.get("version"),
    }


def prune(records: dict[str, dict], now: float) -> None:
    for session_id, rec in list(records.items()):
        written = num(rec.get("written_at")) or 0.0
        if now - written > KEEP_FILES_FOR:
            try:
                session_path(session_id).unlink()
            except OSError:
                pass
            del records[session_id]


def build_report(now: float | None = None) -> dict:
    now = time.time() if now is None else now
    records = load_records()
    prune(records, now)

    sessions = []
    for session_id, rec in records.items():
        view = session_view(session_id, rec, now)
        if view["state"] == "ended":
            if now - view["ended_at"] > LIST_ENDED_FOR:
                continue
        elif now - view["last_response_at"] > LIST_IDLE_FOR:
            continue
        sessions.append(view)
    order = {"active": 0, "idle": 1, "ended": 2}
    sessions.sort(key=lambda s: (order[s["state"]], -s["last_response_at"]))

    return {
        "version": RECORD_VERSION,
        "generated_at": now,
        "limits": {name: best_limit(name, records, now) for name in LIMIT_WINDOWS},
        "sessions": sessions,
    }


# --- text --------------------------------------------------------------------------------------

def fmt_tokens(n: float | None) -> str:
    if n is None:
        return "?"
    if n >= 1_000_000:
        m = n / 1_000_000
        return f"{m:.0f}M" if m >= 10 or abs(m - round(m)) < 0.05 else f"{m:.1f}M"
    if n >= 1000:
        return f"{n / 1000:.0f}k"
    return f"{n:.0f}"


def fmt_duration(seconds: float) -> str:
    s = max(0, int(seconds))
    d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m"
    return "<1m"


def fmt_when(ts: float | None, now: float) -> str:
    if ts is None:
        return "?"
    t = time.localtime(ts)
    if time.strftime("%Y-%m-%d", t) == time.strftime("%Y-%m-%d", time.localtime(now)):
        return time.strftime("%H:%M", t)
    return time.strftime("%a %H:%M", t)


def limit_text(limit: dict | None, now: float) -> str:
    if limit is None:
        return "no reading yet"
    if limit["expired"]:
        return f"reset at {fmt_when(limit['resets_at'], now)}, no reading since"
    text = f"{limit['used_percentage']:.0f}%"
    if limit["resets_at"] is not None:
        text += (f"  resets {fmt_when(limit['resets_at'], now)}"
                 f" (in {fmt_duration(limit['resets_at'] - now)})")
    return text + f"  as of {fmt_when(limit['as_of'], now)}"


def report_text(report: dict) -> str:
    now = report["generated_at"]
    limits = report["limits"]
    lines = [f"5-hour   {limit_text(limits['five_hour'], now)}",
             f"7-day    {limit_text(limits['seven_day'], now)}"]
    if limits.get("spend_limit"):
        lines.append(f"spend    {limit_text(limits['spend_limit'], now)}")
    lines.append("")
    if not report["sessions"]:
        lines.append("no Claude Code session seen in the last 24 hours")
    for s in report["sessions"]:
        ctx = s["context"]
        if ctx["free_tokens"] is not None:
            context = (f"{fmt_tokens(ctx['free_tokens'])} free of {fmt_tokens(ctx['size'])}"
                       f" ({ctx['remaining_percentage']:.0f}%)")
        else:
            context = "context not measured yet"
        when = s["ended_at"] if s["state"] == "ended" else s["last_response_at"]
        title = s["title"] if len(s["title"]) <= 28 else s["title"][:27] + "…"
        lines.append(f"{title:<28} {s['model_short'] or '?':<10} {context:<26}"
                     f" {s['state']} {fmt_duration(now - when)} ago   {s['cwd_display']}")
    return "\n".join(lines)


def status_line_text(status: dict, now: float) -> str:
    parts = []
    ctx = context_view(as_dict(status.get("context_window")))
    if ctx["free_tokens"] is not None:
        parts.append(f"ctx {fmt_tokens(ctx['free_tokens'])} free ({ctx['remaining_percentage']:.0f}%)")
    limits = as_dict(status.get("rate_limits"))
    five = as_dict(limits.get("five_hour"))
    if num(five.get("used_percentage")) is not None:
        text = f"5h {num(five['used_percentage']):.0f}%"
        if num(five.get("resets_at")) is not None:
            text += f" → {fmt_when(num(five['resets_at']), now)}"
        parts.append(text)
    seven = as_dict(limits.get("seven_day"))
    if num(seven.get("used_percentage")) is not None:
        parts.append(f"7d {num(seven['used_percentage']):.0f}%")
    return " · ".join(parts)


# --- Claude Code settings ----------------------------------------------------------------------

def claude_settings_path() -> Path:
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return Path(base) / "settings.json"


def default_command() -> str:
    """What settings.json should run: the ~/.local/bin/claude-usage install.sh makes, if it's there.

    On Windows Claude Code runs the command through Git Bash, or PowerShell where Git Bash is
    missing. A backslash is an escape in the one and a quoted first word is not a command in the
    other, so the launcher stays bare and only the path is quoted, with forward slashes.
    """
    if ON_WINDOWS:
        launcher = "py" if shutil.which("py") else "python"
        return f'{launcher} "{Path(__file__).resolve().as_posix()}"'
    installed = Path.home() / ".local" / "bin" / "claude-usage"
    return str(installed) if installed.exists() else f"python3 {Path(__file__).resolve()}"


def is_ours(command, subcommand: str) -> bool:
    return isinstance(command, str) and re.search(
        rf"claude[-_]usage(\.py)?['\"]?\s+{subcommand}\b", command) is not None


def _backup(path: Path) -> Path | None:
    if not path.exists():
        return None
    backup = path.with_name(f"{path.name}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.copy2(path, backup)
    return backup


def _mode(path: Path) -> int:
    try:
        return stat.S_IMODE(path.stat().st_mode)
    except OSError:
        return 0o644


def _load_settings(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} does not hold a JSON object")
    return data


def configure(command: str | None = None) -> int:
    path = claude_settings_path()
    command = command or default_command()
    data = _load_settings(path)
    before = json.dumps(data, sort_keys=True)

    current = data.get("statusLine")
    if current and not is_ours(as_dict(current).get("command"), "statusline"):
        print(f"{path} already has a statusLine that isn't ours, leaving it alone:\n"
              f"  {json.dumps(current)}\n"
              f"Remove it (or chain it) and run configure again.", file=sys.stderr)
        return 1
    data["statusLine"] = {"type": "command", "command": f"{command} statusline"}

    hooks = data.setdefault("hooks", {})
    groups = hooks.setdefault("SessionEnd", [])
    groups[:] = [g for g in groups if not any(
        is_ours(as_dict(h).get("command"), "session-end") for h in as_dict(g).get("hooks", []))]
    groups.append({"matcher": "", "hooks": [{"type": "command", "command": f"{command} session-end"}]})

    if json.dumps(data, sort_keys=True) == before:
        print(f"{path} already configured")
        return 0
    backup = _backup(path)
    write_json_atomic(path, data, indent=2, mode=_mode(path))
    print(f"configured {path}" + (f" (backup: {backup.name})" if backup else ""))
    return 0


def unconfigure() -> int:
    path = claude_settings_path()
    data = _load_settings(path)
    changed = False
    if is_ours(as_dict(data.get("statusLine")).get("command"), "statusline"):
        del data["statusLine"]
        changed = True
    hooks = as_dict(data.get("hooks"))
    groups = hooks.get("SessionEnd")
    if isinstance(groups, list):
        kept = [g for g in groups if not any(
            is_ours(as_dict(h).get("command"), "session-end") for h in as_dict(g).get("hooks", []))]
        if len(kept) != len(groups):
            changed = True
            if kept:
                hooks["SessionEnd"] = kept
            else:
                del hooks["SessionEnd"]
                if not hooks:
                    del data["hooks"]
    if not changed:
        print(f"nothing of ours in {path}")
        return 0
    backup = _backup(path)
    write_json_atomic(path, data, indent=2, mode=_mode(path))
    print(f"removed from {path} (backup: {backup.name})")
    return 0


# --- entry points ------------------------------------------------------------------------------

def read_stdin_json():
    # Claude Code sends UTF-8. As bytes, json decodes it whatever the locale's encoding is
    # (on Windows often cp1252).
    return json.load(sys.stdin.buffer)


def cmd_statusline(args) -> int:
    # Runs inside Claude Code after every response: it must never fail or print an error there.
    try:
        status = read_stdin_json()
        if isinstance(status, dict):
            now = time.time()
            record_status(status, now)
            if args.print:
                print(status_line_text(status, now))
    except Exception:
        pass
    return 0


def cmd_session_end(args) -> int:
    try:
        hook = read_stdin_json()
        if isinstance(hook, dict):
            mark_ended(hook, time.time())
    except Exception:
        pass
    return 0


def cmd_report(args) -> int:
    report = build_report()
    if args.json:
        json.dump(report, sys.stdout)  # ASCII: readable whatever encoding the reader assumes
        sys.stdout.write("\n")
    else:
        print(report_text(report))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="claude-usage", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd")
    p = sub.add_parser("statusline", help="Claude Code status line command (reads JSON on stdin)")
    p.add_argument("--print", action="store_true", help="also print a status line in the terminal")
    p.set_defaults(func=cmd_statusline)
    sub.add_parser("session-end", help="Claude Code SessionEnd hook").set_defaults(func=cmd_session_end)
    p = sub.add_parser("report", help="plan limits and recent sessions")
    p.add_argument("--json", action="store_true", help="machine-readable, for widgets and scripts")
    p.set_defaults(func=cmd_report)
    p = sub.add_parser("configure", help="add the status line and hook to Claude Code settings")
    p.add_argument("--command", help="how settings.json should invoke this script")
    p.set_defaults(func=lambda a: configure(a.command))
    sub.add_parser("unconfigure", help="remove them again").set_defaults(func=lambda a: unconfigure())

    # A pipe on Windows gets the locale's encoding, which has no "→" or "…".
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    args = parser.parse_args(argv)
    if args.cmd is None:
        args = parser.parse_args(["report"])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
