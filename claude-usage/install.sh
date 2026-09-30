#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
#
# Install the `claude-usage` command for the current user (Linux, macOS):
#   1. a copy of claude_usage.py as ~/.local/bin/claude-usage
#   2. the Claude Code status line + SessionEnd hook (~/.claude/settings.json, backed up first)
# Running it again upgrades in place. Windows: see the README.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$HOME/.local/bin/claude-usage"

if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    echo "claude-usage needs Python 3.10 or newer as python3; found: $(python3 --version 2>&1)" >&2
    exit 1
fi

# Through a temp file and a rename: every open Claude Code session runs this file after each
# response, and a rename also replaces the link older versions made into the widget package.
mkdir -p "$(dirname "$bin")"
cp "$here/claude_usage.py" "$bin.tmp"
chmod 755 "$bin.tmp"
mv -f "$bin.tmp" "$bin"
echo "installed $bin"

"$bin" configure --command "$bin"

echo
case ":$PATH:" in
    *":$HOME/.local/bin:"*) echo "Try it:  claude-usage" ;;
    *) echo "Try it:  $bin   (~/.local/bin is not on your PATH)" ;;
esac
echo "The figures appear after the next response in any Claude Code session."
