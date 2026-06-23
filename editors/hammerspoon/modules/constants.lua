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

return M
