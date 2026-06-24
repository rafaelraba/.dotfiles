#!/usr/bin/env zsh

set -euo pipefail

width_ratio="${1:-0.66}"
height_ratio="${2:-0.85}"

hs -c "
local widthRatio = tonumber('${width_ratio}')
local heightRatio = tonumber('${height_ratio}')

if not widthRatio or not heightRatio then
  return 'Invalid window ratios'
end

local window = hs.window.focusedWindow()
if not window then
  return 'No focused window'
end

local screenFrame = window:screen():frame()
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
