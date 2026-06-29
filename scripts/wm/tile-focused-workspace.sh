#!/usr/bin/env zsh

set -euo pipefail

window_ids="$(aerospace list-windows --workspace focused --format '%{window-id}')"

if [[ -z "${window_ids}" ]]; then
  exit 0
fi

while IFS= read -r window_id; do
  [[ -z "${window_id}" ]] && continue
  aerospace layout --window-id "${window_id}" tiling >/dev/null || true
done <<< "${window_ids}"

aerospace flatten-workspace-tree >/dev/null || true
aerospace layout tiles horizontal vertical >/dev/null || true
aerospace balance-sizes >/dev/null || true
