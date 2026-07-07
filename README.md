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
3. **JankyBorders**: installed as `borders`; AeroSpace starts it automatically with a rounded periwinkle focused-window border.
4. **Hammerspoon**: open the app once, grant Accessibility permissions, then reload config.
5. **Raycast**: configure Window Management in the app and import/export Raycast settings when moving between machines.
6. **Ghostty**: in Settings, use `JetBrainsMono Nerd Font` or `IosevkaTerm Nerd Font`.
7. **AI agent status**: restart Claude Code and OpenCode so they reload the restored tmux status hooks/plugins.

## Accessibility permissions

AeroSpace, Hammerspoon, and Raycast need Accessibility permissions for the active workflow:

```text
System Settings → Privacy & Security → Accessibility
→ Add/enable: AeroSpace, Hammerspoon, Raycast
```

Without Accessibility permissions, window-management hotkeys and window placement actions will not work.

## Window management restore

This setup is intentionally simple and split by responsibility:

| Runtime | Responsibility |
|---------|----------------|
| AeroSpace | Workspaces, tiling tree, default focus/move/resize hotkeys, monitor assignment, workspace-change SketchyBar trigger. |
| Hammerspoon | Global keyboard input helpers only. No windows, layouts, workspaces, or app launchers. |
| JankyBorders | Rounded focused-window highlight (`#89b4fa`, width `7.0`). |
| Raycast | One-shot centered floating-window placement and sizing. |
| SketchyBar | Elegant top workspace bar with per-monitor workspace indicators. |

Important restore files:

| Repo path | Target / purpose |
|-----------|------------------|
| `editors/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |
| `editors/hammerspoon` | `~/.hammerspoon`, global input helpers only. |
| `editors/raycast/README.md` | Raycast restore, hotkey, and export/import guidance. |
| `editors/sketchybar` | `~/.config/sketchybar` |
| `scripts/wm/toggle-sketchybar.sh` | Toggles SketchyBar and updates AeroSpace's top gap. |

## AI agent status restore

Tmux shows shared agent state for Pi, OpenCode, and Claude Code using the same protocol: `running`, `blocked`, `done`, `idle`, and `error`.

Important restore files:

| Repo path | Target / purpose |
|-----------|------------------|
| `scripts/agent-status.sh` | Generic tmux agent status protocol. |
| `scripts/status-sessions.sh` | Renders tmux session pills with agent status dots. |
| `editors/pi/agent/extensions/tmux-agent-status.ts` | `~/.pi/agent/extensions/tmux-agent-status.ts` |
| `editors/opencode/plugins/tmux-agent-status.ts` | `~/.config/opencode/plugins/tmux-agent-status.ts` |
| `editors/claude/settings.json` | `~/.claude/settings.json`, including Claude Code hooks for tmux status. |
| `scripts/claude-agent-status.sh` | Claude Code hook adapter for tmux status. |

After restore, restart tmux, Claude Code, and OpenCode.

Quick verification:

```bash
test -L ~/.claude/settings.json
test -L ~/.config/opencode/plugins/tmux-agent-status.ts
```

Visual defaults:

- Focus border: JankyBorders `style=round`, `width=7.0`, active color `#89b4fa`.
- AeroSpace gaps: inner `20px`, outer left/right `28px`, bottom `24px`.
- SketchyBar top gap: `60px` when visible, `24px` when hidden.

Current workspace model:

- Workspaces `1..4` are forced to monitor `1`.
- Workspaces `5..8` are forced to monitor `2`.
- `Alt+1..8` switches workspaces.
- `Alt+Shift+1..8` moves the focused window to a workspace and follows it.
- `Alt+H/J/K/L` focuses windows.
- `Alt+Shift+H/J/K/L` moves windows.
- `Alt+B` toggles the workspace bar; windows move below it when shown and reclaim the space when hidden.
- `Alt+Shift+;`, then `F`, toggles the focused window between floating and tiling.
- Use a Raycast Window Management command for explicit centered floating placement.

## Documentation

- [Window management](doc/window-management.md): AeroSpace + SketchyBar + Raycast ownership model, hotkeys, and troubleshooting.

## Verification checklist

- [ ] `aerospace --version` works and `aerospace reload-config` succeeds.
- [ ] `sketchybar --reload` works and workspace indicators appear on both monitors.
- [ ] Hammerspoon global input shortcuts work: `Ctrl+Option+N` → `ñ`, `Ctrl+Option+Shift+N` → `Ñ`, `Ctrl+Option+E` then vowel → accented vowel.
- [ ] `Alt+Shift+;`, then `F`, toggles a focused window between floating and tiling.
- [ ] Your Raycast window-management shortcut centers a floating window.
- [ ] `Alt+B` shows/hides SketchyBar and adjusts the AeroSpace top gap.
- [ ] The focused window has a rounded periwinkle border from `borders`.
- [ ] `nvim` opens without plugin errors.
- [ ] `tmux` starts and the prefix is `Ctrl+a`.
- [ ] Claude Code and OpenCode restart with tmux agent status hooks/plugins loaded.
- [ ] `~/.claude/settings.json` and `~/.config/opencode/plugins/tmux-agent-status.ts` are symlinks into `~/.dotfiles`.
- [ ] `lazygit` opens.
- [ ] `ghostty` uses a Nerd Font.
- [ ] Raycast window-management shortcuts respond.

## Known notes

- The Brewfile uses `python@3.13` as the stable Python formula.
- Some `brew bundle` packages may fail because of manual dependencies; review the output and retry.
- Homebrew may require explicit trust for third-party taps before installing or updating packages. For AeroSpace, run: `brew trust nikitabobko/tap`.
