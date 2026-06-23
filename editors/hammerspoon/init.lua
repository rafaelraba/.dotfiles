pcall(function()
  hs.ipc.cliInstall()
end)

require("modules.constants")
require("modules.layouts")
require("modules.resize")
require("modules.hotkeys")

hs.alert.show("Hammerspoon loaded")
