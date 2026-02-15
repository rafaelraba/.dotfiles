return {
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    opts = {
      global_keymaps = false,
    },
    keys = {
      { "<leader>Rs", desc = "Send request" },
      { "<leader>Ra", desc = "Send all requests" },
      { "<leader>Rb", desc = "Open scratchpad" },
      { "<leader>Ri", desc = "Inspect request" },
      { "<leader>Rc", desc = "Copy as cURL" },
      { "<leader>Re", desc = "Select environment" },
      { "<leader>Rn", desc = "Jump to next request" },
      { "<leader>Rp", desc = "Jump to previous request" },
      { "<leader>Rt", desc = "Toggle response body/headers" },
    },
  },
}
