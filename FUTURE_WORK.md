# Future work

Open ideas and known gaps, roughly in order of how much they matter.

## Clean up the session files more reliably

Each Claude Code session has a file in `~/.local/state/claude-usage/sessions/`
(`%LOCALAPPDATA%\claude-usage\sessions` on Windows). Old files are removed: `prune()` deletes a
file 8 days after its last write (`KEEP_FILES_FOR`). The gaps:

- **Only `claude-usage report` prunes.** The widgets run it every 30 s, so with a widget running
  the folder stays small. Without one, and with no Claude session running `claude-usage`,
  files pile up, one per session and a few KB each. The status line and the `SessionEnd` hook
  never prune. Pruning from `session-end` would fix it cheaply: it runs once per session and
  isn't on the path of every response. If the status line pruned instead, it could do so at most
  once a day, with a marker file.
- **Files that can't be read are never removed.** `load_records()` skips a file that isn't valid
  JSON or has no `status`, and `prune()` only sees the files `load_records()` returned. Prune
  such files by their modification time instead.
- **Leftover temp files.** `write_json_atomic()` removes its `.tmp-*.json` when writing fails,
  but not when the process is killed between the write and the rename. Nothing removes those.
  Prune `.tmp-*` files older than a minute.
- **Settings backups.** Every `configure` / `unconfigure` that changes `~/.claude/settings.json`
  leaves a `settings.json.bak-<stamp>` beside it. Keep the last few.

Tests: each case with a temp state dir, like the existing `test_listing_and_pruning`.

## Session states

- **"Turn over, only background work left" reads as working.** `claude agents --json` reports a
  session with a background shell, a monitor or a subagent still running as `busy`. Two
  `async: true` hooks, `UserPromptSubmit` and `Stop` / `StopFailure`, could record when each
  turn starts and ends in the session file. "Busy, with no turn open" would then mean
  background work only. A turn that starts without a prompt (a finished background task, a
  monitor event, a `/loop` wake-up) would show as background work until it ends.
- **Counting shells** (Linux only, relies on internals). Bash-tool and Monitor shells are child
  processes of the session's `pid`, with command lines that source Claude Code's shell
  snapshot. They could be counted and named per session.
- **Checked only on a background session:** that a lone background shell keeps a session
  `busy`. Check an interactive session too.
- **The Windows tray** doesn't show the states yet. A session closed without `SessionEnd` shows
  there as `ended` without a time.

## Before publishing

- A screenshot of the panel.
- A name that doesn't read as an official Anthropic product.
- Run the tray on real Windows (so far only `-Print` in PowerShell 7 on Linux).
- Check in a real panel: the dot, the settings dialog, and whether the popup keeps to its
  content height (`Layout.maximumHeight`; plasmawindowed ignores it).

## Other

- `configure` refuses a status line that's already set. It could chain it instead: run the
  existing command and print its output.
