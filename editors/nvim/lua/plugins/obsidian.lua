return {
  {
    "obsidian-nvim/obsidian.nvim",
    version = "*",
    cmd = "Obsidian",
    ft = "markdown",
    keys = {
      { "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Obsidian Backlinks" },
      { "<leader>oc", "<cmd>Obsidian check<cr>", desc = "Obsidian Check" },
      { "<leader>of", "<cmd>Obsidian follow_link<cr>", desc = "Obsidian Follow Link" },
      { "<leader>on", "<cmd>Obsidian new<cr>", desc = "Obsidian New Note" },
      { "<leader>oq", "<cmd>Obsidian quick_switch<cr>", desc = "Obsidian Quick Switch" },
      { "<leader>os", "<cmd>Obsidian search<cr>", desc = "Obsidian Search" },
      { "<leader>ot", "<cmd>Obsidian today<cr>", desc = "Obsidian Today" },
    },
    ---@module 'obsidian'
    ---@type obsidian.config
    opts = {
      legacy_commands = false,
      workspaces = {
        {
          name = "brain",
          path = "~/Documents/Brain",
        },
      },
      picker = {
        name = "snacks.picker",
      },
      -- Keep render-markdown.nvim as the visual renderer. Obsidian.nvim should
      -- provide vault commands, navigation, search, backlinks, and completion;
      -- it should not change the Markdown reading style.
      ui = {
        enable = false,
      },
      footer = {
        enabled = false,
      },
      statusline = {
        enabled = false,
      },
    },
  },
}
