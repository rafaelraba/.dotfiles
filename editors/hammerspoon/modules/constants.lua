local M = {}

M.hyper = { "cmd", "alt" }

-- Geometry constants shared across layout presets.
M.gap = 8
M.leftRatio = 0.62
M.centerMainRatio = 0.65

-- Resize step in screen points.
M.resizeStep = 80
M.minWidthRatio = 0.18

-- Focus behavior constants.
M.directionThreshold = 20
M.edgeSnapThreshold = 12

-- Layout limits.
M.stackRightMaxWindows = 3

-- Workspace layout restore behavior.
M.workspaceLayoutAutoRestore = false
M.workspaceLayoutPollInterval = 0.20
M.workspaceLayoutRestoreDebounce = 0.10
M.aerospaceCliTimeout = 1.0
M.workspaceLayoutStatePath = os.getenv("HOME") .. "/.cache/dotfiles/wm-layouts/state.json"
M.aerospaceCliCandidates = {}
if os.getenv("AEROSPACE_BIN") then
  table.insert(M.aerospaceCliCandidates, os.getenv("AEROSPACE_BIN"))
end
table.insert(M.aerospaceCliCandidates, "/opt/homebrew/bin/aerospace")
table.insert(M.aerospaceCliCandidates, "/usr/local/bin/aerospace")
table.insert(M.aerospaceCliCandidates, "aerospace")

return M
