#!/usr/bin/env bash
set -euo pipefail

workspace="${1:-$(aerospace list-workspaces --focused)}"
focused_id="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null || true)"
window_ids=()
while IFS= read -r window_id; do
  if [ -n "$window_id" ] && [ "$window_id" != "$focused_id" ]; then
    window_ids+=("$window_id")
  fi
done < <(aerospace list-windows --workspace "$workspace" --format '%{window-id}')

if [ -n "$focused_id" ]; then
  window_ids=("$focused_id" "${window_ids[@]}")
fi

if [ "${#window_ids[@]}" -lt 2 ]; then
  exit 0
fi

aerospace workspace "$workspace" >/dev/null 2>&1 || true
aerospace flatten-workspace-tree >/dev/null 2>&1 || true
aerospace layout h_tiles >/dev/null 2>&1 || true

# Build an app-agnostic target shape from existing windows:
# 1st window: left, full height
# 2nd window: top-right
# 3rd window: bottom-right
left_id="${window_ids[0]}"
top_right_id="${window_ids[1]}"
bottom_right_id="${window_ids[2]:-}"

if [ -n "$left_id" ]; then
  aerospace layout --window-id "$left_id" h_tiles >/dev/null 2>&1 || true
  aerospace split --window-id "$left_id" horizontal >/dev/null 2>&1 || true
  aerospace focus --window-id "$left_id" >/dev/null 2>&1 || true
  aerospace move --window-id "$left_id" left >/dev/null 2>&1 || true
  aerospace resize --window-id "$left_id" width +300 >/dev/null 2>&1 || true
fi

if [ -n "$top_right_id" ]; then
  aerospace focus --window-id "$top_right_id" >/dev/null 2>&1 || true
  aerospace move --window-id "$top_right_id" right >/dev/null 2>&1 || true
  if [ -n "$bottom_right_id" ]; then
    aerospace move --window-id "$top_right_id" up >/dev/null 2>&1 || true
  fi
fi

if [ -n "$bottom_right_id" ]; then
  aerospace focus --window-id "$bottom_right_id" >/dev/null 2>&1 || true
  aerospace move --window-id "$bottom_right_id" right >/dev/null 2>&1 || true
  aerospace move --window-id "$bottom_right_id" down >/dev/null 2>&1 || true
fi

aerospace balance-sizes >/dev/null 2>&1 || true

if [ -n "$left_id" ]; then
  aerospace focus --window-id "$left_id" >/dev/null 2>&1 || true
fi
