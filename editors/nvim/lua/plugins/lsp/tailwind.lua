return {
  -- Configuración adicional de Tailwind LSP
  -- El extra de LazyVim para Tailwind se importa en lazy.lua
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tailwindcss = {
          -- Habilita sugerencias en más tipos de archivo
          filetypes = {
            "html",
            "css",
            "scss",
            "javascript",
            "javascriptreact",
            "typescript",
            "typescriptreact",
            "vue",
          },
          settings = {
            tailwindCSS = {
              experimental = {
                classRegex = {
                  -- Soporta className en template strings
                  { "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
                  { "cx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
                },
              },
            },
          },
        },
      },
    },
  },
}
