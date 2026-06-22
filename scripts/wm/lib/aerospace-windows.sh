#!/usr/bin/env bash
set -euo pipefail

# Shared helpers for Aerospace -> Hammerspoon layout scripts.

aerospace_focused_workspace_ids() {
  aerospace list-windows --workspace focused --format '%{window-id}'
}

float_window_ids() {
  local ids=("$@")

  for window_id in "${ids[@]}"; do
    aerospace layout --window-id "$window_id" floating >/dev/null 2>&1 || true
  done
}

call_hs_layout() {
  local layout_fn="$1"
  shift
  local ids=("$@")

  if [ "${#ids[@]}" -eq 0 ]; then
    return 0
  fi

  local lua_ids
  lua_ids="$(printf ',%s' "${ids[@]}")"
  lua_ids="{${lua_ids#,}}"

  /opt/homebrew/bin/hs -c "${layout_fn}(${lua_ids})"
}
