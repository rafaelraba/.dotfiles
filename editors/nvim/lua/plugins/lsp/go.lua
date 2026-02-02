return {
  -- Configuración adicional de gopls (Go LSP)
  -- El extra de LazyVim para Go se importa en lazy.lua
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gopls = {
          -- Configuraciones adicionales para gopls
          settings = {
            gopls = {
              gofumpt = true, -- Usa gofumpt para formatear (más estricto que gofmt)
              analyses = {
                unusedparams = true,
                shadow = true,
              },
              staticcheck = true,
            },
          },
        },
      },
    },
  },
}
