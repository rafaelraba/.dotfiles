pcall(function()
  hs.ipc.cliInstall()
end)

require("modules.constants")
require("modules.layouts")
require("modules.resize")
local workspaceLayoutRestore = require("modules.workspace_layout_restore")
require("modules.hotkeys")

workspaceLayoutRestore.start()

hs.alert.show("Hammerspoon loaded")
