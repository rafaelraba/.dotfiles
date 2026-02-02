return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview File History" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview History" },
    { "<leader>gc", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
  },
  opts = {
    enhanced_diff_hl = true,
    use_icons = true,
    view = {
      default = {
        layout = "diff2_vertical", -- Lado a lado vertical
        winbar_info = true,
      },
      file_history = {
        layout = "diff2_vertical",
        winbar_info = true,
      },
    },
    file_panel = {
      listing_style = "list",
      win_config = {
        position = "left",
        width = 35,
      },
    },
  },
}
