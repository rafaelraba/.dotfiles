#!/usr/bin/env zsh

set -euo pipefail

hs -c "
local function visibleFrameForScreen(screen)
  if type(screen.visibleFrame) == 'function' then
    return screen:visibleFrame()
  end

  return screen:frame()
end

local window = hs.window.focusedWindow()
if not window then
  return 'No focused window'
end

local screen = window:screen()
if not screen then
  return 'No screen for focused window'
end

window:setFrame(visibleFrameForScreen(screen), 0)
return 'Maximized focused window'
"
