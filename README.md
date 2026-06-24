# .dotfiles created with [dotly](https://github.com/CodelyTV/dotly)

Personal macOS setup: Neovim, tmux, Ghostty, LazyGit, AeroSpace, SketchyBar, Hammerspoon, Raycast, zsh, and Starship.

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
3. **Hammerspoon**: menu → `Reload Config`.
4. **Raycast**: open it and configure the keyboard shortcut.
5. **Ghostty**: in Settings, use `JetBrainsMono Nerd Font` or `IosevkaTerm Nerd Font`.

## Accessibility permissions

AeroSpace, Hammerspoon, and Raycast need Accessibility permissions for the active workflow:

```text
System Settings → Privacy & Security → Accessibility
→ Add/enable: AeroSpace, Hammerspoon, Raycast
```

Without Accessibility permissions, window-management hotkeys and frame helpers will not work.

## Window management restore

This setup is intentionally split by responsibility:

| Runtime | Responsibility |
|---------|----------------|
| AeroSpace | Workspaces, tiling tree, focus/move hotkeys, monitor assignment, workspace-change hooks. |
| Hammerspoon | Small CLI frame helpers used by AeroSpace for explicit floating geometry. |
| SketchyBar | Transparent top workspace bar with per-monitor workspace indicators. |

Important restore files:

| Repo path | Target / purpose |
|-----------|------------------|
| `editors/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |
| `editors/sketchybar` | `~/.config/sketchybar` |
| `scripts/wm/stack-right-focused-workspace.sh` | `Cmd+Alt+S` floating main-left/stack-right layout. |
| `scripts/wm/save-visible-window-frames.sh` | Saves only AeroSpace-visible floating frames. |
| `scripts/wm/restore-visible-window-frames.sh` | Restores visible frames on workspace change and prevents offscreen/top-bar overlap. |
| `scripts/wm/ensure-visible-windows-top-gap.sh` | Reflows windows when SketchyBar is shown/hidden. |
| `scripts/wm/toggle-sketchybar.sh` | Toggles SketchyBar and updates AeroSpace `outer.top`. |

Current workspace model:

- Workspaces `1..4` are forced to monitor `1`.
- Workspaces `5..8` are forced to monitor `2`.
- `Cmd+Alt+1..8` switches workspaces.
- `Cmd+Alt+Shift+1..8` moves the focused window to a workspace, follows it, and scales/contains floating frames on the target monitor.
- `Ctrl+Alt+Cmd+H/L` focuses the monitor to the left/right.
- `Ctrl+Alt+Cmd+Shift+H/L` moves the focused window to the left/right monitor and scales/contains it inside the target screen.
- `Cmd+Alt+S` applies the custom floating stack layout and persists visible frames.

The top gap is dynamic:

- SketchyBar visible → AeroSpace `outer.top = 42`.
- SketchyBar hidden → AeroSpace `outer.top = 8`.
- Frame restore must use AeroSpace-visible windows, not only Hammerspoon `visibleWindows()`, because AeroSpace-hidden windows can still appear offscreen to Hammerspoon.

## Documentation

- [Window management](doc/window-management.md): AeroSpace + SketchyBar + Hammerspoon ownership model, hotkeys, restore behavior, and troubleshooting.

## Verification checklist

- [ ] `aerospace --version` works and `aerospace reload-config` succeeds.
- [ ] `sketchybar --reload` works and workspace indicators appear on both monitors.
- [ ] Hammerspoon shows the menu bar icon and has no console errors.
- [ ] `Cmd+Alt+S` applies the main-left/stack-right floating layout.
- [ ] Switching workspaces after `Cmd+Alt+S` restores windows without hiding them offscreen.
- [ ] Toggling SketchyBar does not overlap windows; top gap changes between `42` and `8`.
- [ ] `nvim` opens without plugin errors.
- [ ] `tmux` starts and the prefix is `Ctrl+a`.
- [ ] `lazygit` opens.
- [ ] `ghostty` uses a Nerd Font.
- [ ] Hammerspoon/Raycast shortcuts respond.

## Known notes

- The Brewfile uses `python@3.13` as the stable Python formula.
- Some `brew bundle` packages may fail because of manual dependencies; review the output and retry.
- Homebrew may require explicit trust for third-party taps before installing or updating packages. For AeroSpace, run: `brew trust nikitabobko/tap`.
