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

local function assertFalse(value, message)
  if value then
    error(message or "expected false", 2)
  end
end

local function resetModules()
  package.loaded["modules.workspace_layout_restore"] = nil
  package.loaded["modules.layouts"] = nil
  package.loaded["modules.resize"] = nil
  package.loaded["modules.constants"] = nil
end

local function newHarness(options)
  options = options or {}
  resetModules()
  local productionConstants = require("modules.constants")
  local workspaceLayoutAutoRestore = productionConstants.workspaceLayoutAutoRestore
  if options.workspaceLayoutAutoRestore ~= nil then
    workspaceLayoutAutoRestore = options.workspaceLayoutAutoRestore
  end

  local harness = {
    afterTimers = {},
    everyTimers = {},
    tasks = {},
    logs = {},
    writes = {},
    frames = {},
    windows = {},
    visibleWindowIds = {},
    writeResult = true,
    state = options.state or { schemaVersion = 1, workspaces = {} },
  }

  local mainScreen = {
    frame = function()
      return { x = 0, y = 0, w = 1000, h = 800 }
    end,
  }

  if options.mainScreenVisibleFrame ~= false then
    mainScreen.visibleFrame = function()
      return { x = 0, y = 24, w = 1000, h = 776 }
    end
  end

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
    }
    self.windows[id] = window
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

  function harness:fireAfter(index)
    local timer = self.afterTimers[index]
    assertTrue(timer, "missing after timer " .. tostring(index))
    assertFalse(timer.stopped, "after timer already stopped " .. tostring(index))
    timer.fn()
  end

  function harness:completeTask(index, exitCode, output, stderr)
    local task = self.tasks[index]
    assertTrue(task, "missing task " .. tostring(index))
    task.callback(exitCode or 0, output or "", stderr)
  end

  hs = {
    fs = {
      attributes = function(path)
        if path:match("/aerospace$") then
          return { mode = "file" }
        end
        return nil
      end,
    },
    json = {
      read = function()
        return harness.state
      end,
      write = function(state, path)
        table.insert(harness.writes, { state = state, path = path })
        return harness.writeResult
      end,
    },
    execute = function()
      return true
    end,
    printf = function(format, ...)
      table.insert(harness.logs, string.format(format, ...))
    end,
    timer = {
      absoluteTime = function()
        harness.absoluteCounter = (harness.absoluteCounter or 0) + 1
        return harness.absoluteCounter
      end,
      doAfter = function(_, fn)
        local timer = {
          fn = fn,
          stopped = false,
          stop = function(self)
            self.stopped = true
          end,
        }
        table.insert(harness.afterTimers, timer)
        return timer
      end,
      doEvery = function(_, fn)
        local timer = {
          fn = fn,
          stopped = false,
          stop = function(self)
            self.stopped = true
          end,
        }
        table.insert(harness.everyTimers, timer)
        return timer
      end,
    },
    task = {
      new = function(command, callback, args)
        local task = {
          command = command,
          callback = callback,
          args = args,
          terminated = false,
          started = false,
          start = function(self)
            self.started = true
            return options.taskStartResult ~= false
          end,
          terminate = function(self)
            self.terminated = true
          end,
        }
        table.insert(harness.tasks, task)
        return options.taskFactoryResult == false and nil or task
      end,
    },
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
    alert = {
      show = function() end,
    },
  }

  package.loaded["modules.constants"] = {
    gap = 8,
    leftRatio = 0.62,
    centerMainRatio = 0.65,
    stackRightMaxWindows = 3,
    workspaceLayoutAutoRestore = workspaceLayoutAutoRestore,
    workspaceLayoutPollInterval = 0.5,
    workspaceLayoutRestoreDebounce = 0.3,
    aerospaceCliTimeout = 1,
    workspaceLayoutStatePath = "/tmp/workspace-layout-restore-test/state.json",
    aerospaceCliCandidates = { "aerospace" },
  }

  return harness
end

test("workspace polling uses async task, timeout, and a single in-flight query", function()
  local harness = newHarness()
  local restore = require("modules.workspace_layout_restore")

  restore.start()
  assertEquals(#harness.tasks, 1, "initial poll starts one task")
  assertTrue(restore.status().workspaceQueryInFlight, "query is in flight")

  harness.everyTimers[1].fn()
  assertEquals(#harness.tasks, 1, "second poll reuses in-flight task")

  harness:fireAfter(1)
  assertTrue(harness.tasks[1].terminated, "timeout terminates task")
  assertFalse(restore.status().workspaceQueryInFlight, "timeout clears in-flight state")
end)

test("workspace polling does not auto-restore by production default", function()
  local harness = newHarness({
    state = {
      schemaVersion = 1,
      workspaces = {
        dev = { layout = "columns", windowIds = { 901, 902 } },
      },
    },
  })
  harness:addWindow(901)
  harness:addWindow(902)
  harness:setVisible({ 901, 902 })
  harness.focusedWindowId = 901

  local restore = require("modules.workspace_layout_restore")
  restore.start()
  harness:completeTask(1, 0, "dev\n")

  assertEquals(restore.status().currentWorkspace, "dev", "current workspace is still tracked")
  assertFalse(restore.status().autoRestore, "auto-restore is disabled")
  assertEquals(#harness.afterTimers, 1, "only the workspace query timeout timer exists")
  assertEquals(harness.frames[901], nil, "saved layout is not auto-applied")
  assertEquals(harness.frames[902], nil, "saved layout is not auto-applied")
end)

test("restore uses only current visible current-screen windows and ignores stale IDs", function()
  local harness = newHarness({
    workspaceLayoutAutoRestore = true,
    state = {
      schemaVersion = 1,
      workspaces = {
        dev = { layout = "stack-right", windowIds = { 101, 999, 102 } },
      },
    },
  })
  harness:addWindow(101)
  harness:addWindow(102)
  harness:addWindow(999, { screen = "other" })
  harness:setVisible({ 101, 102 })
  harness.focusedWindowId = 101

  local restore = require("modules.workspace_layout_restore")
  restore.start()
  harness:completeTask(1, 0, "dev\n")
  harness:fireAfter(2)
  harness:completeTask(2, 0, "dev\n")
  harness:completeTask(3, 0, "")
  harness:completeTask(4, 0, "")

  assertTrue(harness.frames[101] ~= nil, "visible window 101 is laid out")
  assertTrue(harness.frames[102] ~= nil, "visible window 102 is laid out")
  assertEquals(harness.frames[999], nil, "stale non-visible window is ignored")
end)

test("restore targets focused non-main screen instead of main screen", function()
  local harness = newHarness({
    workspaceLayoutAutoRestore = true,
    state = {
      schemaVersion = 1,
      workspaces = {
        dev = { layout = "columns", windowIds = { 701, 702, 703, 704 } },
      },
    },
  })
  harness:addWindow(701)
  harness:addWindow(702)
  harness:addWindow(703, { screen = "other" })
  harness:addWindow(704, { screen = "other" })
  harness:setVisible({ 701, 702, 703, 704 })
  harness.focusedWindowId = 703

  local restore = require("modules.workspace_layout_restore")
  restore.start()
  harness:completeTask(1, 0, "dev\n")
  harness:fireAfter(2)
  harness:completeTask(2, 0, "dev\n")
  harness:completeTask(3, 0, "")
  harness:completeTask(4, 0, "")

  assertEquals(harness.frames[701], nil, "main-screen window 701 is ignored")
  assertEquals(harness.frames[702], nil, "main-screen window 702 is ignored")
  assertEquals(harness.frames[703].x, 2000, "focused-screen first column starts on non-main screen")
  assertEquals(harness.frames[704].x, 2504, "focused-screen second column stays on non-main screen")
end)

test("manual layout window IDs use focused non-main screen", function()
  local harness = newHarness()
  harness:addWindow(801)
  harness:addWindow(802)
  harness:addWindow(803, { screen = "other" })
  harness:addWindow(804, { screen = "other" })
  harness:setVisible({ 801, 802, 803, 804 })
  harness.focusedWindowId = 803
  local layouts = require("modules.layouts")

  local ids = layouts.WindowIdsOnCurrentScreen()

  assertEquals(ids[1], 803, "focused non-main window is first")
  assertEquals(ids[2], 804, "other non-main window is included")
  assertEquals(#ids, 2, "main-screen windows are excluded")
end)

test("restore save suppression remains until async layout completion", function()
  local harness = newHarness({
    workspaceLayoutAutoRestore = true,
    state = {
      schemaVersion = 1,
      workspaces = {
        dev = { layout = "columns", windowIds = { 201, 202 } },
      },
    },
  })
  harness:addWindow(201)
  harness:addWindow(202)
  harness:setVisible({ 201, 202 })
  harness.focusedWindowId = 201

  local restore = require("modules.workspace_layout_restore")
  restore.start()
  harness:completeTask(1, 0, "dev\n")
  harness:fireAfter(2)
  harness:completeTask(2, 0, "dev\n")

  assertTrue(restore.isRestoring(), "restore suppression is active while float tasks run")
  assertFalse(restore.saveCurrentWorkspaceLayout("columns", { 201, 202 }), "save is suppressed during async restore")

  harness:completeTask(3, 0, "")
  assertTrue(restore.isRestoring(), "restore remains active until all float tasks finish")
  harness:completeTask(4, 0, "")
  assertFalse(restore.isRestoring(), "restore suppression clears after async layout completion")
end)

test("center-main restore lays focused window in the large center column", function()
  local harness = newHarness({
    workspaceLayoutAutoRestore = true,
    state = {
      schemaVersion = 1,
      workspaces = {
        dev = { layout = "center-main", windowIds = { 501, 502, 503, 504 } },
      },
    },
  })
  harness:addWindow(501)
  harness:addWindow(502)
  harness:addWindow(503)
  harness:addWindow(504)
  harness:setVisible({ 501, 502, 503, 504 })
  harness.focusedWindowId = 501

  local restore = require("modules.workspace_layout_restore")
  restore.start()
  harness:completeTask(1, 0, "dev\n")
  harness:fireAfter(2)
  harness:completeTask(2, 0, "dev\n")
  harness:completeTask(3, 0, "")
  harness:completeTask(4, 0, "")
  harness:completeTask(5, 0, "")
  harness:completeTask(6, 0, "")

  assertEquals(harness.frames[501].x, 175, "main x is centered after left side and gap")
  assertEquals(harness.frames[501].w, 650, "main uses configured width ratio")
  assertEquals(harness.frames[502].x, 0, "first extra is on the left")
  assertEquals(harness.frames[502].h, 396, "left extras stack vertically")
  assertEquals(harness.frames[503].x, 833, "second extra is on the right")
  assertEquals(harness.frames[503].h, 800, "single right extra uses full height")
  assertEquals(harness.frames[504].x, 0, "third extra returns to the left")
  assertEquals(harness.frames[504].y, 404, "second left row is stacked below the first")
end)

test("center-main with two windows keeps focused main centered and secondary on the left", function()
  local harness = newHarness()
  harness:addWindow(601)
  harness:addWindow(602)
  harness:setVisible({ 601, 602 })
  harness.focusedWindowId = 601
  local layouts = require("modules.layouts")

  local applied = layouts.CenterMainLayoutForIds({ 601, 602 }, { showAlert = false })
  assertTrue(applied, "center-main starts")
  harness:completeTask(1, 0, "")
  harness:completeTask(2, 0, "")

  assertEquals(harness.frames[601].x, 175, "main remains centered")
  assertEquals(harness.frames[601].w, 650, "main width uses center-main ratio")
  assertEquals(harness.frames[602].x, 0, "secondary uses left side")
  assertEquals(harness.frames[602].h, 800, "secondary uses full side height")
end)

test("JSON write failure makes save return false and log", function()
  local harness = newHarness()
  harness.writeResult = false
  local restore = require("modules.workspace_layout_restore")

  restore.start()
  harness:completeTask(1, 0, "dev\n")

  assertFalse(restore.saveCurrentWorkspaceLayout("columns", { 1, 2 }), "save returns false when json.write fails")
  assertTrue((harness.logs[#harness.logs] or ""):match("Failed to write workspace layout state") ~= nil, "write failure is logged")
end)

test("async float timeout still invokes completion", function()
  local harness = newHarness()
  harness:addWindow(301)
  harness:addWindow(302)
  harness:setVisible({ 301, 302 })
  harness.focusedWindowId = 301
  local layouts = require("modules.layouts")
  local completed = false

  local applied = layouts.ColumnsLayoutForIds({ 301, 302 }, {
    showAlert = false,
    onApplied = function()
      completed = true
    end,
  })

  assertTrue(applied, "layout starts")
  assertFalse(completed, "completion waits for async float")
  harness:fireAfter(1)
  harness:fireAfter(2)

  assertTrue(completed, "completion runs after float timeouts")
  assertTrue(harness.frames[301] ~= nil, "frames applied after timeout cleanup")
  assertTrue(harness.frames[302] ~= nil, "frames applied after timeout cleanup")
end)

test("center focused window floats before applying frame", function()
  local harness = newHarness()
  harness:addWindow(401, { frame = { x = 0, y = 24, w = 400, h = 300 } })
  harness.focusedWindowId = 401
  local resize = require("modules.resize")

  resize.centerFocusedWindow()

  assertEquals(#harness.tasks, 1, "center starts one float task")
  assertEquals(harness.tasks[1].args[1], "layout", "center uses aerospace layout command")
  assertEquals(harness.tasks[1].args[3], "401", "center floats the focused window")
  assertEquals(harness.frames[401], nil, "frame waits for async float completion")

  harness:completeTask(1, 0, "")
  assertEquals(harness.frames[401].x, 150, "centered x is applied")
  assertEquals(harness.frames[401].y, 63, "centered y is applied")
  assertEquals(harness.frames[401].w, 700, "width uses 70 percent of visible width")
  assertEquals(harness.frames[401].h, 698, "height uses 90 percent of visible height")
end)

test("maximize focused window floats before applying visible frame", function()
  local harness = newHarness()
  harness:addWindow(402, { frame = { x = 100, y = 100, w = 400, h = 300 } })
  harness.focusedWindowId = 402
  local resize = require("modules.resize")

  resize.maximizeFocusedWindow()

  assertEquals(#harness.tasks, 1, "maximize starts one float task")
  assertEquals(harness.tasks[1].args[1], "layout", "maximize uses aerospace layout command")
  assertEquals(harness.tasks[1].args[3], "402", "maximize floats the focused window")
  assertEquals(harness.frames[402], nil, "frame waits for async float completion")

  harness:completeTask(1, 0, "")
  assertEquals(harness.frames[402].x, 0, "visible frame x is applied")
  assertEquals(harness.frames[402].y, 24, "visible frame y is applied")
  assertEquals(harness.frames[402].w, 1000, "visible frame width is applied")
  assertEquals(harness.frames[402].h, 776, "visible frame height is applied")
end)

test("maximize focused window falls back to screen frame without visibleFrame", function()
  local harness = newHarness({ mainScreenVisibleFrame = false })
  harness:addWindow(403, { frame = { x = 100, y = 100, w = 400, h = 300 } })
  harness.focusedWindowId = 403
  local resize = require("modules.resize")

  resize.maximizeFocusedWindow()
  harness:completeTask(1, 0, "")

  assertEquals(harness.frames[403].x, 0, "screen frame x fallback is applied")
  assertEquals(harness.frames[403].y, 0, "screen frame y fallback is applied")
  assertEquals(harness.frames[403].w, 1000, "screen frame width fallback is applied")
  assertEquals(harness.frames[403].h, 800, "screen frame height fallback is applied")
end)

test("aerospace PATH candidate resolves without spawning a process", function()
  local harness = newHarness()
  local restore = require("modules.workspace_layout_restore")
  local layouts = require("modules.layouts")

  assertTrue(restore._test.aerospaceCli():match("/aerospace$") ~= nil, "restore module resolves PATH candidate")
  assertTrue(layouts._test.aerospaceCli():match("/aerospace$") ~= nil, "layouts module resolves PATH candidate")
  assertEquals(#harness.tasks, 0, "PATH lookup does not create hs.task processes")
end)

local failures = 0
for _, case in ipairs(tests) do
  local ok, err = pcall(case.fn)
  if ok then
    print("ok - " .. case.name)
  else
    failures = failures + 1
    io.stderr:write("not ok - " .. case.name .. "\n" .. tostring(err) .. "\n")
  end
end

if failures > 0 then
  os.exit(1)
end
