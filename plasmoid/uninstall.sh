#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 pe7ro
# SPDX-License-Identifier: MIT
#
# Remove the Plasma widget. The claude-usage command and its Claude Code settings stay; remove
# them with ../claude-usage/uninstall.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])' \
      "$here/package/metadata.json")"
pkg="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$id"

if [ -d "$pkg" ]; then
    kpackagetool6 -t Plasma/Applet -r "$id"
else
    echo "the widget is not installed ($pkg)"
fi
