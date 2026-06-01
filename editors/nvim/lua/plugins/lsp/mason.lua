return {
  -- Mason: gestor de LSP servers, DAP servers, linters y formatters
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        -- LSP Servers
        "jdtls", -- Java
        "gopls", -- Go
        "vtsls", -- JavaScript/TypeScript/React (LazyVim TypeScript extra default)
        "tailwindcss-language-server", -- Tailwind CSS
        "html-lsp", -- HTML
        "css-lsp", -- CSS

        -- Formatters
        "prettier", -- JS/TS/React/CSS/HTML/Tailwind

        -- Linters
        "eslint_d", -- JavaScript/TypeScript
        "golangci-lint", -- Go
      },
    },
  },

  -- Mason-lspconfig: puente entre mason y lspconfig
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
    },
    opts = {
      -- Instalación automática de LSP servers configurados en lspconfig
      automatic_installation = true,
    },
  },
}
