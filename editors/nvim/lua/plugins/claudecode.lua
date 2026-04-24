return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  event = "VeryLazy",
  opts = {
    auto_start = true,
    track_selection = true,
    focus_after_send = false,
  },
  keys = {
    { "<leader>a", "", desc = "+ai/claude" },
    { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude terminal" },
    { "<leader>aS", "<cmd>ClaudeCodeStatus<cr>", desc = "Claude status" },
    { "<leader>aM", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select model" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection" },
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
  },
}
