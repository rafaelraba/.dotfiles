package.path = "./editors/hammerspoon/?.lua;./editors/hammerspoon/?/init.lua;" .. package.path

local tests = {}

local function test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message or "assertEquals", tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(value, message)
  if not value then
    error(message or "expected true", 2)
  end
end

local function resetModules()
  package.loaded["modules.layouts"] = nil
  package.loaded["modules.resize"] = nil
  package.loaded["modules.focus"] = nil
  package.loaded["modules.hotkeys"] = nil
  package.loaded["modules.constants"] = nil
end

local function assertFrame(actual, expected, message)
  assertTrue(actual, message or "missing frame")
  assertEquals(actual.x, expected.x, (message or "frame") .. " x")
  assertEquals(actual.y, expected.y, (message or "frame") .. " y")
  assertEquals(actual.w, expected.w, (message or "frame") .. " w")
  assertEquals(actual.h, expected.h, (message or "frame") .. " h")
end

local function newHarness()
  resetModules()

  local harness = {
    frames = {},
    hotkeys = {},
    windows = {},
    visibleWindowIds = {},
    taskCount = 0,
    keyStrokes = {},
    typedText = {},
    activeAppName = "Ghostty",
    activeAppBundleId = "com.mitchellh.ghostty",
  }

  local function hotkeyId(modifiers, key)
    local copy = {}
    for _, modifier in ipairs(modifiers) do
      table.insert(copy, modifier)
    end
    table.sort(copy)
    return table.concat(copy, "+") .. ":" .. key
  end

  local mainScreen = {
    frame = function()
      return { x = 0, y = 0, w = 1000, h = 800 }
    end,
    visibleFrame = function()
      return { x = 0, y = 24, w = 1000, h = 776 }
    end,
  }

  local otherScreen = {
    frame = function()
      return { x = 2000, y = 0, w = 1000, h = 800 }
    end,
    visibleFrame = function()
      return { x = 2000, y = 24, w = 1000, h = 776 }
    end,
  }

  function harness:addWindow(id, opts)
    opts = opts or {}
    local screen = opts.screen == "other" and otherScreen or mainScreen
    local frame = opts.frame or screen:frame()
    local focused = opts.focused == true
    local window = {
      id = function()
        return id
      end,
      isStandard = function()
        return opts.standard ~= false
      end,
      isMinimized = function()
        return opts.minimized == true
      end,
      screen = function()
        return screen
      end,
      frame = function()
        return frame
      end,
      setFrame = function(_, newFrame)
        harness.frames[id] = newFrame
        frame = newFrame
      end,
      focus = function()
        harness.focusedWindowId = id
      end,
    }
    self.windows[id] = window
    if focused then
      self.focusedWindowId = id
    end
    return window
  end

  function harness:setVisible(ids)
    self.visibleWindowIds = ids
  end

  function harness:visibleWindows()
    local windows = {}
    for _, id in ipairs(self.visibleWindowIds) do
      table.insert(windows, self.windows[id])
    end
    return windows
  end

  hs = {
    window = {
      animationDuration = 0,
      get = function(id)
        return harness.windows[id]
      end,
      visibleWindows = function()
        return harness:visibleWindows()
      end,
      focusedWindow = function()
        return harness.windows[harness.focusedWindowId]
      end,
    },
    screen = {
      mainScreen = function()
        return mainScreen
      end,
    },
    hotkey = {
      bind = function(modifiers, key, callback)
        harness.hotkeys[hotkeyId(modifiers, key)] = callback
      end,
    },
    alert = {
      show = function() end,
    },
    application = {
      launchOrFocus = function() end,
      frontmostApplication = function()
        return {
          name = function()
            return harness.activeAppName
          end,
          bundleID = function()
            return harness.activeAppBundleId
          end,
        }
      end,
    },
    eventtap = {
      keyStroke = function(modifiers, key)
        table.insert(harness.keyStrokes, { modifiers = modifiers, key = key })
      end,
      keyStrokes = function(text)
        table.insert(harness.typedText, text)
      end,
    },
    fs = {
      attributes = function()
        return true
      end,
    },
    printf = function() end,
    task = {
      new = function()
        harness.taskCount = harness.taskCount + 1
        error("standalone Hammerspoon layouts must not create CLI tasks")
      end,
    },
  }

  package.loaded["modules.constants"] = {
    hyper = { "cmd", "alt" },
    gap = 8,
    leftRatio = 0.62,
    centerMainRatio = 0.65,
    stackRightMaxWindows = 3,
    resizeStep = 80,
    minWidthRatio = 0.18,
    directionThreshold = 20,
    edgeSnapThreshold = 12,
  }

  return harness
end

local function assertHotkey(harness, modifiers, key, message)
  local copy = {}
  for _, modifier in ipairs(modifiers) do
    table.insert(copy, modifier)
  end
  table.sort(copy)

  local callback = harness.hotkeys[table.concat(copy, "+") .. ":" .. key]
  assertTrue(callback, message or ("missing hotkey " .. key))
  return callback
end

test("manual layout float helper calls back without spawning external workspace-manager tasks", function()
  local harness = newHarness()
  local layouts = require("modules.layouts")
  local called = false

  layouts.FloatWindowsForManualLayout({}, function()
    called = true
  end)

  assertTrue(called, "callback should run")
  assertEquals(harness.taskCount, 0, "CLI task count")
end)

test("stack-right applies frames through direct Hammerspoon APIs", function()
  local harness = newHarness()
  harness:addWindow(1, { focused = true, frame = { x = 0, y = 24, w = 400, h = 400 } })
  harness:addWindow(2, { frame = { x = 400, y = 24, w = 300, h = 300 } })
  harness:addWindow(3, { frame = { x = 700, y = 24, w = 300, h = 300 } })
  harness:setVisible({ 1, 2, 3 })

  local layouts = require("modules.layouts")
  local applied, ids = layouts.StackRightLayout()

  assertTrue(applied, "layout should apply")
  assertEquals(#ids, 3, "applied window count")
  assertFrame(harness.frames[1], { x = 0, y = 24, w = 615, h = 776 }, "main window")
  assertFrame(harness.frames[2], { x = 623, y = 24, w = 377, h = 384 }, "top stack window")
  assertFrame(harness.frames[3], { x = 623, y = 416, w = 377, h = 384 }, "bottom stack window")
  assertEquals(harness.taskCount, 0, "CLI task count")
end)

test("columns applies full-screen columns through direct Hammerspoon APIs", function()
  local harness = newHarness()
  harness:addWindow(1, { focused = true, frame = { x = 0, y = 24, w = 400, h = 400 } })
  harness:addWindow(2, { frame = { x = 400, y = 24, w = 300, h = 300 } })
  harness:addWindow(3, { frame = { x = 700, y = 24, w = 300, h = 300 } })
  harness:setVisible({ 1, 2, 3 })

  local layouts = require("modules.layouts")
  local applied, ids = layouts.ColumnsLayout()

  assertTrue(applied, "layout should apply")
  assertEquals(#ids, 3, "applied window count")
  assertFrame(harness.frames[1], { x = 0, y = 0, w = 328, h = 800 }, "first column")
  assertFrame(harness.frames[2], { x = 336, y = 0, w = 328, h = 800 }, "second column")
  assertFrame(harness.frames[3], { x = 672, y = 0, w = 328, h = 800 }, "third column")
  assertEquals(harness.taskCount, 0, "CLI task count")
end)

test("center-main applies centered primary and stacked side windows directly", function()
  local harness = newHarness()
  harness:addWindow(1, { focused = true, frame = { x = 100, y = 24, w = 400, h = 400 } })
  harness:addWindow(2, { frame = { x = 0, y = 24, w = 300, h = 300 } })
  harness:addWindow(3, { frame = { x = 500, y = 24, w = 300, h = 300 } })
  harness:addWindow(4, { frame = { x = 700, y = 24, w = 300, h = 300 } })
  harness:setVisible({ 1, 2, 3, 4 })

  local layouts = require("modules.layouts")
  local applied, ids = layouts.CenterMainLayout()

  assertTrue(applied, "layout should apply")
  assertEquals(#ids, 4, "applied window count")
  assertFrame(harness.frames[1], { x = 175, y = 0, w = 650, h = 800 }, "main window")
  assertFrame(harness.frames[2], { x = 0, y = 0, w = 167, h = 396 }, "left top window")
  assertFrame(harness.frames[3], { x = 833, y = 0, w = 167, h = 800 }, "right window")
  assertFrame(harness.frames[4], { x = 0, y = 404, w = 167, h = 396 }, "left bottom window")
  assertEquals(harness.taskCount, 0, "CLI task count")
end)

test("spanish character shortcuts only type inside Ghostty", function()
  local harness = newHarness()

  require("modules.hotkeys")

  assertHotkey(harness, { "ctrl", "alt" }, "n", "Ctrl+Alt+N should be bound")()
  assertHotkey(harness, { "ctrl", "alt", "shift" }, "n", "Ctrl+Alt+Shift+N should be bound")()

  assertEquals(#harness.typedText, 2, "Ghostty typed text count")
  assertEquals(harness.typedText[1], "ñ", "lowercase enye")
  assertEquals(harness.typedText[2], "Ñ", "uppercase enye")

  harness.activeAppName = "Safari"
  harness.activeAppBundleId = "com.apple.Safari"

  assertHotkey(harness, { "ctrl", "alt" }, "n", "Ctrl+Alt+N should remain bound")()

  assertEquals(#harness.typedText, 2, "non-Ghostty apps should be ignored")
end)

test("resize center and maximize use direct visible-frame geometry", function()
  local harness = newHarness()
  harness:addWindow(1, { focused = true, frame = { x = 100, y = 100, w = 500, h = 500 } })

  local resize = require("modules.resize")
  resize.centerFocusedWindow()

  assertFrame(harness.frames[1], { x = 150, y = 63, w = 700, h = 698 }, "centered window")

  resize.maximizeFocusedWindow()
  assertFrame(harness.frames[1], { x = 0, y = 24, w = 1000, h = 776 }, "maximized window")
  assertEquals(harness.taskCount, 0, "CLI task count")
end)

local passed = 0
for _, entry in ipairs(tests) do
  entry.fn()
  passed = passed + 1
  print("PASS " .. entry.name)
end

print(string.format("%d hammerspoon standalone layout tests passed", passed))
