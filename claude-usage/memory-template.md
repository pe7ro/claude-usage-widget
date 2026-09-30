---
name: plan-usage-limits
description: "Check the plan's 5-hour and weekly usage with `claude-usage` at the start, at milestones and before heavy steps, and pace the work to the reset times"
metadata:
  type: feedback
---

The plan has a 5-hour and a weekly (7-day) usage limit. Every Claude Code session on the account
draws on both, and claude.ai chats probably do too. Running into one stops every session until it
resets.

`claude-usage` prints both limits with their reset times, then every Claude Code session of the
last 24 hours with its free context. `claude-usage report --json` gives the same as JSON:
`limits.five_hour` and `limits.seven_day` have `used_percentage`, `resets_at` (epoch seconds) and
`as_of`. On Windows, run `py "$LOCALAPPDATA/claude-usage/claude_usage.py"` instead (in
PowerShell, `$env:LOCALAPPDATA`). The figures
are account-wide, as of the latest response of any session ("as of 14:27"). Reading them costs
only the command's output.

- Check at the start of a session, at each milestone, and before anything heavy: several agents,
  a long test or build run, reading a large codebase. Not more often than that.
- Before a heavy step, say roughly what it will cost and how that compares with what is left.
- 5-hour limit above about 80 %: finish the current step. Don't start several agents at once,
  and say when the window resets so the user can decide whether to wait.
- Weekly limit above about 85 %: finish and write down the current work (what is done, what is
  next), rather than start a new area.
- Agents are the biggest cost. Use them for independent, well-scoped work, and read a single known
  file yourself. Launch them in waves of 3–4 and check usage between waves. Give reading and
  extraction to a cheaper model, and spot-check its claims. Brief them with exact files and line
  ranges.
- Every request re-reads the whole conversation. Don't poll a background task; wait for its
  notice. Split a long session at a milestone and start the next from a written prompt, rather
  than carrying a context near its limit.
- An agent stopped by the limit keeps its uncommitted work in the tree. After the reset, resume
  it with a message rather than starting a new one, which would read everything again.
- This session's own free context is in its row of the report (find it by its working
  directory). When it runs low, finish the milestone and hand over.

**Why:** the limits are shared by every session and are only visible from outside a session.
Work that runs into one stops halfway, and all other sessions stop with it.

**How to apply:** follow the list above as defaults, not rules. Where one would make the work
noticeably worse, don't follow it, and say why. The 80 % and 85 % thresholds are starting points:
adjust them to how the plan is used.
