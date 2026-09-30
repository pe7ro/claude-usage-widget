# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
"""Tests for claude-usage/claude_usage.py.

    python3 -m unittest discover -s tests

Every test runs against a temporary state dir and a temporary Claude config dir, so nothing
here touches the real ~/.local/state or ~/.claude.
"""

import copy
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True  # no __pycache__ beside the script in the repo

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "claude-usage" / "claude_usage.py"

spec = importlib.util.spec_from_file_location("claude_usage", SCRIPT)
cu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cu)

FULL = json.loads((HERE / "fixtures" / "full.json").read_text())
EARLY = json.loads((HERE / "fixtures" / "early.json").read_text())
FIVE_RESET = FULL["rate_limits"]["five_hour"]["resets_at"]
NOW = FIVE_RESET - (2 * 3600 + 13 * 60)  # 2h 13m before the 5-hour window resets


def status(base=FULL, **changes):
    s = copy.deepcopy(base)
    for key, value in changes.items():
        s[key] = value
    return s


def with_limits(s, five=None, seven=None):
    s = copy.deepcopy(s)
    s["rate_limits"] = {}
    if five:
        s["rate_limits"]["five_hour"] = {"used_percentage": five[0], "resets_at": five[1]}
    if seven:
        s["rate_limits"]["seven_day"] = {"used_percentage": seven[0], "resets_at": seven[1]}
    return s


def run_main(argv, stdin_text, stdin_encoding="utf-8"):
    """Claude Code writes UTF-8; `stdin_encoding` is what Python's text layer assumes."""
    out, err = io.StringIO(), io.StringIO()
    stdin = io.TextIOWrapper(io.BytesIO(stdin_text.encode("utf-8")), encoding=stdin_encoding)
    with mock.patch("sys.stdin", stdin), redirect_stdout(out), redirect_stderr(err):
        code = cu.main(argv)
    return code, out.getvalue(), err.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {
            "CLAUDE_USAGE_STATE_DIR": str(root / "state"),
            "CLAUDE_CONFIG_DIR": str(root / "claude"),
        })
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()


class Writing(Base):
    def test_snapshot_is_stored_privately(self):
        path = cu.record_status(FULL, NOW)
        self.assertEqual(path.name, FULL["session_id"] + ".json")
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        rec = json.loads(path.read_text())
        self.assertEqual(rec["status"], FULL)
        self.assertEqual(rec["response_at"], NOW)
        self.assertEqual(rec["limits"]["five_hour"],
                         {"used_percentage": 34.4, "resets_at": FIVE_RESET, "seen_at": NOW})

    def test_statusline_prints_nothing_by_default(self):
        code, out, err = run_main(["statusline"], json.dumps(FULL))
        self.assertEqual((code, out, err), (0, "", ""))
        self.assertTrue(cu.session_path(FULL["session_id"]).exists())

    def test_statusline_print(self):
        code, out, _ = run_main(["statusline", "--print"], json.dumps(FULL))
        self.assertEqual(code, 0)
        self.assertRegex(out.strip(), r"^ctx 810k free \(81%\) · 5h 34% → (\w{3} )?\d\d:\d\d · 7d 12%$")

    def test_non_ascii_is_read_as_utf8_and_reported_as_ascii(self):
        run_main(["statusline"], json.dumps(status(session_name="Überblick → 2"), ensure_ascii=False),
                 stdin_encoding="cp1252")  # a Windows locale
        rec = json.loads(cu.session_path(FULL["session_id"]).read_text(encoding="utf-8"))
        self.assertEqual(rec["status"]["session_name"], "Überblick → 2")
        cu.record_status(status(session_name="Überblick → 2"), cu.time.time())
        _, out, _ = run_main(["report", "--json"], "")
        self.assertTrue(out.isascii())
        self.assertEqual(json.loads(out)["sessions"][0]["title"], "Überblick → 2")

    def test_garbage_input_is_silent(self):
        for text in ("", "not json", "[1, 2]", '{"session_id": "../../etc/passwd"}'):
            self.assertEqual(run_main(["statusline"], text), (0, "", ""))
            self.assertEqual(run_main(["session-end"], text), (0, "", ""))
        self.assertEqual(cu.load_records(), {})

    def test_rerun_without_new_response_keeps_measurement_time(self):
        cu.record_status(FULL, NOW)
        cu.record_status(FULL, NOW + 600)  # e.g. the prompt cache expired, nothing new was asked
        rec = json.loads(cu.session_path(FULL["session_id"]).read_text())
        self.assertEqual(rec["written_at"], NOW + 600)
        self.assertEqual(rec["response_at"], NOW)
        self.assertEqual(rec["limits"]["five_hour"]["seen_at"], NOW)

        newer = status(cost={**FULL["cost"], "total_api_duration_ms": 25000})
        cu.record_status(newer, NOW + 900)
        rec = json.loads(cu.session_path(FULL["session_id"]).read_text())
        self.assertEqual(rec["response_at"], NOW + 900)

    def test_dropped_window_is_kept_and_reported_as_reset(self):
        cu.record_status(FULL, NOW)
        after = NOW + 3 * 3600  # past five_hour.resets_at; Claude Code dropped the window
        dropped = status(rate_limits={"seven_day": FULL["rate_limits"]["seven_day"]})
        cu.record_status(dropped, after)
        five = cu.build_report(after)["limits"]["five_hour"]
        self.assertTrue(five["expired"])
        self.assertEqual(five["resets_at"], FIVE_RESET)

    def test_first_sight_takes_the_transcript_time(self):
        transcript = Path(self.tmp.name) / "t.jsonl"
        transcript.write_text("{}\n")
        os.utime(transcript, (NOW - 3600, NOW - 3600))
        cu.record_status(status(transcript_path=str(transcript)), NOW)
        (s,) = cu.build_report(NOW)["sessions"]
        self.assertEqual(s["last_response_at"], NOW - 3600)
        self.assertEqual(s["state"], "idle")
        cu.record_status(status(transcript_path=str(transcript), prompt_id="next"), NOW + 5)
        self.assertEqual(cu.build_report(NOW + 5)["sessions"][0]["state"], "active")

    def test_early_session_without_numbers(self):
        cu.record_status(EARLY, NOW)
        report = cu.build_report(NOW)
        self.assertEqual(report["limits"], {"five_hour": None, "seven_day": None, "spend_limit": None})
        (s,) = report["sessions"]
        self.assertEqual(s["context"]["free_tokens"], None)
        self.assertEqual(s["title"], "other")
        self.assertIn("context not measured yet", cu.report_text(report))


class Reading(Base):
    def test_session_view(self):
        cu.record_status(FULL, NOW)
        (s,) = cu.build_report(NOW + 60)["sessions"]
        self.assertEqual(s["title"], "example-app")
        self.assertEqual(s["model"], "Opus")
        self.assertEqual(s["state"], "active")
        self.assertEqual(cu.session_view("x", {"status": status(model={"display_name": "Opus 5.5 (1M context)"})},
                                         NOW)["model_short"], "Opus 5.5")
        self.assertEqual(s["context"]["size"], 1_000_000)
        self.assertEqual(s["context"]["free_tokens"], 810_000)
        self.assertEqual(s["cost_usd"], 1.2345)

    def test_session_name_wins_over_folder(self):
        cu.record_status(status(session_name="widget work"), NOW)
        self.assertEqual(cu.build_report(NOW)["sessions"][0]["title"], "widget work")

    def test_context_from_current_usage_when_percentages_missing(self):
        ctx = dict(FULL["context_window"], used_percentage=None, remaining_percentage=None)
        view = cu.context_view(ctx)
        self.assertAlmostEqual(view["used_percentage"], 18.8)
        self.assertAlmostEqual(view["free_tokens"], 812_000)

    def test_highest_concurrent_reading_of_the_newest_window_wins(self):
        a = with_limits(status(session_id="a"), five=(30.0, FIVE_RESET), seven=(10.0, 1790300000))
        b = with_limits(status(session_id="b"), five=(34.4, FIVE_RESET + 5), seven=(12.0, 1790300000))
        old = with_limits(status(session_id="old"), five=(95.0, FIVE_RESET - 5 * 3600))
        cu.record_status(b, NOW - 120)
        cu.record_status(a, NOW)  # written last, but its reading is lower: it is older
        cu.record_status(old, NOW)  # previous window, however high
        limits = cu.build_report(NOW)["limits"]
        self.assertEqual(limits["five_hour"]["used_percentage"], 34.4)
        self.assertEqual(limits["five_hour"]["session_id"], "b")
        self.assertEqual(limits["five_hour"]["as_of"], NOW - 120)
        self.assertFalse(limits["five_hour"]["expired"])
        self.assertEqual(limits["seven_day"]["used_percentage"], 12.0)

    def test_usage_reset_lowers_the_reading_within_a_window(self):
        seven_reset = NOW + 40 * 3600  # a usage reset keeps the window's resets_at
        before = with_limits(status(session_id="before"), seven=(91.0, seven_reset))
        after = with_limits(status(session_id="after"), seven=(14.0, seven_reset))
        cu.record_status(before, NOW - 2 * 3600)
        cu.record_status(after, NOW)
        seven = cu.build_report(NOW)["limits"]["seven_day"]
        self.assertEqual(seven["used_percentage"], 14.0)
        self.assertEqual(seven["session_id"], "after")
        self.assertEqual(seven["as_of"], NOW)

    def test_idle_and_ended(self):
        cu.record_status(FULL, NOW)
        cu.record_status(EARLY, NOW)
        cu.mark_ended({"session_id": EARLY["session_id"], "reason": "prompt_input_exit"}, NOW + 60)
        later = NOW + cu.IDLE_AFTER + 60
        sessions = {s["session_id"]: s for s in cu.build_report(later)["sessions"]}
        self.assertEqual(sessions[FULL["session_id"]]["state"], "idle")
        self.assertEqual(sessions[EARLY["session_id"]]["state"], "ended")
        self.assertEqual(sessions[EARLY["session_id"]]["end_reason"], "prompt_input_exit")
        self.assertNotIn(EARLY["session_id"],
                         [s["session_id"] for s in cu.build_report(NOW + cu.LIST_ENDED_FOR + 120)["sessions"]])

    def test_session_end_cli_marks_the_file(self):
        cu.record_status(FULL, NOW)
        code, out, _ = run_main(["session-end"], json.dumps({"session_id": FULL["session_id"], "reason": "clear"}))
        self.assertEqual((code, out), (0, ""))
        rec = json.loads(cu.session_path(FULL["session_id"]).read_text())
        self.assertEqual(rec["end_reason"], "clear")

    def test_listing_and_pruning(self):
        cu.record_status(FULL, NOW)
        self.assertEqual(len(cu.build_report(NOW + cu.LIST_IDLE_FOR - 60)["sessions"]), 1)
        report = cu.build_report(NOW + cu.LIST_IDLE_FOR + 60)
        self.assertEqual(report["sessions"], [])
        self.assertIsNotNone(report["limits"]["seven_day"])  # still the newest reading there is
        cu.build_report(NOW + cu.KEEP_FILES_FOR + 60)
        self.assertFalse(cu.session_path(FULL["session_id"]).exists())

    def test_report_json_cli(self):
        cu.record_status(FULL, cu.time.time())  # the CLI reports at the real clock
        code, out, _ = run_main(["report", "--json"], "")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["sessions"][0]["model"], "Opus")


class Settings(Base):
    def settings(self):
        return json.loads(cu.claude_settings_path().read_text())

    def write_settings(self, data):
        path = cu.claude_settings_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))

    def test_configure_keeps_everything_else_and_is_idempotent(self):
        self.write_settings({"model": "opus[1m]", "hooks": {"SessionEnd": [
            {"matcher": "", "hooks": [{"type": "command", "command": "other-tool end"}]}]}})
        with redirect_stdout(io.StringIO()):
            self.assertEqual(cu.configure("/x/claude-usage"), 0)
            self.assertEqual(cu.configure("/x/claude-usage"), 0)
        data = self.settings()
        self.assertEqual(data["model"], "opus[1m]")
        self.assertEqual(data["statusLine"], {"type": "command", "command": "/x/claude-usage statusline"})
        commands = [h["command"] for g in data["hooks"]["SessionEnd"] for h in g["hooks"]]
        self.assertEqual(commands, ["other-tool end", "/x/claude-usage session-end"])
        backups = list(cu.claude_settings_path().parent.glob("settings.json.bak-*"))
        self.assertEqual(len(backups), 1)  # the second run changed nothing, so wrote nothing

    def test_settings_keep_their_file_mode(self):
        self.write_settings({"model": "opus[1m]"})
        cu.claude_settings_path().chmod(0o644)
        with redirect_stdout(io.StringIO()):
            cu.configure("/x/claude-usage")
        self.assertEqual(stat.S_IMODE(cu.claude_settings_path().stat().st_mode), 0o644)

    def test_settings_write_without_fchmod(self):  # Windows before Python 3.13
        self.write_settings({"model": "opus[1m]"})
        fchmod = os.fchmod
        del os.fchmod
        try:
            with redirect_stdout(io.StringIO()):
                self.assertEqual(cu.configure("/x/claude-usage"), 0)
        finally:
            os.fchmod = fchmod
        self.assertEqual(self.settings()["statusLine"]["command"], "/x/claude-usage statusline")

    def test_foreign_status_line_is_left_alone(self):
        self.write_settings({"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}})
        with redirect_stderr(io.StringIO()):
            self.assertEqual(cu.configure("/x/claude-usage"), 1)
        self.assertEqual(self.settings()["statusLine"]["command"], "~/.claude/statusline.sh")

    def test_unconfigure_removes_only_ours(self):
        self.write_settings({"model": "opus[1m]"})
        with redirect_stdout(io.StringIO()):
            cu.configure("python3 /x/claude_usage.py")
            cu.unconfigure()
        self.assertEqual(self.settings(), {"model": "opus[1m]"})


class Windows(Base):
    def setUp(self):
        super().setUp()
        self.windows = mock.patch.object(cu, "ON_WINDOWS", True)
        self.windows.start()

    def tearDown(self):
        self.windows.stop()
        super().tearDown()

    def test_state_dir_is_under_local_app_data(self):
        with mock.patch.dict(os.environ, {"LOCALAPPDATA": "/c/Users/me/AppData/Local"}):
            del os.environ["CLAUDE_USAGE_STATE_DIR"]
            self.assertEqual(cu.state_dir(), Path("/c/Users/me/AppData/Local/claude-usage"))

    def test_command_works_in_git_bash_and_powershell(self):
        for which, launcher in (("C:/Windows/py.exe", "py"), (None, "python")):
            with mock.patch.object(cu.shutil, "which", return_value=which):
                command = cu.default_command()
            self.assertEqual(command, f'{launcher} "{SCRIPT.as_posix()}"')
            self.assertNotIn("\\", command)
            self.assertTrue(cu.is_ours(f"{command} statusline", "statusline"))
            self.assertTrue(cu.is_ours(f"{command} session-end", "session-end"))


if __name__ == "__main__":
    unittest.main()
