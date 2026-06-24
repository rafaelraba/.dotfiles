#!/usr/bin/env zsh

set -euo pipefail

direction="${1:?Usage: move-focused-window-to-monitor.sh left|right|next|prev}"

case "${direction}" in
  left|right|next|prev) ;;
  *)
    print -u2 "Invalid direction: ${direction}. Expected left, right, next, or prev."
    exit 1
    ;;
esac

if [[ -n "${AEROSPACE_TOP_GAP:-}" ]]; then
  top_gap="${AEROSPACE_TOP_GAP}"
elif command -v sketchybar >/dev/null 2>&1 && [[ "$(sketchybar --query bar 2>/dev/null | /usr/bin/awk -F'\"' '/\"hidden\"/ { print $4; exit }')" == "on" ]]; then
  top_gap="8"
else
  top_gap="42"
fi

window_layout="$(aerospace list-windows --focused --format '%{window-layout}' 2>/dev/null || true)"
before_geometry=""

if [[ "${window_layout}" == "floating" ]]; then
  before_geometry="$(hs -c "
local topGap = tonumber('${top_gap}') or 42
local window = hs.window.focusedWindow()

if window and window:isStandard() and not window:isMinimized() then
  local frame = window:frame()
  local screenFrame = window:screen():frame()
  screenFrame.y = screenFrame.y + topGap
  screenFrame.h = screenFrame.h - topGap

  print(string.format('%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d', frame.x, frame.y, frame.w, frame.h, screenFrame.x, screenFrame.y, screenFrame.w, screenFrame.h))
end
" | /usr/bin/awk '/^-?[0-9]+\t/ { print; exit }')"
fi

aerospace move-node-to-monitor --focus-follows-window --wrap-around "${direction}"

if [[ "${window_layout}" != "floating" || -z "${before_geometry}" ]]; then
  exit 0
fi

IFS=$'\t' read -r old_x old_y old_w old_h source_x source_y source_w source_h <<< "${before_geometry}"

hs -c "
local topGap = tonumber('${top_gap}') or 42
local oldFrame = {
  x = tonumber('${old_x}'),
  y = tonumber('${old_y}'),
  w = tonumber('${old_w}'),
  h = tonumber('${old_h}'),
}
local sourceFrame = {
  x = tonumber('${source_x}'),
  y = tonumber('${source_y}'),
  w = tonumber('${source_w}'),
  h = tonumber('${source_h}'),
}
local window = hs.window.focusedWindow()

if not window or not window:isStandard() or window:isMinimized() then
  return 'No focused standard window to scale'
end

local screen = window:screen()
if not screen then
  return 'No screen for focused window'
end

local screenFrame = screen:frame()
screenFrame.y = screenFrame.y + topGap
screenFrame.h = screenFrame.h - topGap

local function clampFrame(frame, bounds)
  if frame.w > bounds.w then
    frame.w = bounds.w
  end

  if frame.h > bounds.h then
    frame.h = bounds.h
  end

  local maxX = bounds.x + bounds.w - frame.w
  local maxY = bounds.y + bounds.h - frame.h

  if frame.x < bounds.x then
    frame.x = bounds.x
  elseif frame.x > maxX then
    frame.x = maxX
  end

  if frame.y < bounds.y then
    frame.y = bounds.y
  elseif frame.y > maxY then
    frame.y = maxY
  end

  return frame
end

local function framesAreEquivalent(frameA, frameB)
  local tolerance = 2

  return math.abs(frameA.x - frameB.x) <= tolerance
    and math.abs(frameA.y - frameB.y) <= tolerance
    and math.abs(frameA.w - frameB.w) <= tolerance
    and math.abs(frameA.h - frameB.h) <= tolerance
end

if not oldFrame.x or not sourceFrame.x or sourceFrame.w <= 0 or sourceFrame.h <= 0 then
  local frame = clampFrame(window:frame(), screenFrame)

  if not framesAreEquivalent(window:frame(), frame) then
    window:setFrame(frame, 0)
  end

  return 'Moved and contained focused window on target monitor'
end

local frame = clampFrame({
  x = math.floor(screenFrame.x + (((oldFrame.x - sourceFrame.x) / sourceFrame.w) * screenFrame.w) + 0.5),
  y = math.floor(screenFrame.y + (((oldFrame.y - sourceFrame.y) / sourceFrame.h) * screenFrame.h) + 0.5),
  w = math.max(120, math.floor(((oldFrame.w / sourceFrame.w) * screenFrame.w) + 0.5)),
  h = math.max(120, math.floor(((oldFrame.h / sourceFrame.h) * screenFrame.h) + 0.5)),
}, screenFrame)

if not framesAreEquivalent(window:frame(), frame) then
  window:setFrame(frame, 0)
end

return 'Moved and scaled focused window on target monitor'
"

"${HOME}/.dotfiles/scripts/wm/save-visible-window-frames.sh" >/dev/null
