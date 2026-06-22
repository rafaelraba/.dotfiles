return {
  {
    "sainnhe/gruvbox-material",
    priority = 1000,
    init = function()
      vim.g.gruvbox_material_background = "hard"
      vim.g.gruvbox_material_foreground = "material"
      vim.g.gruvbox_material_enable_italic = true
      vim.g.gruvbox_material_transparent_background = 0

      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "gruvbox-material",
        callback = function()
          local folder = "#d8a657"
          local text = "#d4be98"

          vim.api.nvim_set_hl(0, "Directory", { fg = folder })
          vim.api.nvim_set_hl(0, "NeoTreeDirectoryIcon", { fg = folder })
          vim.api.nvim_set_hl(0, "NeoTreeDirectoryName", { fg = text })
          vim.api.nvim_set_hl(0, "NeoTreeRootName", { fg = folder, bold = true })
          vim.api.nvim_set_hl(0, "SnacksPickerDirectory", { fg = text })
          vim.api.nvim_set_hl(0, "SnacksPickerDir", { fg = text })
          vim.api.nvim_set_hl(0, "LazyGitNormal", { fg = "#d4be98", bg = "#1d2021" })
          vim.api.nvim_set_hl(0, "LazyGitBorder", { fg = "#d8a657", bg = "#1d2021" })
          vim.api.nvim_set_hl(0, "LazyGitWinBar", { fg = "#d8a657", bg = "#1d2021", bold = true })
        end,
      })
    end,
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha", -- latte, frappe, macchiato, mocha
      transparent_background = true,
      term_colors = true,
      integrations = {
        blink_cmp = true,
        diffview = true,
        gitsigns = true,
        treesitter = true,
        notify = true,
        mini = true,
        native_lsp = {
          enabled = true,
        },
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "gruvbox-material",
    },
  },
}
