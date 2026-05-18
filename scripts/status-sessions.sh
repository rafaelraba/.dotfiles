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
		echo -n "#[bg=#7aa2f7,fg=#1a1b26,bold] $session #[bg=#1a1b26,fg=#7aa2f7]#[bg=#1a1b26,fg=#a9b1d6]"
	else
		echo -n "#[fg=#565f89] $session "
	fi
done
