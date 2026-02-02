return {
  -- Configuración adicional de nvim-jdtls (Java LSP)
  -- El extra de LazyVim para Java se importa en lazy.lua
  {
    "mfussenegger/nvim-jdtls",
    opts = {
      -- Configuración del servidor JDTLS
      -- jdtls = {
      --   -- Puedes agregar configuraciones específicas aquí
      --   -- Por ejemplo, para Spring Boot:
      --   settings = {
      --     java = {
      --       configuration = {
      --         runtimes = {
      --           -- Especifica las versiones de Java instaladas
      --           -- {
      --           --   name = "JavaSE-17",
      --           --   path = "/path/to/jdk-17",
      --           -- },
      --         },
      --       },
      --     },
      --   },
      -- },
    },
  },
}
