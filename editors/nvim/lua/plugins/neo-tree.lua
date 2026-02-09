return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = {
      window = {
        width = 50,
      },
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      explorer = {
        replace_netrw = false,
      },
      picker = {
        sources = {
          explorer = {
            layout = {
              layout = {
                position = "left",
                width = 50,
              },
            },
          },
        },
      },
    },
  },
}
