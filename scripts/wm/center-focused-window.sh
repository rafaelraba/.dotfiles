#!/usr/bin/env zsh

set -euo pipefail

width_ratio="${1:-0.66}"
height_ratio="${2:-0.85}"

if [[ -n "${AEROSPACE_TOP_GAP:-}" ]]; then
  top_gap="${AEROSPACE_TOP_GAP}"
elif command -v sketchybar >/dev/null 2>&1 && [[ "$(sketchybar --query bar 2>/dev/null | /usr/bin/awk -F'\"' '/\"hidden\"/ { print $4; exit }')" == "on" ]]; then
  top_gap="8"
else
  top_gap="42"
fi

hs -c "
local widthRatio = tonumber('${width_ratio}')
local heightRatio = tonumber('${height_ratio}')
local topGap = tonumber('${top_gap}') or 42

if not widthRatio or not heightRatio then
  return 'Invalid window ratios'
end

local window = hs.window.focusedWindow()
if not window then
  return 'No focused window'
end

local screenFrame = window:screen():frame()
screenFrame.y = screenFrame.y + topGap
screenFrame.h = screenFrame.h - topGap
local width = math.floor(screenFrame.w * widthRatio)
local height = math.floor(screenFrame.h * heightRatio)

window:setFrame({
  x = math.floor(screenFrame.x + ((screenFrame.w - width) / 2)),
  y = math.floor(screenFrame.y + ((screenFrame.h - height) / 2)),
  w = width,
  h = height,
}, 0)

return string.format('Centered focused window at %.0f%% width and %.0f%% height', widthRatio * 100, heightRatio * 100)
"

"${HOME}/.dotfiles/scripts/wm/save-visible-window-frames.sh" >/dev/null
