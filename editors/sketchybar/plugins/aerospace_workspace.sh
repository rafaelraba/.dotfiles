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
    background.color=0xff89b4fa \
    background.border_color=0xffb4befe \
    background.border_width=1 \
    background.shadow.drawing=on \
    background.shadow.color=0x8889b4fa \
    background.shadow.angle=270 \
    background.shadow.distance=3
else
  sketchybar --set "$NAME" \
    label.color=0xff9399b2 \
    label.font="SF Pro:Semibold:13.0" \
    background.drawing=on \
    background.color=0x2220202a \
    background.border_color=0x33454a5f \
    background.border_width=1 \
    background.shadow.drawing=off
fi
