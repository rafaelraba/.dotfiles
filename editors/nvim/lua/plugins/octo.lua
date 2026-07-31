return {
  "pwntester/octo.nvim",
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>gpl", "<cmd>Octo pr list<cr>", desc = "GitHub PRs: List" },
    {
      "<leader>gps",
      function()
        require("octo.utils").create_base_search_command({ include_current_repo = true })
      end,
      desc = "GitHub PRs: Search Current Repo",
    },
    { "<leader>gpS", "<cmd>Octo search is:pr<cr>", desc = "GitHub PRs: Search" },
    { "<leader>gpo", "<cmd>Octo pr browser<cr>", desc = "GitHub PR: Open in Browser" },
    { "<leader>gpc", "<cmd>Octo pr checkout<cr>", desc = "GitHub PR: Checkout" },
    { "<leader>gpd", "<cmd>Octo pr diff<cr>", desc = "GitHub PR: Diff" },
    { "<leader>gpf", "<cmd>Octo pr changes<cr>", desc = "GitHub PR: Changed Files" },
    { "<leader>gr", "<cmd>Octo review start<cr>", desc = "GitHub PR Review: Start" },
    { "<leader>gR", "<cmd>Octo review resume<cr>", desc = "GitHub PR Review: Resume" },
    { "<leader>gpm", "<cmd>Octo review comments<cr>", desc = "GitHub PR Review: Comments" },
    { "<leader>gpx", "<cmd>Octo review submit<cr>", desc = "GitHub PR Review: Submit" },
  },
  opts = {
    picker = "snacks",
    enable_builtin = true,
    default_remote = { "upstream", "origin" },
    default_delete_branch = false,
    use_local_fs = true,
    picker_config = {
      mappings = {
        checkout_pr = { lhs = "<C-o>", desc = "checkout pull request" },
        open_in_browser = { lhs = "<C-b>", desc = "open in browser" },
        copy_url = { lhs = "<C-y>", desc = "copy URL" },
        copy_sha = { lhs = "<C-e>", desc = "copy commit SHA" },
      },
    },
    reviews = {
      auto_show_threads = true,
      focus = "right",
    },
    pull_requests = {
      order_by = {
        field = "UPDATED_AT",
        direction = "DESC",
      },
    },
    file_panel = {
      size = 12,
      icons = true,
    },
  },
  config = function(_, opts)
    local octo = require("octo")
    local uri = require("octo.uri")
    local utils = require("octo.utils")

    octo.setup(opts)

    -- Octo's GraphQL callback can run after its target buffer was closed.
    -- Keep this workaround until upstream validates bufnr before nvim_buf_call().
    octo.load_buffer = function(load_opts)
      load_opts = load_opts or {}
      local bufnr = load_opts.bufnr or vim.api.nvim_get_current_buf()
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local buffer_info = uri.parse(vim.fn.bufname(bufnr))

      if buffer_info == nil then
        utils.print_err("Cannot parse buffer name: " .. vim.fn.bufname(bufnr))
        return
      end

      octo.load(buffer_info.repo, buffer_info.kind, buffer_info.id, buffer_info.hostname, function(obj)
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        vim.api.nvim_buf_call(bufnr, function()
          octo.create_buffer(buffer_info.kind, obj, buffer_info.repo, false, buffer_info.hostname)

          local lines = vim.api.nvim_buf_line_count(bufnr)
          vim.api.nvim_win_set_cursor(0, {
            math.min(cursor_pos[1], lines),
            math.max(0, cursor_pos[2] - 1),
          })

          if load_opts.verbose then
            utils.info(string.format("Loaded %s/%s/%d", buffer_info.repo, buffer_info.kind, buffer_info.id))
          end
        end)
      end)
    end
  end,
}
