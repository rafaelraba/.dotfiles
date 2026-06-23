return {
  "pwntester/octo.nvim",
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>gpl", "<cmd>Octo pr list<cr>", desc = "GitHub PRs: List" },
    {
      "<leader>gps",
      function()
        require("octo.utils").create_base_search_command({ include_current_repo = true })
      end,
      desc = "GitHub PRs: Search Current Repo",
    },
    { "<leader>gpS", "<cmd>Octo search is:pr<cr>", desc = "GitHub PRs: Search" },
    { "<leader>gpo", "<cmd>Octo pr browser<cr>", desc = "GitHub PR: Open in Browser" },
    { "<leader>gpc", "<cmd>Octo pr checkout<cr>", desc = "GitHub PR: Checkout" },
    { "<leader>gpd", "<cmd>Octo pr diff<cr>", desc = "GitHub PR: Diff" },
    { "<leader>gpf", "<cmd>Octo pr changes<cr>", desc = "GitHub PR: Changed Files" },
    { "<leader>gpr", "<cmd>Octo review start<cr>", desc = "GitHub PR Review: Start" },
    { "<leader>gpR", "<cmd>Octo review resume<cr>", desc = "GitHub PR Review: Resume" },
    { "<leader>gpm", "<cmd>Octo review comments<cr>", desc = "GitHub PR Review: Comments" },
    { "<leader>gpx", "<cmd>Octo review submit<cr>", desc = "GitHub PR Review: Submit" },
  },
  opts = {
    picker = "snacks",
    enable_builtin = true,
    default_remote = { "upstream", "origin" },
    default_delete_branch = false,
    use_local_fs = true,
    picker_config = {
      mappings = {
        checkout_pr = { lhs = "<C-o>", desc = "checkout pull request" },
        open_in_browser = { lhs = "<C-b>", desc = "open in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy URL" },
        copy_sha = { lhs = "<C-e>", desc = "copy commit SHA" },
      },
    },
    reviews = {
      auto_show_threads = true,
      focus = "right",
    },
    pull_requests = {
      order_by = {
        field = "UPDATED_AT",
        direction = "DESC",
      },
    },
    file_panel = {
      size = 12,
      icons = true,
    },
  },
}
