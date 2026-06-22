# Aerospace window management

AeroSpace owns workspaces, focus, movement across monitors, and workspace-to-monitor assignment.

This directory is symlinked to `~/.config/aerospace` by `dot self install`.

## Ownership boundaries

- **AeroSpace**: tiling mode, workspaces, window focus, monitor movement, split controls.
- **Hammerspoon**: absolute-geometry layout presets and resize hotkeys.
- **Shell scripts in `scripts/wm/`**: bridge AeroSpace window IDs to Hammerspoon layout functions.

## Files

- `aerospace.toml`: main AeroSpace config.
- `toggle-sketchybar-gap.sh`: toggles SketchyBar visibility and adjusts `outer.top` gap in `aerospace.toml`.
