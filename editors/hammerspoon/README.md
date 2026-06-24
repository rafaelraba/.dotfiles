# Hammerspoon

Hammerspoon owns only lightweight macOS automations that are not handled by the dedicated window manager.

This directory is symlinked to `~/.hammerspoon` by `dot self install`.

## Modules

- `modules/constants.lua`: shared constants (hyper key, gaps, ratios, resize step, focus thresholds).
- `modules/layouts.lua`: legacy layout presets kept for reference; not loaded at runtime.
- `modules/workspace_layout_restore.lua`: deprecated no-op compatibility module; not started at runtime.
- `modules/resize.lua`: legacy focused window resize and centering helpers; not loaded at runtime.
- `modules/focus.lua`: legacy directional focus/move and monitor helpers; not loaded at runtime.
- `modules/hotkeys.lua`: keyboard bindings for all Hammerspoon-owned actions.

## Ownership boundaries

- **AeroSpace**: tiling, layouts, resize, focus/move, workspaces, workspace-to-monitor behavior.
- **Hammerspoon**: app launcher and SketchyBar visibility toggling.
- **Raycast/Rectangle**: optional floating-window or launcher workflows that do not conflict with AeroSpace bindings.

## Workspace layout restore

Per-workspace layout restore is disabled. Hammerspoon should not bind shortcuts for layouts, resize, window focus, monitor movement, or native Spaces proxies; those responsibilities belong to AeroSpace.

`Cmd+Alt+Shift+B` runs `scripts/wm/toggle-sketchybar.sh`, which resolves `sketchybar` through a controlled GUI-safe PATH and toggles only SketchyBar visibility.
