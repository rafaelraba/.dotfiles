# Hammerspoon

Hammerspoon owns layout presets, resize/center actions, directional focus/move, app launcher, monitor focus/move, SketchyBar visibility toggling, and a thin proxy to native macOS Desktop shortcuts.

This directory is symlinked to `~/.hammerspoon` by `dot self install`.

## Modules

- `modules/constants.lua`: shared constants (hyper key, gaps, ratios, resize step, focus thresholds).
- `modules/layouts.lua`: layout presets for the current screen.
- `modules/workspace_layout_restore.lua`: deprecated no-op compatibility module; not started at runtime.
- `modules/resize.lua`: focused window resize and centering helpers.
- `modules/focus.lua`: directional focus/move and monitor helpers.
- `modules/hotkeys.lua`: keyboard bindings for all Hammerspoon-owned actions.

## Ownership boundaries

- **Hammerspoon**: layout presets, resize/center actions, directional focus/move, app launcher, monitor focus/move, SketchyBar visibility toggling, and `Cmd+Alt+1..0` proxy shortcuts.
- **macOS Spaces**: native desktop/workspace behavior through Mission Control `Ctrl+1..0` shortcuts.

## Workspace layout restore

Per-workspace layout restore is disabled:

- Pressing `Cmd+Alt+S` applies `stack-right` to the current visible windows.
- Pressing `Cmd+Alt+Shift+S` applies `columns` to the current visible windows.
- Pressing `Cmd+Alt+Shift+M` applies `center-main`: the focused window becomes the large center column, and the remaining windows stack into thinner side columns. It requires at least two windows.
- Layout shortcuts do not save per-workspace state.
- Hammerspoon does not depend on an external workspace manager.
- Native macOS Spaces behavior is accepted; do not add fragile workspace restore through `hs.spaces`.
- `Cmd+Alt+1..0` sends native Mission Control `Ctrl+1..0`; enable `Switch to Desktop 1..10` in System Settings first.

Known tradeoff: native macOS Spaces do not provide deterministic repo-managed workspace IDs, workspace-to-monitor assignment, or move-to-workspace shortcuts.

`Cmd+Alt+Shift+B` runs `scripts/wm/toggle-sketchybar.sh`, which resolves `sketchybar` through a controlled GUI-safe PATH and toggles only SketchyBar visibility.
