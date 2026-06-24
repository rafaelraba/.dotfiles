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
AEROSPACE_CONFIG="${AEROSPACE_CONFIG:-$HOME/.dotfiles/editors/aerospace/aerospace.toml}"
VISIBLE_TOP_GAP="${VISIBLE_TOP_GAP:-42}"
HIDDEN_TOP_GAP="${HIDDEN_TOP_GAP:-8}"

set_aerospace_top_gap() {
	local top_gap="$1"

	python3 - "$AEROSPACE_CONFIG" "$top_gap" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
top_gap = sys.argv[2]
content = path.read_text()
updated = re.sub(r"(?m)^(\s*outer\.top\s*=\s*)\d+\s*$", rf"\g<1>{top_gap}", content, count=1)

if updated == content:
    raise SystemExit("outer.top setting not found")

path.write_text(updated)
PY

	"$AEROSPACE_BIN" reload-config >/dev/null
	"$HOME/.dotfiles/scripts/wm/ensure-visible-windows-top-gap.sh" >/dev/null
}

hidden="$("$SKETCHYBAR_BIN" --query bar 2>/dev/null | /usr/bin/awk -F'"' '/"hidden"/ { print $4; exit }')"

if [ "$hidden" = "on" ]; then
	"$SKETCHYBAR_BIN" --bar hidden=off
	set_aerospace_top_gap "$VISIBLE_TOP_GAP"
else
	"$SKETCHYBAR_BIN" --bar hidden=on
	set_aerospace_top_gap "$HIDDEN_TOP_GAP"
fi
