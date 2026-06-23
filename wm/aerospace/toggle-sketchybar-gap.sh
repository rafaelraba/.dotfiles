#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.config/aerospace/aerospace.toml"
VISIBLE_GAP=42
HIDDEN_GAP=8
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

resolve_bin() {
	local name="$1" env_var="$2" override candidate
	shift 2

	eval "override=\${$env_var:-}"
	if [ -n "$override" ]; then
		if [ -x "$override" ]; then
			printf '%s\n' "$override"
			return 0
		fi

		printf '%s is set but not executable: %s\n' "$env_var" "$override" >&2
		return 127
	fi

	for candidate in "$@"; do
		if [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	if candidate="$(command -v "$name" 2>/dev/null)" && [ -n "$candidate" ]; then
		printf '%s\n' "$candidate"
		return 0
	fi

	printf 'Unable to resolve %s in controlled PATH: %s\n' "$name" "$PATH" >&2
	return 127
}

SKETCHYBAR_BIN="$(resolve_bin sketchybar SKETCHYBAR_BIN /opt/homebrew/bin/sketchybar /usr/local/bin/sketchybar)"
AEROSPACE_BIN="$(resolve_bin aerospace AEROSPACE_BIN /opt/homebrew/bin/aerospace /usr/local/bin/aerospace)"

hidden="$("$SKETCHYBAR_BIN" --query bar 2>/dev/null | /usr/bin/awk -F'"' '/"hidden"/ { print $4; exit }')"

if [ "$hidden" = "on" ]; then
	# Show bar, reserve room for it, and repaint each monitor workspace.
	"$SKETCHYBAR_BIN" --bar hidden=off
	"$SKETCHYBAR_BIN" --trigger aerospace_workspace_change
	/usr/bin/perl -0pi -e "s/outer\.top = \d+/outer.top = $VISIBLE_GAP/" "$CONFIG"
else
	# Hide bar and reclaim the top gap.
	"$SKETCHYBAR_BIN" --bar hidden=on
	/usr/bin/perl -0pi -e "s/outer\.top = \d+/outer.top = $HIDDEN_GAP/" "$CONFIG"
fi

"$AEROSPACE_BIN" reload-config
