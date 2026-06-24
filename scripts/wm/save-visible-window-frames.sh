#!/usr/bin/env zsh

set -euo pipefail

state_file="${AEROSPACE_FRAME_STATE:-${XDG_CACHE_HOME:-$HOME/.cache}/aerospace-window-frames.tsv}"
mkdir -p "$(dirname "$state_file")"

visible_window_ids="$(aerospace list-windows --workspace visible --format '%{window-id}' 2>/dev/null || true)"
[[ -n "$visible_window_ids" ]] || exit 0

visible_csv="$(print -r -- "$visible_window_ids" | paste -sd, -)"

tmp_file="$(mktemp)"
existing_file="$(mktemp)"
touch "$state_file"

hs -c "
local visible = {}

for id in string.gmatch('${visible_csv}', '[^,]+') do
  visible[tonumber(id)] = true
end

for _, window in ipairs(hs.window.visibleWindows()) do
  local id = window:id()

  if id and visible[id] and window:isStandard() and not window:isMinimized() then
    local frame = window:frame()
    print(string.format('%d\t%d\t%d\t%d\t%d', id, frame.x, frame.y, frame.w, frame.h))
  end
end
" > "$tmp_file"

if [[ -s "$tmp_file" ]]; then
  /usr/bin/awk 'NR == FNR { seen[$1] = 1; next } !($1 in seen)' "$tmp_file" "$state_file" > "$existing_file"
  cat "$existing_file" "$tmp_file" > "$state_file"
fi

rm -f "$tmp_file" "$existing_file"
