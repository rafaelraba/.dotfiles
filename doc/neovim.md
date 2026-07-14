# Restore Neovim reliably

This setup restores Neovim, its plugins, and its Markdown tooling through `./restore.sh`.

## Quick verification

Run these commands after restoration:

```bash
command -v nvim node npm marksman
nvim --headless '+checkhealth vim.lsp' '+qall'
```

Open a Markdown file in Neovim and run `:LspInfo`. `marksman` must appear as an attached server. Use `<leader>mp` to open the browser preview.

## Markdown components

| Component | Responsibility | Installed by |
| --- | --- | --- |
| Node.js and npm | Custom browser preview and `markdown-preview.nvim` build | Homebrew Brewfile |
| Marksman | Markdown diagnostics, navigation, and completion | Homebrew Brewfile |
| render-markdown.nvim | Inline rendering in Neovim | Lazy.nvim |
| markdown-preview.nvim | Browser preview | Lazy.nvim and npm |

The browser preview listens only on `127.0.0.1` and uses an available port automatically.

## Troubleshooting

If `marksman` does not attach, ensure the binary is installed and restart Neovim:

```bash
brew install marksman
```

Then run `:LspInfo` inside the Markdown buffer.

If the browser preview reports that Node is missing, run:

```bash
brew bundle --file="$HOME/.dotfiles/os/mac/brew/Brewfile"
```

Then restart Neovim.
