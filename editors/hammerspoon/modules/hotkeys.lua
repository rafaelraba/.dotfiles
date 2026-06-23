local constants = require("modules.constants")
local focus = require("modules.focus")
local layouts = require("modules.layouts")
local resize = require("modules.resize")
local workspaceLayoutRestore = require("modules.workspace_layout_restore")

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
  runScript((os.getenv("HOME") or "") .. "/.dotfiles/wm/aerospace/toggle-sketchybar-gap.sh")
end)

-- Layout presets. The previous "/" bindings registered but did not fire,
-- likely because another process (macOS accessibility/Raycast/AeroSpace)
-- intercepts Cmd+Alt+"/". "s" is free and mnemonic for "stack" layout.
hs.hotkey.bind(hyper, "s", function()
  local applied, windowIds = layouts.StackRightLayout()
  if applied then
    workspaceLayoutRestore.saveCurrentWorkspaceLayout("stack-right", windowIds)
  end
end)

hs.hotkey.bind(shiftHyper, "s", function()
  local applied, windowIds = layouts.ColumnsLayout()
  if applied then
    workspaceLayoutRestore.saveCurrentWorkspaceLayout("columns", windowIds)
  end
end)

hs.hotkey.bind(shiftHyper, "m", function()
  local applied, windowIds = layouts.CenterMainLayout()
  if applied then
    workspaceLayoutRestore.saveCurrentWorkspaceLayout("center-main", windowIds)
  end
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
