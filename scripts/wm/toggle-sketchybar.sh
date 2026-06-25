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

hidden="$("$SKETCHYBAR_BIN" --query bar 2>/dev/null | /usr/bin/awk -F'"' '/"hidden"/ { print $4; exit }')"

if [ "$hidden" = "on" ]; then
	"$SKETCHYBAR_BIN" --bar hidden=off
else
	"$SKETCHYBAR_BIN" --bar hidden=on
fi
