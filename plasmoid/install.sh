#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
#
# Install the Claude Usage Plasma widget for the current user (kpackagetool6, into
# ~/.local/share/plasma/plasmoids/). It shows what the `claude-usage` command reports, so install
# that first: ../claude-usage/install.sh. Running this again upgrades in place.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])' \
      "$here/package/metadata.json")"
pkg="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$id"
bin="$HOME/.local/bin/claude-usage"

# Versions before the split linked the command into the widget package. Upgrading the package
# would delete the link's target, and with it every Claude Code session's status line.
if [ -L "$bin" ] && case "$(readlink "$bin")" in "$pkg"/*) true ;; *) false ;; esac; then
    echo "$bin still points into the widget package. Run $(dirname "$here")/claude-usage/install.sh" >&2
    echo "first: it replaces the link with a copy of the command." >&2
    exit 1
fi

if [ -d "$pkg" ]; then
    kpackagetool6 -t Plasma/Applet -u "$here/package"
    upgraded=1
else
    kpackagetool6 -t Plasma/Applet -i "$here/package"
    upgraded=0
fi

echo
if ! PATH="$HOME/.local/bin:$PATH" command -v claude-usage >/dev/null; then
    echo "Note: the claude-usage command isn't installed yet, so the widget will say so."
    echo "  $(dirname "$here")/claude-usage/install.sh"
    echo
fi
if [ "$upgraded" = 1 ]; then
    echo "Upgraded. A widget already in the panel keeps the old code until plasmashell restarts:"
    echo "  systemctl --user restart plasma-plasmashell"
else
    echo "Installed. Add it to a panel: right-click the panel > Add or Manage Widgets > \"Claude Usage\"."
fi
echo "Try it in a window first:  plasmawindowed $id"
