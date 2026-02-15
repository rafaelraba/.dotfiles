-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Force diffview.nvim over any other plugin for <leader>gd
vim.keymap.set("n", "<leader>gd", "<cmd>DiffviewOpen<cr>", { desc = "Diffview Open" })

-- Clear test result marks (junit/testng)
vim.keymap.set("n", "<leader>tc", function()
  local bufnr = vim.api.nvim_get_current_buf()
  for _, ns_name in ipairs({ "junit", "testng" }) do
    local ns = vim.api.nvim_create_namespace(ns_name)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    vim.diagnostic.reset(ns, bufnr)
  end
end, { desc = "Clear test marks" })
