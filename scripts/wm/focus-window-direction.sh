#!/usr/bin/env zsh

set -euo pipefail

direction="${1:?Usage: focus-window-direction.sh left|down|up|right}"

case "${direction}" in
  left|down|up|right) ;;
  *)
    print -u2 "Invalid direction: ${direction}. Expected left, down, up, or right."
    exit 1
    ;;
esac

hs -c "
local direction = '${direction}'
local threshold = 20

local function windowCenter(window)
  local frame = window:frame()
  return {
    x = frame.x + frame.w / 2,
    y = frame.y + frame.h / 2,
  }
end

local function frameIntersectionArea(frameA, frameB)
  local x1 = math.max(frameA.x, frameB.x)
  local y1 = math.max(frameA.y, frameB.y)
  local x2 = math.min(frameA.x + frameA.w, frameB.x + frameB.w)
  local y2 = math.min(frameA.y + frameA.h, frameB.y + frameB.h)

  if x2 <= x1 or y2 <= y1 then
    return 0
  end

  return (x2 - x1) * (y2 - y1)
end

local function windowIsOnScreen(window, screen)
  local frame = window:frame()
  local center = windowCenter(window)
  local screenFrame = screen:frame()

  if center.x >= screenFrame.x
    and center.x <= screenFrame.x + screenFrame.w
    and center.y >= screenFrame.y
    and center.y <= screenFrame.y + screenFrame.h
  then
    return true
  end

  local windowArea = frame.w * frame.h
  if windowArea <= 0 then
    return false
  end

  return frameIntersectionArea(frame, screenFrame) >= windowArea * 0.25
end

local function isInDirection(focusedCenter, targetCenter)
  local dx = targetCenter.x - focusedCenter.x
  local dy = targetCenter.y - focusedCenter.y

  if direction == 'left' then
    return dx < -threshold
  elseif direction == 'right' then
    return dx > threshold
  elseif direction == 'up' then
    return dy < -threshold
  elseif direction == 'down' then
    return dy > threshold
  end

  return false
end

local focused = hs.window.focusedWindow()
if not focused then
  return 'No focused window'
end

local focusedScreen = focused:screen()
local focusedCenter = windowCenter(focused)
local candidates = {}

for _, window in ipairs(hs.window.visibleWindows()) do
  if window ~= focused and window:isStandard() and not window:isMinimized() and windowIsOnScreen(window, focusedScreen) then
    local center = windowCenter(window)

    if isInDirection(focusedCenter, center) then
      local dx = center.x - focusedCenter.x
      local dy = center.y - focusedCenter.y
      local primaryDistance
      local secondaryDistance

      if direction == 'left' or direction == 'right' then
        primaryDistance = math.abs(dx)
        secondaryDistance = math.abs(dy)
      else
        primaryDistance = math.abs(dy)
        secondaryDistance = math.abs(dx)
      end
      local distance = math.sqrt(dx * dx + dy * dy)

      table.insert(candidates, {
        window = window,
        primaryDistance = primaryDistance,
        secondaryDistance = secondaryDistance,
        distance = distance,
      })
    end
  end
end

if #candidates == 0 then
  return 'No window ' .. direction
end

table.sort(candidates, function(a, b)
  if math.abs(a.secondaryDistance - b.secondaryDistance) > 20 then
    return a.secondaryDistance < b.secondaryDistance
  end

  return a.distance < b.distance
end)

candidates[1].window:focus()
return 'Focused window ' .. direction
"
