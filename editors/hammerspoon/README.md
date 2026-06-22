# Hammerspoon

Hammerspoon owns absolute-geometry layout presets and resize hotkeys.

This directory is symlinked to `~/.hammerspoon` by `dot self install`.

## Modules

- `modules/constants.lua`: shared constants (hyper key, gaps, ratios, resize step).
- `modules/layouts.lua`: layout presets exposed as global functions for `hs -c` calls.
- `modules/resize.lua`: focused window resize helper.
- `modules/hotkeys.lua`: `cmd+alt+=/-` resize bindings.

## Ownership boundaries

- **Hammerspoon**: absolute geometry layout presets, resize.
- **AeroSpace**: workspaces, focus, movement across monitors.
- **Shell scripts in `scripts/wm/`**: bridge AeroSpace window IDs to Hammerspoon layout functions.
