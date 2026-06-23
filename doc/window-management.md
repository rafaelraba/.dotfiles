# AeroSpace + Hammerspoon window management

This repo uses a disciplined hybrid window-management setup: **AeroSpace owns workspaces** and **Hammerspoon owns window geometry, layouts, focus/move actions, app launch, and layout restore**. Use this document to restore the setup on a fresh macOS machine and verify that the ownership boundary still holds.

## Quick restore path

```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./restore.sh

# Apply and validate the window-management config.
aerospace reload-config --dry-run
aerospace reload-config
```

Then manually reload Hammerspoon:

```text
Hammerspoon menu bar icon → Reload Config
```

Expected result: `Cmd+Alt+1..8` switches AeroSpace workspaces (`1..4` on monitor 1, `5..8` on monitor 2), and Hammerspoon hotkeys apply explicit layouts/actions. Saved layouts are persisted by layout shortcuts but are not auto-restored on workspace switch by default.

## Required apps, tools, and permissions

| Requirement | Source | Notes |
|-------------|--------|-------|
| AeroSpace | `os/mac/brew/Brewfile` → `cask "nikitabobko/tap/aerospace"` | Workspace switching and move-to-workspace owner. |
| Hammerspoon | `os/mac/brew/Brewfile` → `cask "hammerspoon"` | Layouts, actions, app launcher, restore polling. |
| Homebrew bundle | `./restore.sh` runs `brew bundle --file=os/mac/brew/Brewfile` | Installs required CLI/apps/fonts. |
| Accessibility permissions | macOS System Settings | Enable AeroSpace, Hammerspoon, and Raycast. |

Accessibility path:

```text
System Settings → Privacy & Security → Accessibility
→ enable AeroSpace, Hammerspoon, Raycast
```

Without Accessibility permissions, hotkeys and window moves may silently fail.

## Dotfiles and symlink paths

`dot self install` creates these macOS symlinks from `symlinks/conf.macos.yaml`:

| Repo path | Target path | Owner |
|-----------|-------------|-------|
| `wm/aerospace` | `~/.config/aerospace` | AeroSpace config. |
| `editors/hammerspoon` | `~/.hammerspoon` | Hammerspoon config/modules. |

Key files:

| File | Purpose |
|------|---------|
| `wm/aerospace/aerospace.toml` | Workspace-only AeroSpace bindings and gaps. |
| `editors/hammerspoon/init.lua` | Hammerspoon entrypoint. |
| `editors/hammerspoon/modules/hotkeys.lua` | All Hammerspoon-owned hotkeys. |
| `editors/hammerspoon/modules/layouts.lua` | Layout preset implementations. |
| `editors/hammerspoon/modules/workspace_layout_restore.lua` | Per-workspace layout persistence and restore. |
| `editors/hammerspoon/modules/constants.lua` | Shared timing, geometry, and CLI constants. |

## Ownership model

| Capability | Owner | Where |
|------------|-------|-------|
| Switch workspace `1..8` | AeroSpace | `wm/aerospace/aerospace.toml` |
| Move focused window to workspace `1..8` | AeroSpace | `wm/aerospace/aerospace.toml` |
| Assign workspaces `1..4` to monitor 1 and `5..8` to monitor 2 | AeroSpace | `wm/aerospace/aerospace.toml` |
| Reload AeroSpace config | AeroSpace | `wm/aerospace/aerospace.toml` |
| Layout presets | Hammerspoon | `editors/hammerspoon/modules/layouts.lua` |
| Save/restore per-workspace layout | Hammerspoon | `workspace_layout_restore.lua` |
| Resize, center, directional focus/move | Hammerspoon | `resize.lua`, `focus.lua`, `hotkeys.lua` |
| App launcher | Hammerspoon | `hotkeys.lua` |
| Monitor focus/move | Hammerspoon | `focus.lua`, `hotkeys.lua` |

Forbidden patterns:

- Keep AeroSpace `exec-on-workspace-change` limited to the SketchyBar workspace highlight event.
- Do not use AeroSpace workspace-change hooks for Hammerspoon or layout restore bridges.
- Do not add shell bridge scripts that call `hs -c` from AeroSpace.
- Do not make AeroSpace own layout, resize, focus, app-launch, or monitor actions.
- Do not make Hammerspoon synchronously call AeroSpace in hot paths.

Allowed Hammerspoon → AeroSpace interaction is narrow: async, timeout-protected CLI calls for focused workspace polling and floating target windows before Hammerspoon applies frames.

## Hotkeys

### AeroSpace-owned workspace keys

| Hotkey | Action |
|--------|--------|
| `Cmd+Alt+1..8` | Switch to workspace `1..8`. |
| `Cmd+Alt+Shift+1..8` | Move focused window to workspace `1..8` and follow it. |
| `Cmd+Alt+Shift+R` | Reload AeroSpace config. |

### Hammerspoon-owned layout/action keys

| Hotkey | Action |
|--------|--------|
| `Cmd+Alt+H/J/K/L` | Focus window left/down/up/right. |
| `Cmd+Alt+Shift+H/J/K/L` | Move focused window left/down/up/right. |
| `Cmd+Alt+-` | Shrink focused window width. |
| `Cmd+Alt+=` | Grow focused window width. |
| `Cmd+Alt+M` | Center focused window. |
| `Cmd+Alt+F` | Maximize focused window to the visible screen frame. |
| `Cmd+Alt+S` | Apply and save `stack-right` layout for the current workspace. |
| `Cmd+Alt+Shift+S` | Apply and save `columns` layout for the current workspace. |
| `Cmd+Alt+Shift+M` | Apply and save `center-main` layout for the current workspace. |
| `Cmd+Alt+Shift+B` | Toggle SketchyBar visibility/gap. |
| `Cmd+Alt+Tab` | Focus next monitor. |
| `Cmd+Alt+Shift+Tab` | Move focused window to next monitor. |

### Hammerspoon app launcher keys

| Hotkey | App |
|--------|-----|
| `Cmd+Alt+Return` | Ghostty |
| `Cmd+Alt+O` | Obsidian |
| `Cmd+Alt+B` | Safari |
| `Cmd+Alt+C` | Visual Studio Code |

If a new machine uses different app names, update only the `apps` table in `editors/hammerspoon/modules/hotkeys.lua`.

## Layout restore behavior

| Item | Behavior |
|------|----------|
| State file | `$HOME/.cache/dotfiles/wm-layouts/state.json` |
| Schema | `schemaVersion = 1` |
| Known layouts | `stack-right`, `columns`, `center-main` |
| Polling | Hammerspoon polls `aerospace list-workspaces --focused` every `0.20s`. |
| Debounce | Restore waits `0.10s` after workspace change detection. |
| Auto-restore default | Disabled by default (`workspaceLayoutAutoRestore = false`) to avoid stale saved geometry affecting manual layouts. |
| Deadlock prevention | Uses async `hs.task`, one in-flight workspace query, and a `1.0s` AeroSpace CLI timeout. |
| Stale restore prevention | Re-checks focused workspace before applying and ignores old generations. |
| Feedback-loop prevention | Suppresses save-on-layout while restore is running. |
| Safe no-op cases | Missing AeroSpace, missing/invalid state, unknown layout, or fewer than two visible current-screen windows. |

The restore order uses saved window IDs when they are still visible on the current screen, then appends other visible windows. Hammerspoon may float windows through async AeroSpace calls before applying frames so AeroSpace tiling does not immediately undo the layout.

## Verification checklist

Run these from `~/.dotfiles`:

```bash
luajit test/scripts/workspace-layout-restore.lua
bash test/scripts/wm-invariants.sh
aerospace reload-config --dry-run
```

Manual Hammerspoon checks:

- [ ] Hammerspoon menu bar icon is visible.
- [ ] `Reload Config` completes without console errors.
- [ ] `Cmd+Alt+S`, `Cmd+Alt+Shift+S`, and `Cmd+Alt+Shift+M` apply layouts and update `$HOME/.cache/dotfiles/wm-layouts/state.json`.
- [ ] Explicit layout shortcuts still apply and save layouts; workspace switching does not auto-restore layouts by default.
- [ ] `Cmd+Alt+1..8` and `Cmd+Alt+Shift+1..8` still work through AeroSpace.

Useful status command:

```bash
hs -c 'return hs.inspect(require("modules.workspace_layout_restore").status())'
```

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Hotkeys do nothing | Accessibility permissions | Enable AeroSpace, Hammerspoon, and Raycast in Accessibility. Restart apps if needed. |
| AeroSpace keys fail | Config load | Run `aerospace reload-config --dry-run`, then `aerospace reload-config`. |
| Hammerspoon keys fail | Config reload/status | Use Hammerspoon menu → `Reload Config`; inspect Hammerspoon Console for Lua errors. |
| Layouts do not move windows | AeroSpace tiling or too few windows | Use at least two visible windows on the current screen; verify Hammerspoon can run async float calls. |
| Restore feels delayed | Poll/debounce constants | Inspect `workspaceLayoutPollInterval` and `workspaceLayoutRestoreDebounce` in `constants.lua`. Current values are `0.20` and `0.10`. |
| Multi-monitor layout restores on wrong screen | Focus/current screen | Focus a window on the intended monitor before saving the layout. Layout enumeration is scoped to the focused/current screen. |
| Bad or stale restore state | State cache | Remove `$HOME/.cache/dotfiles/wm-layouts/state.json`, then save layouts again. |
| AeroSpace CLI is not found | CLI path resolution | Set `AEROSPACE_BIN=/path/to/aerospace` before launching Hammerspoon, or ensure `aerospace` is in PATH. |

## Agent notes

Do not change behavior while updating docs or adding restore guidance. For implementation work:

- Read `wm/aerospace/README.md` and `editors/hammerspoon/README.md` first.
- Keep the ownership split: AeroSpace for workspaces only; Hammerspoon for geometry/actions/restore.
- Safe extension points are Hammerspoon modules, new tests under `test/scripts/`, and docs under `doc/`.
- If adding a layout, update `layouts.lua`, `hotkeys.lua`, `workspace_layout_restore.lua` known layouts, tests, and this document.
- If adding a new app launcher binding, update only the Hammerspoon `apps` table unless the app also needs Brewfile installation.
- Always run `bash test/scripts/wm-invariants.sh` after changing window-management behavior.
