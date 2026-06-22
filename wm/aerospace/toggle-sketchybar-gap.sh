#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.config/aerospace/aerospace.toml"
VISIBLE_GAP=42
HIDDEN_GAP=8

hidden="$(sketchybar --query bar 2>/dev/null | /usr/bin/awk -F'"' '/"hidden"/ { print $4; exit }')"

if [ "$hidden" = "on" ]; then
	# Show bar, reserve room for it, and repaint each monitor workspace.
	sketchybar --bar hidden=off
	sketchybar --trigger aerospace_workspace_change
	/usr/bin/perl -0pi -e "s/outer\.top = \d+/outer.top = $VISIBLE_GAP/" "$CONFIG"
else
	# Hide bar and reclaim the top gap.
	sketchybar --bar hidden=on
	/usr/bin/perl -0pi -e "s/outer\.top = \d+/outer.top = $HIDDEN_GAP/" "$CONFIG"
fi

aerospace reload-config
