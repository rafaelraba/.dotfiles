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
          local script = vim.fn.expand("~/.config/nvim/md-preview/server.js")
          vim.fn.jobstart({ "node", script, file }, {
            detach = true,
            on_stderr = function(_, data)
              if data and data[1] ~= "" then
                vim.schedule(function()
                  vim.notify(table.concat(data, "\n"), vim.log.levels.ERROR)
                end)
              end
            end,
            on_stdout = function(_, data)
              for _, line in ipairs(data) do
                local url = line:match("(http://localhost:%d+)")
                if url then
                  vim.schedule(function()
                    vim.ui.open(url)
                  end)
                end
              end
            end,
          })
          vim.notify("Markdown preview started", vim.log.levels.INFO)
        end,
        ft = "markdown",
        desc = "Markdown Preview (Browser)",
      },
    },
  },
}
