#!/usr/bin/env bash
set -euo pipefail

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

VISIBLE_TOP_GAP=60
HIDDEN_TOP_GAP=24

set_aerospace_top_gap() {
	local top_gap="$1" config_path link_target link_dir

	config_path="$($AEROSPACE_BIN config --config-path 2>/dev/null || true)"
	if [ -z "$config_path" ] || [ ! -f "$config_path" ]; then
		config_path="$HOME/.config/aerospace/aerospace.toml"
	fi

	if [ -L "$config_path" ]; then
		link_target="$(/usr/bin/readlink "$config_path")"
		case "$link_target" in
			/*) config_path="$link_target" ;;
			*)
				link_dir="$(dirname "$config_path")"
				config_path="$link_dir/$link_target"
				;;
		esac
	fi

	/usr/bin/perl -0pi -e "s/(outer\.top\s*=\s*)\d+/\${1}$top_gap/" "$config_path"
	"$AEROSPACE_BIN" reload-config --no-gui >/dev/null
}

hidden="$("$SKETCHYBAR_BIN" --query bar 2>/dev/null | /usr/bin/awk -F'"' '/"hidden"/ { print $4; exit }')"

if [ "$hidden" = "on" ]; then
	set_aerospace_top_gap "$VISIBLE_TOP_GAP"
	"$SKETCHYBAR_BIN" --bar hidden=off
	"$SKETCHYBAR_BIN" --trigger aerospace_workspace_change
else
	"$SKETCHYBAR_BIN" --bar hidden=on
	set_aerospace_top_gap "$HIDDEN_TOP_GAP"
fi
