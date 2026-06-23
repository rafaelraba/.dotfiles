local constants = require("modules.constants")
local layouts = require("modules.layouts")
local workspaceLayoutRestore = require("modules.workspace_layout_restore")

local function centeredFrameForVisibleScreen(_, visibleFrame)
  local width = math.floor(visibleFrame.w * 0.70)
  local height = math.floor(visibleFrame.h * 0.90)

  return {
    x = visibleFrame.x + math.floor((visibleFrame.w - width) / 2),
    y = visibleFrame.y + math.floor((visibleFrame.h - height) / 2),
    w = width,
    h = height,
  }
end

local function visibleFrameForScreen(screen)
  if type(screen.visibleFrame) == "function" then
    return screen:visibleFrame()
  end

  return screen:frame()
end

local function resizeFocusedWindow(delta)
  local window = hs.window.focusedWindow()

  if not window then
    return
  end

  local frame = window:frame()
  local screenFrame = window:screen():frame()
  local minWidth = math.floor(screenFrame.w * constants.minWidthRatio)
  local maxWidth = screenFrame.w

  local newWidth = math.max(minWidth, math.min(maxWidth, frame.w + delta))
  local widthDelta = newWidth - frame.w
  if widthDelta == 0 then
    return
  end

  workspaceLayoutRestore.clearCurrentWorkspaceLayout()

  if math.abs(frame.x - screenFrame.x) < constants.edgeSnapThreshold then
    frame.w = newWidth
  else
    frame.x = frame.x - widthDelta
    frame.w = newWidth
  end

  window:setFrame(frame, 0)
end

local function shrinkFocusedWindow()
  resizeFocusedWindow(-constants.resizeStep)
end

local function growFocusedWindow()
  resizeFocusedWindow(constants.resizeStep)
end

local function centerFocusedWindow()
  local window = hs.window.focusedWindow()

  if not window then
    return
  end

  local screen = window:screen()

  if not screen then
    return
  end

  workspaceLayoutRestore.clearCurrentWorkspaceLayout()
  layouts.FloatWindowsForManualLayout({ window }, function()
    window:setFrame(centeredFrameForVisibleScreen(window:frame(), visibleFrameForScreen(screen)), 0)
  end)
end

local function maximizeFocusedWindow()
  local window = hs.window.focusedWindow()

  if not window then
    return
  end

  local screen = window:screen()

  if not screen then
    return
  end

  workspaceLayoutRestore.clearCurrentWorkspaceLayout()
  layouts.FloatWindowsForManualLayout({ window }, function()
    window:setFrame(visibleFrameForScreen(screen), 0)
  end)
end

return {
  centerFocusedWindow = centerFocusedWindow,
  centeredFrameForVisibleScreen = centeredFrameForVisibleScreen,
  maximizeFocusedWindow = maximizeFocusedWindow,
  resizeFocusedWindow = resizeFocusedWindow,
  shrinkFocusedWindow = shrinkFocusedWindow,
  growFocusedWindow = growFocusedWindow,
}
