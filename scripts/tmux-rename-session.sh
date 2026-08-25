#!/bin/sh
set -eu

target_session="${1:-}"
current_name="${2:-}"
target_client="${3:-}"
pane_path="${4:-}"
target_pane="${5:-$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)}"
window_width="${6:-$(tmux display-message -p '#{window_width}' 2>/dev/null || printf '80')}"
window_height="${7:-$(tmux display-message -p '#{window_height}' 2>/dev/null || printf '24')}"
popup_script="$HOME/.dotfiles/scripts/tmux-rename-session-popup.sh"

if [ -z "$target_session" ] || [ -z "$current_name" ] || [ -z "$target_client" ] || [ -z "$pane_path" ] || [ -z "$target_pane" ]; then
  tmux display-message "Unable to locate the session to rename"
  exit 1
fi

case "$window_width:$window_height" in
  *[!0-9:]* | :* | *:) window_width=80; window_height=24 ;;
esac

float_width=56
float_height=1
[ "$window_width" -gt 60 ] || float_width=$((window_width - 4))
[ "$window_height" -gt 10 ] || float_height=$((window_height - 4))
[ "$float_width" -ge 20 ] || float_width=20
[ "$float_height" -ge 1 ] || float_height=1
float_x=$(((window_width - float_width) / 2))
float_y=$(((window_height - float_height) / 2))

float_pane=$(tmux new-pane -P -F '#{pane_id}' -f \
  -c "$pane_path" -x "$float_width" -y "$float_height" -X "$float_x" -Y "$float_y" \
  -s "bg=#1d2021,fg=#d4be98" -S "fg=#7aa2f7" -R "fg=#7aa2f7" \
  -t "$target_pane" "$popup_script" "$target_session" "$current_name" "$target_client")
tmux set-option -p -t "$float_pane" @rename_session_picker 1
tmux select-pane -t "$float_pane"
