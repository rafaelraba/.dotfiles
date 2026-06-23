# Hammerspoon window management

Hammerspoon is the only window-management runtime in these dotfiles. It owns window geometry, layout presets, focus/move actions, app launch, monitor actions, SketchyBar visibility, and a thin proxy to native macOS Desktop shortcuts.

## Quick restore path

```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./restore.sh

# Validate the standalone Hammerspoon window-management checks.
luajit test/scripts/hammerspoon-standalone-layouts.lua
bash test/scripts/wm-invariants.sh
```

Then manually reload Hammerspoon:

```text
Hammerspoon menu bar icon → Reload Config
```

Expected result: Hammerspoon hotkeys apply explicit layouts/actions without calling external workspace managers. Layout shortcuts apply geometry immediately, but no per-workspace layout state is saved or restored.

## Required apps, tools, and permissions

| Requirement | Source | Notes |
|-------------|--------|-------|
| Hammerspoon | `os/mac/brew/Brewfile` → `cask "hammerspoon"` | Layouts, actions, app launcher, and SketchyBar toggle. |
| SketchyBar | `os/mac/brew/Brewfile` → `brew "felixkratz/formulae/sketchybar"` | Optional menu bar visibility toggled by Hammerspoon. |
| Homebrew bundle | `./restore.sh` runs `brew bundle --file=os/mac/brew/Brewfile` | Installs required CLI/apps/fonts. |
| Accessibility permissions | macOS System Settings | Enable Hammerspoon and Raycast as needed. |

Accessibility path:

```text
System Settings → Privacy & Security → Accessibility
→ enable Hammerspoon and Raycast as needed
```

Without Accessibility permissions, hotkeys and window moves may silently fail.

## Dotfiles and symlink paths

`dot self install` creates the Hammerspoon symlink from `symlinks/conf.macos.yaml`:

| Repo path | Target path | Owner |
|-----------|-------------|-------|
| `editors/hammerspoon` | `~/.hammerspoon` | Hammerspoon config/modules. |

Key files:

| File | Purpose |
|------|---------|
| `editors/hammerspoon/init.lua` | Hammerspoon entrypoint. |
| `editors/hammerspoon/modules/hotkeys.lua` | All Hammerspoon-owned hotkeys. |
| `editors/hammerspoon/modules/layouts.lua` | Layout preset implementations. |
| `editors/hammerspoon/modules/workspace_layout_restore.lua` | Deprecated no-op compatibility module; not started at runtime. |
| `editors/hammerspoon/modules/constants.lua` | Shared geometry constants. |
| `scripts/wm/toggle-sketchybar.sh` | Deterministic SketchyBar visibility toggle. |

## Ownership model

| Capability | Owner | Where |
|------------|-------|-------|
| Layout presets | Hammerspoon | `editors/hammerspoon/modules/layouts.lua` |
| Resize, center, directional focus/move | Hammerspoon | `resize.lua`, `focus.lua`, `hotkeys.lua` |
| App launcher | Hammerspoon | `hotkeys.lua` |
| Monitor focus/move | Hammerspoon | `focus.lua`, `hotkeys.lua` |
| Desktop/workspace model | macOS Spaces | Native macOS behavior; Hammerspoon proxies `Cmd+Alt+1..0` to Mission Control `Ctrl+1..0`. |

Known tradeoff: native macOS Spaces do not provide deterministic repo-managed workspace IDs, workspace-to-monitor assignment, or move-to-workspace shortcuts. Mission Control `Switch to Desktop 1..10` shortcuts must be enabled in System Settings.

Forbidden patterns:

- Do not add runtime calls to external workspace-manager CLIs.
- Do not restore Hammerspoon layouts by workspace.
- Do not make the SketchyBar toggle edit or reload any window-manager config.

## Hotkeys

### Hammerspoon-owned layout/action keys

| Hotkey | Action |
|--------|--------|
| `Cmd+Alt+H/J/K/L` | Focus window left/down/up/right. |
| `Cmd+Alt+Shift+H/J/K/L` | Move focused window left/down/up/right. |
| `Cmd+Alt+-` | Shrink focused window width. |
| `Cmd+Alt+=` | Grow focused window width. |
| `Cmd+Alt+M` | Center focused window. |
| `Cmd+Alt+F` | Maximize focused window to the visible screen frame. |
| `Cmd+Alt+S` | Apply `stack-right` layout. |
| `Cmd+Alt+Shift+S` | Apply `columns` layout. |
| `Cmd+Alt+Shift+M` | Apply `center-main` layout. |
| `Cmd+Alt+Shift+B` | Toggle SketchyBar visibility only. |
| `Cmd+Alt+Tab` | Focus next monitor. |
| `Cmd+Alt+Shift+Tab` | Move focused window to next monitor. |

### Native macOS Desktop keys

These require Mission Control shortcuts `Ctrl+1..Ctrl+0` to be enabled in macOS System Settings.

| Hotkey | Action |
|--------|--------|
| `Cmd+Alt+1..9` | Switch to native macOS Desktop 1..9. |
| `Cmd+Alt+0` | Switch to native macOS Desktop 10. |

### Hammerspoon app launcher keys

| Hotkey | App |
|--------|-----|
| `Cmd+Alt+Return` | Ghostty |
| `Cmd+Alt+O` | Obsidian |
| `Cmd+Alt+B` | Safari |
| `Cmd+Alt+C` | Visual Studio Code |

If a new machine uses different app names, update only the `apps` table in `editors/hammerspoon/modules/hotkeys.lua`.

## Layout restore behavior

Per-workspace layout restore is disabled. `workspace_layout_restore.lua` remains as a deprecated no-op compatibility module, but `init.lua` does not start it and hotkeys do not save layout state. Explicit shortcuts still apply layouts to the current visible windows using direct Hammerspoon frame APIs.

## Verification checklist

Run these from `~/.dotfiles`:

```bash
luajit test/scripts/hammerspoon-standalone-layouts.lua
bash test/scripts/wm-invariants.sh
```

Manual Hammerspoon checks:

- [ ] Hammerspoon menu bar icon is visible.
- [ ] `Reload Config` completes without console errors.
- [ ] `Cmd+Alt+S`, `Cmd+Alt+Shift+S`, and `Cmd+Alt+Shift+M` apply layouts without creating/updating workspace restore state.
- [ ] Mission Control `Switch to Desktop 1..10` shortcuts are enabled as `Ctrl+1..Ctrl+0`.
- [ ] `Cmd+Alt+1..0` switches native macOS Desktops through Hammerspoon.
- [ ] Center/maximize/focus/move/app launcher hotkeys still work.
- [ ] `Cmd+Alt+Shift+B` toggles SketchyBar visibility without editing or reloading any window-manager config.

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Hotkeys do nothing | Accessibility permissions | Enable Hammerspoon and Raycast in Accessibility. Restart apps if needed. |
| Hammerspoon keys fail | Config reload/status | Use Hammerspoon menu → `Reload Config`; inspect Hammerspoon Console for Lua errors. |
| Layouts do not move windows | Too few windows or wrong focused screen | Use at least two visible windows on the current screen. |
| Multi-monitor layout applies on wrong screen | Focus/current screen | Focus a window on the intended monitor before applying the layout. |

## Agent notes

- Keep Hammerspoon as the only window-management runtime.
- Safe extension points are Hammerspoon modules, new tests under `test/scripts/`, and docs under `doc/`.
- If adding a layout, update `layouts.lua`, `hotkeys.lua`, tests, and this document.
- If adding a new app launcher binding, update only the Hammerspoon `apps` table unless the app also needs Brewfile installation.
- Always run `bash test/scripts/wm-invariants.sh` after changing window-management behavior.
