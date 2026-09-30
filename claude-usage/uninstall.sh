#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
#
# Undo install.sh: remove our entries from ~/.claude/settings.json (backed up first) and
# ~/.local/bin/claude-usage. The recorded session files are left in place; the path is printed so
# they can be deleted by hand. A KDE widget still installed shows "not installed" from then on.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$HOME/.local/bin/claude-usage"

python3 "$here/claude_usage.py" unconfigure

if [ -e "$bin" ] || [ -L "$bin" ]; then
    rm "$bin"
    echo "removed $bin"
fi

echo "Session files kept in ${CLAUDE_USAGE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-usage}"
