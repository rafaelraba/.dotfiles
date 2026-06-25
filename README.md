# .dotfiles created with [dotly](https://github.com/CodelyTV/dotly)

Personal macOS setup: Neovim, tmux, Ghostty, LazyGit, AeroSpace, SketchyBar, Raycast, zsh, and Starship.

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
- macOS 13+ for AeroSpace.
- On Intel macOS, run the same `restore.sh`; dotly applies the correct platform symlinks.

## What gets installed

`restore.sh` is idempotent and does the following:

1. Initializes the `dotly` submodule.
2. Creates symlinks with `dot self install`.
3. Installs [TPM](https://github.com/tmux-plugins/tpm) and tmux plugins.
4. Runs `brew bundle` with `os/mac/brew/Brewfile`.
5. Symlinks AeroSpace and SketchyBar config into `~/.config`.

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

1. **AeroSpace**: open the app once, grant Accessibility permissions, then run `aerospace reload-config`.
2. **SketchyBar**: start or reload it with `brew services restart sketchybar` or `sketchybar --reload`.
3. **Raycast**: configure Window Management in the app and import/export Raycast settings when moving between machines.
4. **Ghostty**: in Settings, use `JetBrainsMono Nerd Font` or `IosevkaTerm Nerd Font`.

## Accessibility permissions

AeroSpace and Raycast need Accessibility permissions for the active workflow:

```text
System Settings → Privacy & Security → Accessibility
→ Add/enable: AeroSpace, Raycast
```

Without Accessibility permissions, window-management hotkeys and window placement actions will not work.

## Window management restore

This setup is intentionally simple and split by responsibility:

| Runtime | Responsibility |
|---------|----------------|
| AeroSpace | Workspaces, tiling tree, default focus/move/resize hotkeys, monitor assignment, workspace-change SketchyBar trigger. |
| Raycast | One-shot centered floating-window placement and sizing. |
| SketchyBar | Transparent top workspace bar with per-monitor workspace indicators. |

Important restore files:

| Repo path | Target / purpose |
|-----------|------------------|
| `editors/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |
| `editors/raycast/README.md` | Raycast restore, hotkey, and export/import guidance. |
| `editors/sketchybar` | `~/.config/sketchybar` |
| `scripts/wm/toggle-sketchybar.sh` | Toggles SketchyBar only. |

Current workspace model:

- Workspaces `1..4` are forced to monitor `1`.
- Workspaces `5..8` are forced to monitor `2`.
- `Alt+1..8` switches workspaces.
- `Alt+Shift+1..8` moves the focused window to a workspace and follows it.
- `Alt+H/J/K/L` focuses windows.
- `Alt+Shift+H/J/K/L` moves windows.
- `Alt+Shift+;`, then `F`, toggles the focused window between floating and tiling.
- Use a Raycast Window Management command for explicit centered floating placement.

## Documentation

- [Window management](doc/window-management.md): AeroSpace + SketchyBar + Raycast ownership model, hotkeys, and troubleshooting.

## Verification checklist

- [ ] `aerospace --version` works and `aerospace reload-config` succeeds.
- [ ] `sketchybar --reload` works and workspace indicators appear on both monitors.
- [ ] `Alt+Shift+;`, then `F`, toggles a focused window between floating and tiling.
- [ ] Your Raycast window-management shortcut centers a floating window.
- [ ] Toggling SketchyBar does not modify AeroSpace config.
- [ ] `nvim` opens without plugin errors.
- [ ] `tmux` starts and the prefix is `Ctrl+a`.
- [ ] `lazygit` opens.
- [ ] `ghostty` uses a Nerd Font.
- [ ] Raycast window-management shortcuts respond.

## Known notes

- The Brewfile uses `python@3.13` as the stable Python formula.
- Some `brew bundle` packages may fail because of manual dependencies; review the output and retry.
- Homebrew may require explicit trust for third-party taps before installing or updating packages. For AeroSpace, run: `brew trust nikitabobko/tap`.
