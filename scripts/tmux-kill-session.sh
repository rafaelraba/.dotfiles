#!/bin/sh
curr="$1"
# Buscar otra sesión normal (no flotante, no la actual)
next=$(tmux list-sessions -F '#{session_name}' -f '#{?#{m:_*,#{session_name}},0,1}' | grep -v "^${curr}$" | head -1)
if [ -n "$next" ]; then
  tmux switch-client -t "$next"
  tmux kill-session -t "$curr"
else
  # Es la última sesión normal, cerrar todo
  tmux kill-server
fi
