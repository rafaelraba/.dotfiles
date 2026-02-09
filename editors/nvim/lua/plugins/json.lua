-- JSON editing experience: folding, node manipulation, live visualization

local function json_fold_suffix(lnum, endLnum)
  local first_line = vim.fn.getline(lnum)
  local opener = first_line:match("[%{%[]%s*$")
  if not opener then return "" end
  local is_object = opener:find("{") ~= nil
  local count, depth = 0, 0
  for i = lnum + 1, endLnum - 1 do
    local line = vim.fn.getline(i)
    for _ in line:gmatch("[%{%[]") do depth = depth + 1 end
    for _ in line:gmatch("[%}%]]") do depth = depth - 1 end
    if depth == 0 then
      if is_object then
        if line:match('^%s*"[^"]+"%s*:') then count = count + 1 end
      else
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not trimmed:match("^[%]%}],?$") then count = count + 1 end
      end
    end
  end
  if is_object then
    return "  { " .. count .. (count == 1 and " key" or " keys") .. " }"
  end
  return "  [ " .. count .. (count == 1 and " item" or " items") .. " ]"
end

local json_viewer = { server_job = nil, port = nil, tmp_dir = nil, update_autocmd = nil, debounce_timer = nil }

local function write_json(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if json_viewer.tmp_dir then
    vim.fn.writefile(lines, json_viewer.tmp_dir .. "/data.json")
  end
end

local function stop_server()
  if json_viewer.debounce_timer then vim.fn.timer_stop(json_viewer.debounce_timer) end
  if json_viewer.update_autocmd then vim.api.nvim_del_autocmd(json_viewer.update_autocmd) end
  if json_viewer.server_job then vim.fn.jobstop(json_viewer.server_job) end
  if json_viewer.tmp_dir then vim.fn.delete(json_viewer.tmp_dir, "rf") end
  json_viewer = { server_job = nil, port = nil, tmp_dir = nil, update_autocmd = nil, debounce_timer = nil }
end

local function ensure_server(buf)
  if json_viewer.server_job then write_json(buf); return end
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  json_viewer.tmp_dir = tmp
  local static = vim.fn.stdpath("config") .. "/static/json-viewer"
  vim.fn.system({ "cp", static .. "/tree.html", tmp .. "/tree.html" })
  vim.fn.system({ "cp", static .. "/graph.html", tmp .. "/graph.html" })
  write_json(buf)
  local port_cmd = 'python3 -c "import socket; s=socket.socket(); s.bind((\'\',0)); print(s.getsockname()[1]); s.close()"'
  json_viewer.port = vim.trim(vim.fn.system(port_cmd))
  json_viewer.server_job = vim.fn.jobstart({
    "python3", "-m", "http.server", json_viewer.port, "--bind", "127.0.0.1", "--directory", tmp,
  }, { detach = true })
  json_viewer.update_autocmd = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      if json_viewer.debounce_timer then vim.fn.timer_stop(json_viewer.debounce_timer) end
      json_viewer.debounce_timer = vim.fn.timer_start(500, function()
        json_viewer.debounce_timer = nil
        vim.schedule(function() write_json(buf) end)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", { once = true, callback = stop_server })
end

local function open_viewer(buf, page)
  ensure_server(buf)
  vim.defer_fn(function()
    vim.ui.open("http://127.0.0.1:" .. json_viewer.port .. "/" .. page)
  end, 200)
end

return {
  -- nvim-ufo: modern folding with virtual text
  {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    event = "BufRead",
    keys = {
      { "zR", function() require("ufo").openAllFolds() end, desc = "Open all folds" },
      { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
      { "zr", function() require("ufo").openFoldsExceptKinds() end, desc = "Open folds except kinds" },
      { "zm", function() require("ufo").closeFoldsWith() end, desc = "Close folds with" },
      { "zp", function() require("ufo").peekFoldedLinesUnderCursor() end, desc = "Peek fold" },
    },
    opts = {
      provider_selector = function(_, filetype, _)
        if filetype == "json" or filetype == "jsonc" then
          return { "treesitter", "indent" }
        end
        return { "lsp", "indent" }
      end,
      close_fold_kinds_for_ft = {
        json = { "array", "object" },
      },
      fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
        local newVirtText = {}
        local suffix_text = ""
        local ft = vim.bo.filetype

        -- For JSON files, show key/item count
        if ft == "json" or ft == "jsonc" then
          suffix_text = json_fold_suffix(lnum, endLnum)
        end

        local foldedLines = endLnum - lnum
        local suffix = suffix_text .. ("  %d lines "):format(foldedLines)
        local sufWidth = vim.fn.strdisplaywidth(suffix)
        local targetWidth = width - sufWidth
        local curWidth = 0

        for _, chunk in ipairs(virtText) do
          local chunkText = chunk[1]
          local chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
          else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            local hlGroup = chunk[2]
            table.insert(newVirtText, { chunkText, hlGroup })
            chunkWidth = vim.fn.strdisplaywidth(chunkText)
            if curWidth + chunkWidth < targetWidth then
              suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
            end
            break
          end
          curWidth = curWidth + chunkWidth
        end

        table.insert(newVirtText, { suffix, "MoreMsg" })
        return newVirtText
      end,
    },
    init = function()
      vim.o.foldcolumn = "1"
      vim.o.foldlevel = 99
      vim.o.foldlevelstart = 99
      vim.o.foldenable = true
    end,
  },

  -- Keymaps for quick JSON node manipulation (buffer-local for json files)
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    ft = { "json", "jsonc" },
    config = function()
      -- Quick delete/change JSON nodes with leader mappings
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "json", "jsonc" },
        callback = function(ev)
          local opts = { buffer = ev.buf }

          vim.keymap.set("n", "<leader>jd", function()
            local node = vim.treesitter.get_node()
            if not node then return end
            while node do
              local type = node:type()
              if type == "pair" or type == "object" or type == "array" then break end
              node = node:parent()
            end
            if not node then return end
            local sr, sc, er, ec = node:range()
            local line = vim.fn.getline(er + 1)
            if line:sub(ec + 1, ec + 1) == "," then
              ec = ec + 1
            elseif sc > 0 then
              local prev_line = vim.fn.getline(sr + 1)
              local before = prev_line:sub(1, sc)
              local comma_pos = before:find(",%s*$")
              if comma_pos then sc = comma_pos - 1 end
            end
            vim.api.nvim_buf_set_text(ev.buf, sr, sc, er, ec, {})
            local remaining = vim.fn.getline(sr + 1)
            if vim.trim(remaining) == "" then
              vim.api.nvim_buf_set_lines(ev.buf, sr, sr + 1, false, {})
            end
          end, vim.tbl_extend("force", opts, { desc = "Delete JSON node" }))

          vim.keymap.set("n", "<leader>jf", "za", vim.tbl_extend("force", opts, { desc = "Toggle fold JSON node" }))
          vim.keymap.set("n", "<leader>jF", function()
            require("ufo").closeAllFolds()
          end, vim.tbl_extend("force", opts, { desc = "Fold all JSON" }))
          vim.keymap.set("n", "<leader>jU", function()
            require("ufo").openAllFolds()
          end, vim.tbl_extend("force", opts, { desc = "Unfold all JSON" }))
          vim.keymap.set("n", "<leader>jy", function()
            local node = vim.treesitter.get_node()
            if not node then return end
            while node do
              if node:type() == "pair" then break end
              node = node:parent()
            end
            if not node then return end
            local value_node = node:named_child(1)
            if not value_node then return end
            local text = vim.treesitter.get_node_text(value_node, 0)
            vim.fn.setreg("+", text)
            vim.notify("Yanked: " .. text:sub(1, 50), vim.log.levels.INFO)
          end, vim.tbl_extend("force", opts, { desc = "Yank JSON value" }))
          vim.keymap.set("n", "<leader>jt", function()
            open_viewer(ev.buf, "tree.html")
          end, vim.tbl_extend("force", opts, { desc = "JSON Tree viewer (live)" }))
          vim.keymap.set("n", "<leader>jc", function()
            open_viewer(ev.buf, "graph.html")
          end, vim.tbl_extend("force", opts, { desc = "JSON Crack graph (live)" }))
          vim.keymap.set("n", "<leader>jx", function()
            stop_server()
            vim.notify("JSON viewer stopped", vim.log.levels.INFO)
          end, vim.tbl_extend("force", opts, { desc = "Stop JSON viewer" }))

          local ok, wk = pcall(require, "which-key")
          if ok then wk.add({ { "<leader>j", group = "JSON", buffer = ev.buf } }) end
        end,
      })
    end,
  },
}
