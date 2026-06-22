#!/usr/bin/env bash
# Muestra las sesiones de tmux como pestañas de proyectos
# Uso: ~/.dotfiles/scripts/status-sessions.sh <session_actual>

current="$1"
first=1

tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F '#{session_name}' 2>/dev/null | while IFS= read -r session; do
	if [ "$first" -eq 1 ]; then
		first=0
	else
		echo -n " "
	fi

	if [ "$session" = "$current" ]; then
		echo -n "#[bg=#83a598,fg=#1d2021,bold] $session #[bg=#1d2021,fg=#83a598]#[bg=#1d2021,fg=#d4be98]"
	else
		echo -n "#[fg=#665c54] $session "
	fi
done
