#!/usr/bin/env zsh

set -euo pipefail

if [[ -n "${AEROSPACE_TOP_GAP:-}" ]]; then
  top_gap="${AEROSPACE_TOP_GAP}"
elif command -v sketchybar >/dev/null 2>&1 && [[ "$(sketchybar --query bar 2>/dev/null | /usr/bin/awk -F'\"' '/\"hidden\"/ { print $4; exit }')" == "on" ]]; then
  top_gap="8"
else
  top_gap="42"
fi

hs -c "
local topGap = tonumber('${top_gap}') or 42

local function visibleFrameForScreen(screen)
  if type(screen.visibleFrame) == 'function' then
    local frame = screen:visibleFrame()
    frame.y = frame.y + topGap
    frame.h = frame.h - topGap
    return frame
  end

  local frame = screen:frame()
  frame.y = frame.y + topGap
  frame.h = frame.h - topGap
  return frame
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

"${HOME}/.dotfiles/scripts/wm/save-visible-window-frames.sh" >/dev/null
