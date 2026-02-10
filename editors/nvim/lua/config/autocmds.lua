-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- ---------------------------------------------------------------------------
-- Autoread: real-time reload of files changed externally (Claude Code, git…)
-- Combines fs_event watchers (instant) + FocusGained/checktime (fallback).
-- Toggle with <leader>ua
-- ---------------------------------------------------------------------------

vim.opt.autoread = true

local augroup = vim.api.nvim_create_augroup("autoread_external", { clear = true })
local watchers = {} ---@type table<number, uv.uv_fs_event_t>
local enabled = true

-- Fallback: checktime on focus / cursor idle
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = augroup,
  callback = function(args)
    if not enabled or vim.bo[args.buf].buftype ~= "" then
      return
    end
    vim.cmd.checktime()
  end,
  desc = "Autoread: checktime fallback",
})

-- Notify on reload
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = augroup,
  callback = function()
    vim.notify("File reloaded from disk", vim.log.levels.INFO)
  end,
  desc = "Autoread: notify on reload",
})

-- Real-time: fs_event watcher per buffer
local function watch_buffer(buf)
  if watchers[buf] then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  handle:start(path, {}, vim.schedule_wrap(function(err)
    if err or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if not enabled then
      return
    end
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.checktime()
    end)
  end))

  watchers[buf] = handle

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    once = true,
    callback = function()
      if watchers[buf] then
        watchers[buf]:stop()
        watchers[buf]:close()
        watchers[buf] = nil
      end
    end,
  })
end

-- Attach watcher when a file is read
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  callback = function(args)
    watch_buffer(args.buf)
  end,
  desc = "Autoread: attach fs_event watcher",
})

-- Watch buffers already open at startup
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    watch_buffer(buf)
  end
end

-- Toggle
vim.keymap.set("n", "<leader>ua", function()
  enabled = not enabled
  vim.notify("Autoread " .. (enabled and "ON" or "OFF"), vim.log.levels.INFO)
end, { desc = "Toggle Autoread" })
