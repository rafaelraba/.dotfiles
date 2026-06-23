local constants = require("modules.constants")
local layouts = require("modules.layouts")

local M = {}

local schemaVersion = 1
local knownLayouts = {
  ["stack-right"] = true,
  ["center-main"] = true,
  columns = true,
}

local statePath = constants.workspaceLayoutStatePath
local autoRestore = constants.workspaceLayoutAutoRestore == true
local pollInterval = constants.workspaceLayoutPollInterval
local restoreDebounce = constants.workspaceLayoutRestoreDebounce

local currentWorkspace = nil
local generation = 0
local pollTimer = nil
local restoreTimer = nil
local restoring = false
local resolvedAerospaceCli = nil
local workspaceQueryInFlight = false
local workspaceQueryCallbacks = {}
local workspaceQueryTask = nil
local workspaceQueryTimer = nil
local workspaceQueryToken = 0

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function executableExists(command)
  local attributes = hs.fs.attributes(command)
  return attributes and attributes.mode == "file"
end

local function executableOnPath(command)
  if command:find("/", 1, true) then
    return executableExists(command) and command or nil
  end

  local path = os.getenv("PATH") or ""
  for directory in path:gmatch("([^:]+)") do
    local candidate = directory .. "/" .. command
    if executableExists(candidate) then
      return candidate
    end
  end

  return nil
end

local function aerospaceCli()
  if resolvedAerospaceCli then
    return resolvedAerospaceCli
  end

  for _, candidate in ipairs(constants.aerospaceCliCandidates) do
    local executable = candidate and executableOnPath(candidate)
    if executable then
      resolvedAerospaceCli = executable
      return resolvedAerospaceCli
    end
  end

  return nil
end

local function ensureStateDirectory()
  local dir = statePath:match("^(.+)/[^/]+$")
  if dir then
    hs.execute("mkdir -p " .. shellQuote(dir), false)
  end
end

local function loadState()
  local ok, data = pcall(hs.json.read, statePath)
  if not ok then
    data = nil
  end

  if type(data) ~= "table" or data.schemaVersion ~= schemaVersion or type(data.workspaces) ~= "table" then
    return {
      schemaVersion = schemaVersion,
      workspaces = {},
    }
  end

  return data
end

local function saveState(state)
  ensureStateDirectory()
  local ok, result = pcall(hs.json.write, state, statePath, true, true)
  if not ok or result == false then
    hs.printf("Failed to write workspace layout state to %s: %s", statePath, tostring(result))
    return false
  end

  return true
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function completeWorkspaceQuery(workspace, token)
  if token and token ~= workspaceQueryToken then
    return
  end

  if workspaceQueryTimer then
    workspaceQueryTimer:stop()
    workspaceQueryTimer = nil
  end

  workspaceQueryTask = nil
  workspaceQueryInFlight = false

  local callbacks = workspaceQueryCallbacks
  workspaceQueryCallbacks = {}
  for _, callback in ipairs(callbacks) do
    callback(workspace)
  end
end

local function focusedWorkspaceAsync(callback)
  table.insert(workspaceQueryCallbacks, callback)

  if workspaceQueryInFlight then
    return
  end

  local cli = aerospaceCli()
  if not cli then
    completeWorkspaceQuery(nil)
    return
  end

  workspaceQueryInFlight = true
  workspaceQueryToken = workspaceQueryToken + 1
  local token = workspaceQueryToken
  workspaceQueryTask = hs.task.new(cli, function(exitCode, output, stderr)
    if exitCode ~= 0 then
      hs.printf("AeroSpace focused workspace query failed: exit=%s %s", tostring(exitCode), tostring(stderr or ""))
      completeWorkspaceQuery(nil, token)
      return
    end

    local workspace = trim(output)
    if workspace == "" then
      completeWorkspaceQuery(nil, token)
      return
    end

    completeWorkspaceQuery(workspace, token)
  end, { "list-workspaces", "--focused" })

  if not workspaceQueryTask then
    hs.printf("AeroSpace focused workspace query task could not be created")
    completeWorkspaceQuery(nil, token)
    return
  end

  workspaceQueryTimer = hs.timer.doAfter(constants.aerospaceCliTimeout, function()
    if workspaceQueryTask then
      workspaceQueryTask:terminate()
    end
    hs.printf("AeroSpace focused workspace query timed out")
    completeWorkspaceQuery(nil, token)
  end)

  if not workspaceQueryTask:start() then
    hs.printf("AeroSpace focused workspace query could not start")
    completeWorkspaceQuery(nil, token)
  end
end

local function contains(ids, candidate)
  for _, id in ipairs(ids) do
    if id == candidate then
      return true
    end
  end

  return false
end

local function orderedWindowIds(savedWindowIds)
  local ids = {}
  local visibleIds = layouts.WindowIdsOnCurrentScreen()
  local visibleSet = {}

  for _, windowId in ipairs(visibleIds) do
    visibleSet[windowId] = true
  end

  if type(savedWindowIds) == "table" then
    for _, windowId in ipairs(savedWindowIds) do
      if visibleSet[windowId] then
        table.insert(ids, windowId)
      end
    end
  end

  for _, windowId in ipairs(visibleIds) do
    if not contains(ids, windowId) then
      table.insert(ids, windowId)
    end
  end

  return ids
end

local function applySavedLayout(record, options)
  options = options or {}

  if type(record) ~= "table" or not knownLayouts[record.layout] then
    return false
  end

  local windowIds = orderedWindowIds(record.windowIds)
  if #windowIds < 2 then
    return false
  end

  if record.layout == "stack-right" then
    return layouts.StackRightLayoutForIds(windowIds, { showAlert = false, onApplied = options.onApplied })
  end

  if record.layout == "columns" then
    return layouts.ColumnsLayoutForIds(windowIds, { showAlert = false, onApplied = options.onApplied })
  end

  if record.layout == "center-main" then
    return layouts.CenterMainLayoutForIds(windowIds, { showAlert = false, onApplied = options.onApplied })
  end

  return false
end

local function restoreWorkspace(workspace, expectedGeneration)
  if expectedGeneration ~= generation then
    return
  end

  focusedWorkspaceAsync(function(focused)
    if expectedGeneration ~= generation or focused ~= workspace then
      return
    end

    local state = loadState()
    local record = state.workspaces[workspace]
    if not record then
      return
    end

    restoring = true
    local ok, applied = pcall(function()
      return applySavedLayout(record, {
        onApplied = function()
          restoring = false
        end,
      })
    end)
    if not ok or not applied then
      restoring = false
    end
  end)
end

local function scheduleRestore(workspace)
  if restoreTimer then
    restoreTimer:stop()
  end

  local expectedGeneration = generation
  restoreTimer = hs.timer.doAfter(restoreDebounce, function()
    restoreWorkspace(workspace, expectedGeneration)
  end)
end

local function poll()
  focusedWorkspaceAsync(function(workspace)
    if not workspace or workspace == currentWorkspace then
      return
    end

    currentWorkspace = workspace
    generation = generation + 1
    if autoRestore then
      scheduleRestore(workspace)
    end
  end)
end

function M.saveCurrentWorkspaceLayout(layoutName, windowIds)
  if restoring or not knownLayouts[layoutName] then
    return false
  end

  local workspace = currentWorkspace
  if not workspace then
    return false
  end

  local state = loadState()
  state.workspaces[workspace] = {
    layout = layoutName,
    windowIds = windowIds or {},
    updatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  return saveState(state)
end

function M.start()
  if pollTimer then
    return
  end

  pollTimer = hs.timer.doEvery(pollInterval, poll)
  poll()
end

function M.status()
  return {
    running = pollTimer ~= nil,
    currentWorkspace = currentWorkspace,
    generation = generation,
    restoring = restoring,
    autoRestore = autoRestore,
    workspaceQueryInFlight = workspaceQueryInFlight,
    statePath = statePath,
  }
end

function M.isRestoring()
  return restoring
end

M._test = {
  aerospaceCli = aerospaceCli,
  executableOnPath = executableOnPath,
}

return M
