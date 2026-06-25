# Window management

This setup keeps window management intentionally simple:

- **AeroSpace** owns workspaces, tiling, focus, move, resize, and floating/tiling state.
- **Raycast** centers or resizes a floating window with native Window Management commands.
- **Hammerspoon** owns global keyboard input helpers only; it does not manage windows.
- **SketchyBar** displays workspace state and its toggle adjusts the AeroSpace top gap so windows never sit under the bar.
- **JankyBorders** highlights the focused window with a rounded periwinkle active border.

## Quick restore path

```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./restore.sh

open -a AeroSpace
open -a Hammerspoon
aerospace reload-config
sketchybar --reload
```

Then configure the desired Raycast Window Management command and hotkey in Raycast. Use Raycast export/import when moving the setup between machines.

If Homebrew refuses the AeroSpace cask from `nikitabobko/tap` as untrusted, run this once and retry:

```bash
brew trust nikitabobko/tap
brew bundle --file="$HOME/.dotfiles/os/mac/brew/Brewfile" --no-lock
```

## Required apps and permissions

| Requirement | Source | Notes |
|-------------|--------|-------|
| AeroSpace | `os/mac/brew/Brewfile` → `cask "nikitabobko/tap/aerospace"` | Workspaces and tiling. |
| SketchyBar | `os/mac/brew/Brewfile` → `brew "felixkratz/formulae/sketchybar"` | Workspace bar. |
| JankyBorders | `os/mac/brew/Brewfile` → `brew "felixkratz/formulae/borders"` | Focused-window border. |
| Hammerspoon | `os/mac/brew/Brewfile` → `cask "hammerspoon"` | Global input helpers only. |
| Raycast | `os/mac/brew/Brewfile` → `cask "raycast"` | Centered floating-window placement. |

## Visual defaults

| Area | Value |
|------|-------|
| Focus border | JankyBorders `style=round`, `width=7.0`, color `#89b4fa`. |
| Workspace active color | SketchyBar active workspace pill `#89b4fa`. |
| Window gaps | AeroSpace inner `20px`, outer left/right `28px`, bottom `24px`. |
| Bar spacing | `Alt+B` toggles top gap between `60px` visible and `24px` hidden. |

Accessibility path:

```text
System Settings → Privacy & Security → Accessibility
→ enable AeroSpace, Hammerspoon, and Raycast
```

## Symlinked paths

| Repo path | Target path |
|-----------|-------------|
| `editors/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |
| `editors/hammerspoon` | `~/.hammerspoon` |
| `editors/raycast/README.md` | Raycast restore, hotkey, and export/import guidance. |
| `editors/sketchybar` | `~/.config/sketchybar` |

## Workspace model

Workspaces `1..8` are persistent. The config keeps the two-monitor assignment used by SketchyBar:

| Monitor | Workspaces |
|---------|------------|
| `1` | `1`, `2`, `3`, `4` |
| `2` | `5`, `6`, `7`, `8` |

## AeroSpace hotkeys

The bindings are close to the official AeroSpace default and use `Alt` as the main modifier.

| Hotkey | Action |
|--------|--------|
| `Alt+/` | Toggle tiles orientation. |
| `Alt+,` | Toggle accordion orientation. |
| `Alt+H/J/K/L` | Focus window left/down/up/right. |
| `Alt+Shift+H/J/K/L` | Move focused window left/down/up/right. |
| `Alt+-` / `Alt+=` | Resize tiling split smaller/larger. |
| `Alt+1..8` | Switch workspace. |
| `Alt+Shift+1..8` | Move focused window to workspace and follow it. |
| `Alt+Tab` | Workspace back-and-forth. |
| `Alt+Shift+;` | Enter service mode. |
| `Alt+B` | Toggle the workspace bar and resize AeroSpace's top gap. |
| Service mode `F` | Toggle focused window between floating and tiling. |
| Service mode `R` | Flatten workspace tree. |
| Service mode `B` | Balance sizes. |

## Floating windows

AeroSpace owns the floating/tiling state, but not exact floating geometry. For a centered floating window:

1. Toggle the window to floating with `Alt+Shift+;`, then `F`.
2. Run your Raycast Window Management shortcut to center/size it.

This avoids persistent frame restore scripts and keeps workspace switching stable.

## Verification checklist

```bash
zsh -n scripts/wm/toggle-sketchybar.sh
aerospace reload-config --dry-run --no-gui
sketchybar --reload
test/scripts/wm-invariants.sh
```

Manual checks:

- [ ] `Alt+1..8` switches AeroSpace workspaces.
- [ ] `Alt+Shift+;`, then `F`, toggles floating/tiling.
- [ ] Hammerspoon global input shortcuts work without taking window-management ownership.
- [ ] Your Raycast window-management shortcut centers the floating window.
- [ ] `Alt+B` shows/hides SketchyBar; windows move below it when shown and reclaim the space when hidden.
- [ ] The focused window has a rounded periwinkle border from `borders`.

## Agent notes

- Do not reintroduce frame persistence, workspace-change restore hooks, or external layout ownership.
- The SketchyBar toggle is intentionally allowed to update only `gaps.outer.top` and reload AeroSpace because AeroSpace has no runtime gaps command in 0.20.3.
- Keep Hammerspoon limited to global input helpers.
- Keep AeroSpace bindings native unless there is a clear reason not to.
- Keep explicit floating geometry in Raycast, not in AeroSpace scripts.
