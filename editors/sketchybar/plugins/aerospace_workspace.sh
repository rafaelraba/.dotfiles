#!/usr/bin/env bash

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

workspace="$1"
monitor="$2"
visible="$(aerospace list-workspaces --monitor "$monitor" --visible 2>/dev/null || true)"

if [ "$workspace" = "$visible" ]; then
  sketchybar --set "$NAME" \
    label.color=0xff11111b \
    label.font="SF Pro:Bold:13.0" \
    background.drawing=on \
    background.color=0xffb4befe \
    background.border_color=0x99cba6f7 \
    background.border_width=1
else
  sketchybar --set "$NAME" \
    label.color=0xff9399b2 \
    label.font="SF Pro:Semibold:13.0" \
    background.drawing=on \
    background.color=0x00181825 \
    background.border_color=0x00000000 \
    background.border_width=0
fi
