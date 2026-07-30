return {
  "rparrapy/tuicr.nvim",
  cmd = { "Tuicr", "TuicrToggle" },
  opts = {
    close_on_exit = true,
    close_strategy = "clip_then_quit",
    win = {
      style = "float",
      border = "rounded",
      width = 0.95,
      height = 0.95,
      title = " tuicr ",
      title_pos = "center",
    },
  },
}
