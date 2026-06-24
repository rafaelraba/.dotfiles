pcall(function()
  hs.ipc.cliInstall()
end)

require("modules.constants")
require("modules.hotkeys")

hs.alert.show("Hammerspoon loaded")
