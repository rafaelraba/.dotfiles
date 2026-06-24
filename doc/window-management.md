# Window management

This dotfiles setup uses AeroSpace as the window/workspace manager, SketchyBar as the visible workspace bar, and Hammerspoon only for small frame-helper scripts that AeroSpace calls from keybindings.

## Quick restore path

```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./restore.sh

# Start the apps once, grant permissions, then reload runtime config.
open -a AeroSpace
open -a Hammerspoon
aerospace reload-config
sketchybar --reload
```

If Homebrew refuses the AeroSpace cask from `nikitabobko/tap` as untrusted, run this once and retry the restore:

```bash
brew trust nikitabobko/tap
brew bundle --file="$HOME/.dotfiles/os/mac/brew/Brewfile" --no-lock
```

## Required apps, tools, and permissions

| Requirement | Source | Notes |
|-------------|--------|-------|
| AeroSpace | `os/mac/brew/Brewfile` → `cask "nikitabobko/tap/aerospace"` | Workspaces, tiling, focus/move, and workspace-change hooks. |
| SketchyBar | `os/mac/brew/Brewfile` → `brew "felixkratz/formulae/sketchybar"` | Transparent top workspace bar. |
| Hammerspoon | `os/mac/brew/Brewfile` → `cask "hammerspoon"` | CLI-accessible frame helpers through `hs -c`. |
| Accessibility permissions | macOS System Settings | Enable AeroSpace, Hammerspoon, and Raycast. |

Accessibility path:

```text
System Settings → Privacy & Security → Accessibility
→ enable AeroSpace, Hammerspoon, and Raycast
```

Without Accessibility permissions, hotkeys and window frame changes may silently fail.

## Ownership model

| Capability | Owner | Where |
|------------|-------|-------|
| Workspace model | AeroSpace | `editors/aerospace/aerospace.toml` |
| Workspace indicators | SketchyBar | `editors/sketchybar/sketchybarrc` |
| Per-monitor workspace highlight | SketchyBar plugin | `editors/sketchybar/plugins/aerospace_workspace.sh` |
| Tiling layouts | AeroSpace | Native AeroSpace commands. |
| Explicit floating layouts | AeroSpace keybindings + Hammerspoon frame helpers | `scripts/wm/*.sh` |
| SketchyBar top-gap reflow | Shell + Hammerspoon | `toggle-sketchybar.sh`, `ensure-visible-windows-top-gap.sh` |

Important rule: do not use Hammerspoon as a competing workspace manager. It is only used here because AeroSpace does not provide all explicit floating frame geometry needed for the custom layouts.

## Symlinked paths

`dot self install` creates these macOS symlinks from `symlinks/conf.macos.yaml`:

| Repo path | Target path |
|-----------|-------------|
| `editors/aerospace/aerospace.toml` | `~/.config/aerospace/aerospace.toml` |
| `editors/sketchybar` | `~/.config/sketchybar` |
| `editors/hammerspoon` | `~/.hammerspoon` |

## Workspace and monitor model

The current setup assumes two monitors and keeps workspaces deterministic:

| Monitor | Workspaces |
|---------|------------|
| `1` | `1`, `2`, `3`, `4` |
| `2` | `5`, `6`, `7`, `8` |

This is configured with AeroSpace `workspace-to-monitor-force-assignment`.

## Hotkeys

| Hotkey | Action |
|--------|--------|
| `Cmd+Alt+/` | Tile focused workspace horizontally. |
| `Cmd+Alt+Shift+/` | Tile focused workspace vertically. |
| `Cmd+Alt+S` | Apply main-left/stack-right floating layout and save visible frames. |
| `Cmd+Alt+,` | Toggle AeroSpace accordion layout. |
| `Cmd+Alt+H/J/K/L` | Focus window left/down/up/right. |
| `Cmd+Alt+Shift+H/J/K/L` | Move focused window left/down/up/right. |
| `Cmd+Alt+-` | Floating center resize at 50% width / 75% height. |
| `Cmd+Alt+=` | Floating center resize at 66% width / 85% height. |
| `Cmd+Alt+M` | Floating center resize at 78% width / 90% height. |
| `Cmd+Alt+F` | Maximize focused window inside the current top gap. |
| `Cmd+Alt+1..8` | Switch AeroSpace workspace. |
| `Cmd+Alt+Shift+1..8` | Move focused window to workspace. |
| `Cmd+Alt+Tab` | Workspace back-and-forth. |
| `Cmd+Alt+Shift+Tab` | Move current workspace to next monitor. |

## Floating frame restore behavior

`Cmd+Alt+S` converts the focused workspace windows to floating and creates the main-left/stack-right layout. The frame state lives in:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/aerospace-window-frames.tsv
```

The restore pipeline is intentionally defensive:

1. `save-visible-window-frames.sh` saves frames only for `aerospace list-windows --workspace visible`.
2. `restore-visible-window-frames.sh` runs on AeroSpace workspace changes.
3. Restore ignores stale saved frames that are mostly offscreen.
4. Restore rechecks the current SketchyBar top gap before applying frames.
5. Restore resolves same-column overlaps after top-gap changes.

This avoids a subtle integration bug: AeroSpace-hidden windows can still appear in Hammerspoon `hs.window.visibleWindows()` with offscreen coordinates. Do not use Hammerspoon visibility alone as the source of truth.

## SketchyBar top gap

The top gap is dynamic:

| SketchyBar state | AeroSpace `outer.top` | Reason |
|------------------|-----------------------|--------|
| Visible | `42` | Reserve room for the top workspace bar. |
| Hidden | `8` | Reclaim the screen area while keeping a small gap. |

`toggle-sketchybar.sh` updates the AeroSpace config, reloads AeroSpace, and runs `ensure-visible-windows-top-gap.sh`. That script scales stacked vertical columns proportionally so windows do not overlap when the bar appears or disappears.

## Verification checklist

Run these after restore or after changing window-management files:

```bash
zsh -n scripts/wm/*.sh
aerospace reload-config
sketchybar --reload
```

Manual checks:

- [ ] `Cmd+Alt+S` creates the main-left/stack-right floating layout.
- [ ] Switching workspaces and returning restores the same visible frames.
- [ ] No window disappears offscreen after workspace changes.
- [ ] SketchyBar visible state keeps windows below the bar.
- [ ] SketchyBar hidden state reclaims top space without overlap.
- [ ] Workspace indicators highlight the visible workspace on each monitor.

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| AeroSpace hotkeys do nothing | Accessibility permissions and app state | Enable AeroSpace in Accessibility, then run `aerospace reload-config`. |
| SketchyBar does not show workspaces | Symlink and service | Verify `~/.config/sketchybar`, then run `sketchybar --reload` or `brew services restart sketchybar`. |
| Window disappears after workspace change | Frame cache and visible window source | Remove `~/.cache/aerospace-window-frames.tsv`, reapply `Cmd+Alt+S`, and switch workspaces again. |
| Windows overlap when toggling the bar | Top-gap enforcement | Run `scripts/wm/ensure-visible-windows-top-gap.sh`; verify AeroSpace `outer.top` is `42` when visible and `8` when hidden. |
| Wrong workspace appears on wrong monitor | Monitor assignment | Check `[workspace-to-monitor-force-assignment]` in `editors/aerospace/aerospace.toml`. |

## Agent notes

- Keep AeroSpace as the owner of workspaces and tiling behavior.
- Keep SketchyBar as a visual indicator only; it should not own workspace state.
- Hammerspoon helpers may set explicit frames, but should not become a second workspace manager.
- When changing top-gap behavior, update both `restore-visible-window-frames.sh` and `ensure-visible-windows-top-gap.sh`.
- When changing workspace IDs or monitor assignment, update AeroSpace config, SketchyBar items, and this document together.
