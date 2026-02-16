#!/bin/sh
# Saltar a la primera sesión no flotante (ignora las que empiezan con _)
next=$(tmux list-sessions -F '#{session_name}' -f '#{?#{m:_*,#{session_name}},0,1}' | head -1)
if [ -n "$next" ]; then
  tmux switch-client -t "$next"
else
  # No quedan sesiones normales, cerrar tmux
  tmux kill-server
fi
