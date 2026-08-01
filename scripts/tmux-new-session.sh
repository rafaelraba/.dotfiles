#!/bin/sh
# Verifica si se puede crear sesión con el nombre del directorio.
# Exit 0 = nombre disponible, Exit 1 = ya existe (necesita prompt).
pane_path="$1"
target_client="${2:-}"
target_pane="${3:-$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)}"
window_width="${4:-$(tmux display-message -p '#{window_width}' 2>/dev/null || printf '80')}"
window_height="${5:-$(tmux display-message -p '#{window_height}' 2>/dev/null || printf '24')}"
popup_script="$HOME/.dotfiles/scripts/tmux-new-session-popup.sh"
dir_name="$(basename "$pane_path")"
dir_name="${dir_name#.}"

if tmux has-session -t "=$dir_name" 2>/dev/null || tmux has-session -t "=_$dir_name" 2>/dev/null; then
  case "$window_width:$window_height" in
    *[!0-9:]* | :* | *:) window_width=80; window_height=24 ;;
  esac
  [ -n "$target_pane" ] || { tmux display-message "Unable to locate the source pane"; exit 1; }

  float_width=56
  float_height=6
  [ "$window_width" -gt 60 ] || float_width=$((window_width - 4))
  [ "$window_height" -gt 10 ] || float_height=$((window_height - 4))
  [ "$float_width" -ge 20 ] || float_width=20
  [ "$float_height" -ge 4 ] || float_height=4
  float_x=$(((window_width - float_width) / 2))
  float_y=$(((window_height - float_height) / 2))

  float_pane=$(tmux new-pane -P -F '#{pane_id}' -f \
    -c "$pane_path" -x "$float_width" -y "$float_height" -X "$float_x" -Y "$float_y" \
    -s "bg=#1d2021,fg=#d4be98" -S "fg=#7aa2f7" -R "fg=#7aa2f7" \
    -t "$target_pane" "$popup_script" "$target_client")
  tmux set-option -p -t "$float_pane" @new_session_picker 1
  tmux select-pane -t "$float_pane"
  exit 0
fi

tmux new-session -d -s "$dir_name" -c "$pane_path"
if [ -n "$target_client" ]; then
  tmux switch-client -c "$target_client" -t "=$dir_name"
else
  tmux switch-client -t "=$dir_name"
fi
