local M = {}

function M.start()
  return false
end

function M.stop()
  return false
end

function M.saveCurrentWorkspaceLayout()
  return false
end

function M.clearCurrentWorkspaceLayout()
  return false
end

function M.status()
  return {
    enabled = false,
    deprecated = true,
    reason = "Workspace layout restore is disabled; Hammerspoon runs standalone on native macOS Spaces.",
  }
end

return M
