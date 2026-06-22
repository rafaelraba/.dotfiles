local constants = require("modules.constants")
local gap = constants.gap

local function filterValidWindows(windowIds)
  local windows = {}

  for _, windowId in ipairs(windowIds) do
    local window = hs.window.get(windowId)

    if window and window:isStandard() and not window:isMinimized() then
      table.insert(windows, window)
    end
  end

  return windows
end

function StackRightLayoutForIds(windowIds)
  local windows = filterValidWindows(windowIds)

  if #windows < 2 then
    hs.alert.show("Need at least 2 windows")
    return
  end

  local screenFrame = windows[1]:screen():frame()
  local leftRatio = constants.leftRatio
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

    return
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
end

function ColumnsLayoutForIds(windowIds)
  local windows = filterValidWindows(windowIds)

  if #windows < 2 then
    hs.alert.show("Need at least 2 windows")
    return
  end

  local screenFrame = windows[1]:screen():frame()
  local totalGap = gap * (#windows - 1)
  local columnWidth = math.floor((screenFrame.w - totalGap) / #windows)

  for index, window in ipairs(windows) do
    local x = screenFrame.x + ((columnWidth + gap) * (index - 1))
    local width = columnWidth

    if index == #windows then
      width = screenFrame.x + screenFrame.w - x
    end

    window:setFrame({
      x = x,
      y = screenFrame.y,
      w = width,
      h = screenFrame.h,
    }, 0)
  end
end

return {
  StackRightLayoutForIds = StackRightLayoutForIds,
  ColumnsLayoutForIds = ColumnsLayoutForIds,
}
