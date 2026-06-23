# Aerospace window management

AeroSpace owns workspace switching, move-node-to-workspace, and reload.
Layout presets, per-workspace layout restore, resize, move, focus, app launch, and monitor actions live in Hammerspoon.

This directory is symlinked to `~/.config/aerospace` by `dot self install`.

## Ownership boundaries

- **AeroSpace**: workspace switching, move-node-to-workspace, and reload.
- **Hammerspoon**: layout presets, per-workspace layout restore, resize, directional focus/move, app launcher, monitor focus/move.

AeroSpace has a narrow `exec-on-workspace-change` hook only to notify SketchyBar about the focused workspace. There are no AeroSpace-to-Hammerspoon bridge scripts. Hammerspoon may poll the focused AeroSpace workspace and may float target windows immediately before applying manual layouts, but those AeroSpace CLI calls must be async and timeout-protected.

## Files

- `aerospace.toml`: main AeroSpace config.
- `toggle-sketchybar-gap.sh`: toggles SketchyBar visibility and adjusts `outer.top` gap in `aerospace.toml`.
