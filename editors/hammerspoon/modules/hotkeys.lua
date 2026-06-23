local constants = require("modules.constants")
local focus = require("modules.focus")
local layouts = require("modules.layouts")
local resize = require("modules.resize")

local hyper = constants.hyper
local shiftHyper = { "cmd", "alt", "shift" }
local pendingScriptTasks = {}

local function runScript(scriptPath)
  if not hs.fs.attributes(scriptPath) then
    hs.printf("Script not found: %s", scriptPath)
    return
  end

  local task
  task = hs.task.new("/bin/zsh", function(exitCode, _, stderr)
    pendingScriptTasks[task] = nil
    if exitCode ~= 0 then
      hs.printf("Script failed: %s exit=%s %s", scriptPath, tostring(exitCode), tostring(stderr or ""))
    end
  end, { scriptPath })

  if not task or not task:start() then
    hs.printf("Script could not start: %s", scriptPath)
    return
  end

  pendingScriptTasks[task] = true
end

local directions = {
  h = "left",
  j = "down",
  k = "up",
  l = "right",
}

local desktopKeys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }

-- Native macOS Spaces. Mission Control must expose Ctrl+1..Ctrl+0 shortcuts.
for _, key in ipairs(desktopKeys) do
  hs.hotkey.bind(hyper, key, function()
    hs.eventtap.keyStroke({ "ctrl" }, key, 0)
  end)
end

-- Focus and move windows.
for key, direction in pairs(directions) do
  hs.hotkey.bind(hyper, key, function()
    focus.focusDirection(direction)
  end)

  hs.hotkey.bind(shiftHyper, key, function()
    focus.moveDirection(direction)
  end)
end

-- Resize focused window width.
hs.hotkey.bind(hyper, "-", function()
  resize.shrinkFocusedWindow()
end)

hs.hotkey.bind(hyper, "=", function()
  resize.growFocusedWindow()
end)

hs.hotkey.bind(hyper, "m", function()
  resize.centerFocusedWindow()
end)

hs.hotkey.bind(hyper, "f", function()
  resize.maximizeFocusedWindow()
end)

hs.hotkey.bind(shiftHyper, "b", function()
  runScript((os.getenv("HOME") or "") .. "/.dotfiles/scripts/wm/toggle-sketchybar.sh")
end)

-- Layout presets. The previous "/" bindings registered but did not fire,
-- likely because another process (macOS accessibility/Raycast)
-- intercepts Cmd+Alt+"/". "s" is free and mnemonic for "stack" layout.
hs.hotkey.bind(hyper, "s", function()
  layouts.StackRightLayout()
end)

hs.hotkey.bind(shiftHyper, "s", function()
  layouts.ColumnsLayout()
end)

hs.hotkey.bind(shiftHyper, "m", function()
  layouts.CenterMainLayout()
end)

-- Monitor navigation.
hs.hotkey.bind(hyper, "tab", function()
  focus.focusNextMonitor()
end)

hs.hotkey.bind(shiftHyper, "tab", function()
  focus.moveToNextMonitor()
end)

-- App launcher.
-- Customize app names to match your installed apps before exporting to a new machine.
local apps = {
  { key = "return", name = "Ghostty" },
  { key = "o", name = "Obsidian" },
  { key = "b", name = "Safari" },
  { key = "c", name = "Visual Studio Code" },
}

for _, app in ipairs(apps) do
  hs.hotkey.bind(hyper, app.key, function()
    hs.application.launchOrFocus(app.name)
  end)
end
