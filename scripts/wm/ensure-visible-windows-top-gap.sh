#!/usr/bin/env zsh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if [[ -n "${AEROSPACE_TOP_GAP:-}" ]]; then
  top_gap="${AEROSPACE_TOP_GAP}"
elif command -v sketchybar >/dev/null 2>&1 && [[ "$(sketchybar --query bar 2>/dev/null | /usr/bin/awk -F'\"' '/\"hidden\"/ { print $4; exit }')" == "on" ]]; then
  top_gap="8"
else
  top_gap="42"
fi

window_ids="$(aerospace list-windows --workspace visible --format '%{window-id}' 2>/dev/null || true)"

if [[ -z "${window_ids}" ]]; then
  exit 0
fi

window_ids_csv="$(print -r -- "${window_ids}" | paste -sd, -)"

hs -c "
local topGap = tonumber('${top_gap}') or 42
local visibleTopGap = 42
local hiddenTopGap = 8
local ids = {}
local records = {}
local groups = {}

for id in string.gmatch('${window_ids_csv}', '[^,]+') do
  table.insert(ids, tonumber(id))
end

local function screenKey(screen)
  if type(screen.id) == 'function' then
    return tostring(screen:id())
  end

  return screen:name()
end

local function inferOldTopGap(minY, screenFrame)
  local visibleTop = screenFrame.y + visibleTopGap
  local hiddenTop = screenFrame.y + hiddenTopGap

  if topGap >= visibleTopGap and minY < visibleTop - 1 then
    return hiddenTopGap
  end

  if topGap <= hiddenTopGap and minY >= visibleTop - 4 and minY <= visibleTop + 4 then
    return visibleTopGap
  end

  if minY < hiddenTop then
    return hiddenTopGap
  end

  return nil
end

local function transformTopGap(frame, screenFrame, oldTopGap)
  local oldTop = screenFrame.y + oldTopGap
  local oldHeight = screenFrame.h - oldTopGap
  local newTop = screenFrame.y + topGap
  local newHeight = screenFrame.h - topGap
  local bottom = screenFrame.y + screenFrame.h

  if oldHeight <= 0 or newHeight <= 0 then
    return frame
  end

  frame.y = math.floor(newTop + (((frame.y - oldTop) / oldHeight) * newHeight) + 0.5)
  frame.h = math.max(120, math.floor(((frame.h / oldHeight) * newHeight) + 0.5))

  if frame.y < newTop then
    frame.y = newTop
  end

  if frame.y + frame.h > bottom then
    frame.h = math.max(120, bottom - frame.y)
  end

  return frame
end

for _, id in ipairs(ids) do
  local window = hs.window.get(id)

  if window and window:isStandard() and not window:isMinimized() then
    local frame = window:frame()
    local screen = window:screen()

    if screen then
      local key = screenKey(screen)
      local group = groups[key]

      if not group then
        group = {
          screenFrame = screen:frame(),
          minY = frame.y,
          records = {},
        }
        groups[key] = group
      else
        group.minY = math.min(group.minY, frame.y)
      end

      local record = {
        window = window,
        frame = frame,
        screenKey = key,
      }

      table.insert(records, record)
      table.insert(group.records, record)
    end
  end
end

local function horizontalOverlapRatio(frameA, frameB)
  local x1 = math.max(frameA.x, frameB.x)
  local x2 = math.min(frameA.x + frameA.w, frameB.x + frameB.w)

  if x2 <= x1 then
    return 0
  end

  return (x2 - x1) / math.min(frameA.w, frameB.w)
end

local function belongsToSameColumn(frameA, frameB)
  return math.abs(frameA.x - frameB.x) <= 40
    and math.abs(frameA.w - frameB.w) <= 40
    and horizontalOverlapRatio(frameA, frameB) >= 0.85
end

local function resolveColumnOverlaps(group)
  local columns = {}

  table.sort(group.records, function(a, b)
    if math.abs(a.frame.x - b.frame.x) > 10 then
      return a.frame.x < b.frame.x
    end

    return a.frame.y < b.frame.y
  end)

  for _, record in ipairs(group.records) do
    local inserted = false

    for _, column in ipairs(columns) do
      if belongsToSameColumn(record.frame, column[1].frame) then
        table.insert(column, record)
        inserted = true
        break
      end
    end

    if not inserted then
      table.insert(columns, { record })
    end
  end

  for _, column in ipairs(columns) do
    if #column > 1 then
      table.sort(column, function(a, b)
        return a.frame.y < b.frame.y
      end)

      local hasOverlap = false

      for index = 1, #column - 1 do
        if column[index].frame.y + column[index].frame.h > column[index + 1].frame.y then
          hasOverlap = true
          break
        end
      end

      if hasOverlap then
        local innerGap = 8
        local top = math.max(group.screenFrame.y + topGap, column[1].frame.y)
        local bottom = group.screenFrame.y + group.screenFrame.h
        local availableHeight = bottom - top - (innerGap * (#column - 1))
        local totalHeight = 0

        for _, record in ipairs(column) do
          totalHeight = totalHeight + record.frame.h
        end

        if availableHeight > 120 * #column and totalHeight > 0 then
          local y = top
          local remainingHeight = availableHeight

          for index, record in ipairs(column) do
            local height

            if index == #column then
              height = remainingHeight
            else
              height = math.max(120, math.floor((availableHeight * (record.frame.h / totalHeight)) + 0.5))
              remainingHeight = remainingHeight - height
            end

            record.frame.y = y
            record.frame.h = height
            y = y + height + innerGap
          end
        end
      end
    end
  end
end

local function framesAreEquivalent(frameA, frameB)
  local tolerance = 2

  return math.abs(frameA.x - frameB.x) <= tolerance
    and math.abs(frameA.y - frameB.y) <= tolerance
    and math.abs(frameA.w - frameB.w) <= tolerance
    and math.abs(frameA.h - frameB.h) <= tolerance
end

for _, record in ipairs(records) do
  local group = groups[record.screenKey]
  local frame = record.frame
  local targetY = group.screenFrame.y + topGap
  local bottom = group.screenFrame.y + group.screenFrame.h
  local oldTopGap = inferOldTopGap(group.minY, group.screenFrame)

  if oldTopGap and oldTopGap ~= topGap then
    frame = transformTopGap(frame, group.screenFrame, oldTopGap)
  elseif frame.y < targetY or (topGap < visibleTopGap and frame.y > targetY and frame.y <= group.screenFrame.y + visibleTopGap + 4) then
    frame.y = targetY

    if frame.y + frame.h > bottom then
      frame.h = math.max(120, bottom - frame.y)
    end
  end

  record.frame = frame
end

for _, group in pairs(groups) do
  resolveColumnOverlaps(group)
end

for _, record in ipairs(records) do
  if not framesAreEquivalent(record.window:frame(), record.frame) then
    record.window:setFrame(record.frame, 0)
  end
end

return 'Ensured visible windows top gap ' .. tostring(topGap)
"
