#!/bin/sh
# Verifica si se puede crear sesión con el nombre del directorio.
# Exit 0 = nombre disponible, Exit 1 = ya existe (necesita prompt).
pane_path="$1"
dir_name="$(basename "$pane_path")"
dir_name="${dir_name#.}"

if tmux has-session -t "=$dir_name" 2>/dev/null || tmux has-session -t "=_$dir_name" 2>/dev/null; then
  exit 1
fi

tmux new-session -d -s "$dir_name" -c "$pane_path"
tmux switch-client -t "$dir_name"
