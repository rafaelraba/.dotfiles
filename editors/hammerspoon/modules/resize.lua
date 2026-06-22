local constants = require("modules.constants")

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

  if math.abs(frame.x - screenFrame.x) < 12 then
    frame.w = newWidth
  else
    frame.x = frame.x - widthDelta
    frame.w = newWidth
  end

  window:setFrame(frame, 0)
end

return {
  resizeFocusedWindow = resizeFocusedWindow,
}
