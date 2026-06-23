# .dotfiles created with [dotly](https://github.com/CodelyTV/dotly)

Personal macOS setup: Neovim, tmux, Ghostty, LazyGit, Hammerspoon, SketchyBar, Raycast, zsh, and Starship.

## Quick install

```bash
# 1. Clone the repo
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles

# 2. Run the full restore
cd ~/.dotfiles && ./restore.sh
```

Restart the terminal when it finishes.

## Prerequisites

- Git with an SSH key configured in GitHub.
- Homebrew installed on macOS: [brew.sh](https://brew.sh).
- On Intel macOS, run the same `restore.sh`; dotly applies the correct platform symlinks.

## What gets installed

`restore.sh` is idempotent and does the following:

1. Initializes the `dotly` submodule.
2. Creates symlinks with `dot self install`.
3. Installs [TPM](https://github.com/tmux-plugins/tpm) and tmux plugins.
4. Runs `brew bundle` with `os/mac/brew/Brewfile`.

## Manual install

If you prefer to control each step:

```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
git submodule update --init --recursive modules/dotly
DOTFILES_PATH="$HOME/.dotfiles" DOTLY_PATH="$DOTFILES_PATH/modules/dotly" "$DOTLY_PATH/bin/dot" self install
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
brew bundle --file="$HOME/.dotfiles/os/mac/brew/Brewfile"
```

## Post-install

After `restore.sh`:

1. **Hammerspoon**: menu → `Reload Config`.
2. **Raycast**: open it and configure the keyboard shortcut.
3. **Ghostty**: in Settings, use `JetBrainsMono Nerd Font` or `IosevkaTerm Nerd Font`.

## Accessibility permissions

Hammerspoon and Raycast need Accessibility permissions for the active workflow:

```text
System Settings → Privacy & Security → Accessibility
→ Add/enable: Hammerspoon, Raycast
```

Without Hammerspoon permissions, window-management hotkeys will not work.

## Documentation

- [Hammerspoon window management](doc/window-management.md): Hammerspoon-only ownership model, hotkeys, verification, and known tradeoffs.

## Verification checklist

- [ ] `test/scripts/wm-invariants.sh` passes all window-management ownership checks.
- [ ] Hammerspoon shows the menu bar icon and has no console errors.
- [ ] `Cmd+Alt+S`, `Cmd+Alt+Shift+S`, and `Cmd+Alt+Shift+M` apply layouts directly from Hammerspoon.
- [ ] Mission Control `Switch to Desktop 1..10` shortcuts are enabled as `Ctrl+1..Ctrl+0`; `Cmd+Alt+1..0` proxies them through Hammerspoon.
- [ ] `nvim` opens without plugin errors.
- [ ] `tmux` starts and the prefix is `Ctrl+a`.
- [ ] `lazygit` opens.
- [ ] `ghostty` uses a Nerd Font.
- [ ] Hammerspoon/Raycast shortcuts respond.

## Known notes

- The Brewfile uses `python@3.13` as the stable Python formula.
- Some `brew bundle` packages may fail because of manual dependencies; review the output and retry.
- Window management is Hammerspoon-only. Native macOS Spaces are driven through Mission Control shortcuts, so there are no repo-managed workspace IDs or move-to-workspace shortcuts.
