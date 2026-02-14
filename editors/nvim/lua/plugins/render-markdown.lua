return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    ft = { "markdown" },
    opts = {},
  },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && npm install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      vim.g.mkdp_page_title = "${name}"
      vim.g.mkdp_preview_options = {
        mermaid = { theme = "default" },
      }
    end,
    keys = {
      {
        "<leader>mp",
        function()
          local file = vim.fn.expand("%:p")
          vim.fn.jobstart(
            { "node", vim.fn.expand("~/.config/nvim/md-preview/server.js"), file },
            { detach = true }
          )
          vim.notify("Markdown preview started", vim.log.levels.INFO)
        end,
        ft = "markdown",
        desc = "Markdown Preview (Browser)",
      },
    },
  },
}
