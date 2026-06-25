local constants = require("modules.constants")

local hyper = constants.hyper
local shiftHyper = { "cmd", "alt", "shift" }
local pendingScriptTasks = {}

local function isGhosttyActive()
  local app = hs.application.frontmostApplication()
  if not app then
    return false
  end

  return app:name() == "Ghostty" or app:bundleID() == "com.mitchellh.ghostty"
end

local function typeTextInGhostty(text)
  if isGhosttyActive() then
    hs.eventtap.keyStrokes(text)
  end
end

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

hs.hotkey.bind(shiftHyper, "b", function()
  runScript((os.getenv("HOME") or "") .. "/.dotfiles/scripts/wm/toggle-sketchybar.sh")
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

-- Ghostty-only Spanish character shortcuts.
-- Keep these scoped to Ghostty so they do not override macOS accent composition elsewhere.
hs.hotkey.bind({ "ctrl", "alt" }, "n", function()
  typeTextInGhostty("ñ")
end)

hs.hotkey.bind({ "ctrl", "alt", "shift" }, "n", function()
  typeTextInGhostty("Ñ")
end)
