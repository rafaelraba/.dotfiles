local constants = require("modules.constants")

local function focusedWindowOrAlert()
  local window = hs.window.focusedWindow()

  if not window then
    hs.alert.show("No focused window")
  end

  return window
end

local function clearSavedWorkspaceLayout()
  local ok, workspaceLayoutRestore = pcall(require, "modules.workspace_layout_restore")
  if ok and workspaceLayoutRestore and workspaceLayoutRestore.clearCurrentWorkspaceLayout then
    workspaceLayoutRestore.clearCurrentWorkspaceLayout()
  end
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

local function candidateWindowsOnScreen(screen)
  local candidates = {}

  for _, window in ipairs(hs.window.visibleWindows()) do
    if window:isStandard() and not window:isMinimized() and windowIsOnScreen(window, screen) then
      table.insert(candidates, window)
    end
  end

  return candidates
end

local function isInDirection(direction, focusedCenter, targetCenter)
  local dx = targetCenter.x - focusedCenter.x
  local dy = targetCenter.y - focusedCenter.y
  local threshold = constants.directionThreshold

  if direction == "left" then
    return dx < -threshold
  elseif direction == "right" then
    return dx > threshold
  elseif direction == "up" then
    return dy < -threshold
  elseif direction == "down" then
    return dy > threshold
  end

  return false
end

local function focusDirection(direction)
  local focused = focusedWindowOrAlert()

  if not focused then
    return
  end

  local focusedScreen = focused:screen()
  local focusedCenter = windowCenter(focused)
  local candidates = {}

  for _, window in ipairs(candidateWindowsOnScreen(focusedScreen)) do
    if window ~= focused then
      local center = windowCenter(window)

      if isInDirection(direction, focusedCenter, center) then
        local dx = center.x - focusedCenter.x
        local dy = center.y - focusedCenter.y
        local distance = math.sqrt(dx * dx + dy * dy)
        table.insert(candidates, { window = window, distance = distance })
      end
    end
  end

  if #candidates == 0 then
    hs.alert.show("No window " .. direction)
    return
  end

  table.sort(candidates, function(a, b)
    return a.distance < b.distance
  end)

  candidates[1].window:focus()
end

local function moveDirection(direction)
  local window = focusedWindowOrAlert()

  if not window then
    return
  end

  local frame = window:frame()
  local moveStep = constants.resizeStep

  if direction == "left" then
    frame.x = frame.x - moveStep
  elseif direction == "right" then
    frame.x = frame.x + moveStep
  elseif direction == "up" then
    frame.y = frame.y - moveStep
  elseif direction == "down" then
    frame.y = frame.y + moveStep
  end

  clearSavedWorkspaceLayout()
  window:setFrame(frame, 0)
end

local function focusNextMonitor()
  local focused = hs.window.focusedWindow()
  local currentScreen = focused and focused:screen() or hs.screen.mainScreen()
  local nextScreen = currentScreen:next()

  if not nextScreen then
    return
  end

  for _, window in ipairs(candidateWindowsOnScreen(nextScreen)) do
    window:focus()
    return
  end
end

local function moveToNextMonitor()
  local window = focusedWindowOrAlert()

  if not window then
    return
  end

  local nextScreen = window:screen():next()

  if nextScreen then
    window:moveToScreen(nextScreen)
  end
end

return {
  focusDirection = focusDirection,
  moveDirection = moveDirection,
  focusNextMonitor = focusNextMonitor,
  moveToNextMonitor = moveToNextMonitor,
}
