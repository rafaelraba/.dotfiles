# Hammerspoon

Hammerspoon owns layout presets, per-workspace layout restore, resize/center actions, directional focus/move, app launcher, and monitor focus/move.

This directory is symlinked to `~/.hammerspoon` by `dot self install`.

## Modules

- `modules/constants.lua`: shared constants (hyper key, gaps, ratios, resize step, focus thresholds).
- `modules/layouts.lua`: layout presets for the current screen.
- `modules/workspace_layout_restore.lua`: polls the focused AeroSpace workspace, persists explicit Hammerspoon layouts, and restores them when returning to a workspace.
- `modules/resize.lua`: focused window resize and centering helpers.
- `modules/focus.lua`: directional focus/move and monitor helpers.
- `modules/hotkeys.lua`: keyboard bindings for all Hammerspoon-owned actions.

## Ownership boundaries

- **Hammerspoon**: layout presets, per-workspace layout restore, resize/center actions, directional focus/move, app launcher, monitor focus/move.
- **AeroSpace**: workspace switching, move-node-to-workspace, reload, and fixed workspace-to-monitor assignment for workspaces `1..8`.

## Workspace layout restore

The hybrid model is intentionally disciplined:

- Pressing `Cmd+Alt+S` saves `stack-right` for the currently focused AeroSpace workspace.
- Pressing `Cmd+Alt+Shift+S` saves `columns` for the currently focused AeroSpace workspace.
- Pressing `Cmd+Alt+Shift+M` saves `center-main` for the currently focused AeroSpace workspace: the focused window becomes the large center column, and the remaining windows stack into thinner side columns. It requires at least two windows.
- State is persisted at `$HOME/.cache/dotfiles/wm-layouts/state.json` with `schemaVersion = 1`.
- Auto-restore on workspace switch is enabled for explicit layout shortcuts.
- Manual geometry actions clear saved layout state so stale explicit layouts do not overwrite manual window placement.
- Hammerspoon polls `aerospace list-workspaces --focused` every `0.20s` with an async `hs.task`, one in-flight query, and a timeout so AeroSpace IPC cannot freeze Hammerspoon.
- Before restoring, it re-checks the focused workspace and ignores stale generations.
- While restoring, save-on-layout is suppressed to avoid feedback loops.
- Restore is a safe no-op when AeroSpace is missing, no state exists, the saved layout is unknown, or fewer than two current visible windows on the current screen are available.
- The only AeroSpace layout command Hammerspoon uses is the narrow async `layout --window-id ... floating` call needed before applying frames; frame changes happen after float attempts finish or time out.

Do not use AeroSpace `exec-on-workspace-change` hooks or shell scripts to call `hs -c`; those bridge patterns can wedge AeroSpace IPC. The only allowed workspace-change hook is the SketchyBar notification in the AeroSpace config.
