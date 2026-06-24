#!/usr/bin/env zsh

set -euo pipefail

state_file="${AEROSPACE_FRAME_STATE:-${XDG_CACHE_HOME:-$HOME/.cache}/aerospace-window-frames.tsv}"
mkdir -p "$(dirname "$state_file")"

visible_windows="$(aerospace list-windows --workspace visible --format '%{window-id} %{window-layout}' 2>/dev/null || true)"
[[ -n "$visible_windows" ]] || exit 0

floating_window_ids="$(print -r -- "$visible_windows" | awk '$2 == "floating" { print $1 }')"
visible_csv="$(print -r -- "$floating_window_ids" | paste -sd, -)"

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

## Remove tiled visible windows from the cache: AeroSpace owns their position.
## This keeps save/restore from fighting tiling during workspace changes.
tiled_visible="$(print -r -- "$visible_windows" | awk '$2 != "floating" { print $1 }')"

if [[ -n "$tiled_visible" ]]; then
  /usr/bin/awk -v tiled_ids="$tiled_visible" '
    BEGIN {
      split(tiled_ids, ids, "\n")
      for (i in ids) {
        tiled[ids[i]] = 1
      }
    }

    !($1 in tiled)
  ' "$state_file" > "$existing_file"
else
  cp "$state_file" "$existing_file"
fi

if [[ -s "$tmp_file" ]]; then
  /usr/bin/awk 'NR == FNR { seen[$1] = 1; next } !($1 in seen)' "$tmp_file" "$existing_file" > "${existing_file}.merged"
  cat "${existing_file}.merged" "$tmp_file" > "$state_file"
  rm -f "${existing_file}.merged"
else
  cp "$existing_file" "$state_file"
fi

rm -f "$tmp_file" "$existing_file"
