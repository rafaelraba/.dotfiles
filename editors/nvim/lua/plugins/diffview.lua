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
        layout = "diff2_horizontal",
        winbar_info = true,
      },
      file_history = {
        layout = "diff2_horizontal",
        winbar_info = true,
      },
    },
    file_panel = {
      listing_style = "list",
      win_config = {
        position = "left",
        width = 60,
      },
    },
    hooks = {
      diff_buf_read = function(bufnr)
        vim.opt_local.list = false
        vim.opt_local.wrap = false
        local name = vim.api.nvim_buf_get_name(bufnr)
        local ft = vim.filetype.match({ buf = bufnr, filename = name })
        if ft and ft ~= "" then
          vim.bo[bufnr].filetype = ft
          pcall(vim.treesitter.start, bufnr, ft)
        end
      end,
    },
  },
}
