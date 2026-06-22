local constants = require("modules.constants")
local resize = require("modules.resize")

local hyper = constants.hyper

hs.hotkey.bind(hyper, "=", function()
  resize.resizeFocusedWindow(constants.resizeStep)
end)

hs.hotkey.bind(hyper, "-", function()
  resize.resizeFocusedWindow(-constants.resizeStep)
end)

return {}
