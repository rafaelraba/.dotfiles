return {
  {
    "mfussenegger/nvim-jdtls",
    opts = {
      settings = {
        java = {
          imports = {
            gradle = { wrapper = { checksums = {} } },
            order = { "java", "javax", "com", "org" },
            favoriteStaticMembers = {
              "org.junit.jupiter.api.Assertions.*",
              "org.mockito.Mockito.*",
              "org.mockito.ArgumentMatchers.*",
              "org.mockito.BDDMockito.*",
              "org.hamcrest.Matchers.*",
              "org.hamcrest.CoreMatchers.*",
              "org.assertj.core.api.Assertions.*",
            },
            starThreshold = 9999,
            staticStarThreshold = 9999,
          },
          completion = {
            favoriteStaticMembers = {
              "org.junit.jupiter.api.Assertions.*",
              "org.mockito.Mockito.*",
              "org.mockito.ArgumentMatchers.*",
              "org.mockito.BDDMockito.*",
              "org.hamcrest.Matchers.*",
              "org.hamcrest.CoreMatchers.*",
              "org.assertj.core.api.Assertions.*",
            },
          },
          sources = {
            organizeImports = {
              starThreshold = 9999,
              staticStarThreshold = 9999,
            },
          },
        },
      },
      jdtls = function(config)
        table.insert(config.cmd, "--jvm-arg=-Xmx4G")
        return config
      end,
    },
  },
}
