#!/bin/sh
# Verifica si se puede crear sesión con el nombre del directorio.
# Exit 0 = nombre disponible, Exit 1 = ya existe (necesita prompt).
pane_path="$1"
client_tty="${2:-}"
popup_script="$HOME/.dotfiles/scripts/tmux-new-session-popup.sh"
dir_name="$(basename "$pane_path")"
dir_name="${dir_name#.}"

if tmux has-session -t "=$dir_name" 2>/dev/null || tmux has-session -t "=_$dir_name" 2>/dev/null; then
  tmux display-popup -t "$client_tty" -d "$pane_path" -w 54 -h 4 -b rounded -s "bg=#1d2021,fg=#d4be98" -S "fg=#504945" -E "$popup_script"
  exit 0
fi

tmux new-session -d -s "$dir_name" -c "$pane_path"
tmux switch-client -t "=$dir_name"
