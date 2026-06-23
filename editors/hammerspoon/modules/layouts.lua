local constants = require("modules.constants")
local gap = constants.gap
local resolvedAerospaceCli = nil
local pendingFloatTasks = {}

hs.window.animationDuration = 0

local function executableExists(command)
  local attributes = hs.fs.attributes(command)
  return attributes and attributes.mode == "file"
end

local function executableOnPath(command)
  if command:find("/", 1, true) then
    return executableExists(command) and command or nil
  end

  local path = os.getenv("PATH") or ""
  for directory in path:gmatch("([^:]+)") do
    local candidate = directory .. "/" .. command
    if executableExists(candidate) then
      return candidate
    end
  end

  return nil
end

local function aerospaceCli()
  if resolvedAerospaceCli then
    return resolvedAerospaceCli
  end

  for _, candidate in ipairs(constants.aerospaceCliCandidates) do
    local executable = candidate and executableOnPath(candidate)
    if executable then
      resolvedAerospaceCli = executable
      return resolvedAerospaceCli
    end
  end

  return nil
end

local function cleanupFloatTask(token)
  local entry = pendingFloatTasks[token]
  if not entry then
    return
  end

  if entry.timer then
    entry.timer:stop()
  end

  pendingFloatTasks[token] = nil
end

local function floatWindowsForManualLayout(windows, callback)
  local cli = aerospaceCli()
  if not cli then
    callback()
    return
  end

  local remaining = #windows
  if remaining == 0 then
    callback()
    return
  end

  local finished = false
  local function completeOne(token)
    if not pendingFloatTasks[token] then
      return
    end

    cleanupFloatTask(token)
    remaining = remaining - 1
    if remaining <= 0 and not finished then
      finished = true
      callback()
    end
  end

  for _, window in ipairs(windows) do
    local windowId = window:id()
    local token = tostring(windowId) .. ":" .. tostring(hs.timer.absoluteTime())
    local task

    task = hs.task.new(cli, function(exitCode, _, stderr)
      if exitCode ~= 0 then
        hs.printf("AeroSpace float failed for window %d: exit=%s %s", windowId, tostring(exitCode), tostring(stderr or ""))
      end
      completeOne(token)
    end, { "layout", "--window-id", tostring(windowId), "floating" })

    if not task then
      hs.printf("AeroSpace float task could not be created for window %d", windowId)
      remaining = remaining - 1
      if remaining <= 0 and not finished then
        finished = true
        callback()
      end
    else
      pendingFloatTasks[token] = {
        task = task,
        timer = hs.timer.doAfter(constants.aerospaceCliTimeout, function()
          local entry = pendingFloatTasks[token]
          if entry and entry.task then
            entry.task:terminate()
          end
          hs.printf("AeroSpace float timed out for window %d", windowId)
          completeOne(token)
        end),
      }

      if not task:start() then
        hs.printf("AeroSpace float could not start for window %d", windowId)
        completeOne(token)
      end
    end
  end
end

local function applyAfterFloat(windows, applyFrames, onApplied)
  floatWindowsForManualLayout(windows, function()
    local ok, err = pcall(applyFrames)
    if not ok then
      hs.printf("Hammerspoon layout frame application failed: %s", tostring(err))
    end

    if onApplied then
      onApplied()
    end
  end)
end

local function targetScreen()
  local focused = hs.window.focusedWindow()

  if focused then
    return focused:screen()
  end

  return hs.screen.mainScreen()
end

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

  -- Center on the target screen is the strongest signal.
  if center.x >= screenFrame.x
    and center.x <= screenFrame.x + screenFrame.w
    and center.y >= screenFrame.y
    and center.y <= screenFrame.y + screenFrame.h
  then
    return true
  end

  -- Otherwise require a meaningful frame intersection.
  local windowArea = frame.w * frame.h
  if windowArea <= 0 then
    return false
  end

  local intersectionArea = frameIntersectionArea(frame, screenFrame)
  return intersectionArea >= windowArea * 0.25
end

local function filterValidWindowsOnScreen(windowIds)
  local allValid = {}

  for _, windowId in ipairs(windowIds) do
    local window = hs.window.get(windowId)

    if window and window:isStandard() and not window:isMinimized() then
      table.insert(allValid, window)
    end
  end

  if #allValid == 0 then
    return {}
  end

  local targetScreen = targetScreen()
  local windows = {}

  for _, window in ipairs(allValid) do
    if windowIsOnScreen(window, targetScreen) then
      table.insert(windows, window)
    end
  end

  return windows
end

local function windowIdsForWindows(windows)
  local ids = {}

  for _, window in ipairs(windows) do
    table.insert(ids, window:id())
  end

  return ids
end

function StackRightLayoutForIds(windowIds, options)
  options = options or {}
  local windows = filterValidWindowsOnScreen(windowIds)

  if #windows < 2 then
    if options.showAlert ~= false then
      hs.alert.show("Need at least 2 windows")
    end
    return false, {}
  end

  if #windows > constants.stackRightMaxWindows then
    windows = { windows[1], windows[2], windows[3] }
  end

  local appliedWindowIds = windowIdsForWindows(windows)

  applyAfterFloat(windows, function()
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
  end, options.onApplied)

  return true, appliedWindowIds
end

function ColumnsLayoutForIds(windowIds, options)
  options = options or {}
  local windows = filterValidWindowsOnScreen(windowIds)

  if #windows < 2 then
    if options.showAlert ~= false then
      hs.alert.show("Need at least 2 windows")
    end
    return false, {}
  end

  local appliedWindowIds = windowIdsForWindows(windows)

  applyAfterFloat(windows, function()
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
  end, options.onApplied)

  return true, appliedWindowIds
end

local function setStackedSideFrames(windows, screenFrame, x, width)
  if #windows == 0 then
    return
  end

  local totalGap = gap * (#windows - 1)
  local rowHeight = math.floor((screenFrame.h - totalGap) / #windows)

  for index, window in ipairs(windows) do
    local y = screenFrame.y + ((rowHeight + gap) * (index - 1))
    local height = rowHeight

    if index == #windows then
      height = screenFrame.y + screenFrame.h - y
    end

    window:setFrame({
      x = x,
      y = y,
      w = width,
      h = height,
    }, 0)
  end
end

function CenterMainLayoutForIds(windowIds, options)
  options = options or {}
  local windows = filterValidWindowsOnScreen(windowIds)

  if #windows < 2 then
    if options.showAlert ~= false then
      hs.alert.show("Need at least 2 windows")
    end
    return false, {}
  end

  local appliedWindowIds = windowIdsForWindows(windows)

  applyAfterFloat(windows, function()
    local screenFrame = windows[1]:screen():frame()
    local mainWidth = math.floor(screenFrame.w * constants.centerMainRatio)
    local sideWidth = math.floor((screenFrame.w - mainWidth - (gap * 2)) / 2)

    if sideWidth < 1 then
      mainWidth = screenFrame.w - (gap * 2) - 2
      sideWidth = 1
    end

    local leftX = screenFrame.x
    local mainX = leftX + sideWidth + gap
    local rightX = mainX + mainWidth + gap
    local leftWindows = {}
    local rightWindows = {}

    windows[1]:setFrame({
      x = mainX,
      y = screenFrame.y,
      w = mainWidth,
      h = screenFrame.h,
    }, 0)

    for index = 2, #windows do
      if index % 2 == 0 then
        table.insert(leftWindows, windows[index])
      else
        table.insert(rightWindows, windows[index])
      end
    end

    setStackedSideFrames(leftWindows, screenFrame, leftX, sideWidth)
    setStackedSideFrames(rightWindows, screenFrame, rightX, screenFrame.x + screenFrame.w - rightX)
  end, options.onApplied)

  return true, appliedWindowIds
end

local function windowsOnCurrentScreen()
  local screen = targetScreen()
  local windows = {}

  for _, window in ipairs(hs.window.visibleWindows()) do
    if window:isStandard() and not window:isMinimized() and windowIsOnScreen(window, screen) then
      table.insert(windows, window)
    end
  end

  return windows
end

local function windowIdsWithFocusedFirst(windows)
  local focused = hs.window.focusedWindow()
  local ids = {}

  if focused then
    table.insert(ids, focused:id())
  end

  for _, window in ipairs(windows) do
    if window ~= focused then
      table.insert(ids, window:id())
    end
  end

  return ids
end

function StackRightLayout()
  local windows = windowsOnCurrentScreen()
  return StackRightLayoutForIds(windowIdsWithFocusedFirst(windows))
end

function ColumnsLayout()
  local windows = windowsOnCurrentScreen()
  return ColumnsLayoutForIds(windowIdsWithFocusedFirst(windows))
end

function CenterMainLayout()
  local windows = windowsOnCurrentScreen()
  return CenterMainLayoutForIds(windowIdsWithFocusedFirst(windows))
end

local function WindowIdsOnCurrentScreen()
  return windowIdsWithFocusedFirst(windowsOnCurrentScreen())
end

return {
  StackRightLayoutForIds = StackRightLayoutForIds,
  ColumnsLayoutForIds = ColumnsLayoutForIds,
  CenterMainLayoutForIds = CenterMainLayoutForIds,
  StackRightLayout = StackRightLayout,
  ColumnsLayout = ColumnsLayout,
  CenterMainLayout = CenterMainLayout,
  WindowIdsOnCurrentScreen = WindowIdsOnCurrentScreen,
  FloatWindowsForManualLayout = floatWindowsForManualLayout,
  _test = {
    aerospaceCli = aerospaceCli,
    executableOnPath = executableOnPath,
  },
}
