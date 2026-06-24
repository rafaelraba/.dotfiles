#!/usr/bin/env zsh

set -euo pipefail

gap="${1:-8}"
left_ratio="${2:-0.55}"

window_ids="$(aerospace list-windows --workspace focused --format '%{window-id}')"

if [[ -z "${window_ids}" ]]; then
  exit 0
fi

window_ids_csv="$(print -r -- "${window_ids}" | paste -sd, -)"

while IFS= read -r window_id; do
  [[ -z "${window_id}" ]] && continue
  aerospace layout --window-id "${window_id}" floating >/dev/null || true
done <<< "${window_ids}"

hs -c "
local gap = tonumber('${gap}') or 8
local leftRatio = tonumber('${left_ratio}') or 0.55
local ids = {}

for id in string.gmatch('${window_ids_csv}', '[^,]+') do
  table.insert(ids, tonumber(id))
end

local windows = {}
for _, id in ipairs(ids) do
  local window = hs.window.get(id)
  if window and window:isStandard() and not window:isMinimized() then
    table.insert(windows, window)
  end
end

if #windows < 2 then
  return 'Need at least 2 windows'
end

if #windows > 3 then
  windows = { windows[1], windows[2], windows[3] }
end

local screenFrame = windows[1]:screen():frame()
local leftWidth = math.floor((screenFrame.w - gap) * leftRatio)
local rightWidth = screenFrame.w - leftWidth - gap

windows[1]:setFrame({
  x = screenFrame.x,
  y = screenFrame.y,
  w = leftWidth,
  h = screenFrame.h,
}, 0)

if #windows == 2 then
  windows[2]:setFrame({
    x = screenFrame.x + leftWidth + gap,
    y = screenFrame.y,
    w = rightWidth,
    h = screenFrame.h,
  }, 0)

  return 'Applied main-left layout with 2 windows'
end

local rightHeight = math.floor((screenFrame.h - gap) / 2)

windows[2]:setFrame({
  x = screenFrame.x + leftWidth + gap,
  y = screenFrame.y,
  w = rightWidth,
  h = rightHeight,
}, 0)

windows[3]:setFrame({
  x = screenFrame.x + leftWidth + gap,
  y = screenFrame.y + rightHeight + gap,
  w = rightWidth,
  h = screenFrame.h - rightHeight - gap,
}, 0)

return 'Applied main-left stack-right layout'
"
