#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aerospace-windows.sh"

focused_id="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null || true)"

window_ids=()
while IFS= read -r window_id; do
  if [ -n "$window_id" ] && [ "$window_id" != "$focused_id" ]; then
    window_ids+=("$window_id")
  fi
done < <(aerospace_focused_workspace_ids)

if [ -n "$focused_id" ]; then
  window_ids=("$focused_id" "${window_ids[@]}")
fi

if [ "${#window_ids[@]}" -lt 2 ]; then
  exit 0
fi

target_ids=("${window_ids[@]:0:3}")

float_window_ids "${target_ids[@]}"
call_hs_layout "StackRightLayoutForIds" "${target_ids[@]}"
