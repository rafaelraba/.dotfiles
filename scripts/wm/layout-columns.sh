#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aerospace-windows.sh"

window_ids=()
while IFS= read -r window_id; do
  if [ -n "$window_id" ]; then
    window_ids+=("$window_id")
  fi
done < <(aerospace_focused_workspace_ids)

if [ "${#window_ids[@]}" -lt 2 ]; then
  exit 0
fi

float_window_ids "${window_ids[@]}"
call_hs_layout "ColumnsLayoutForIds" "${window_ids[@]}"
