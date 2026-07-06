#!/usr/bin/env bash
# Muestra las sesiones de tmux como pestañas de proyectos
# Uso: ~/.dotfiles/scripts/status-sessions.sh <session_actual>

current="$1"

format_session_name() {
	local name="$1"
	local max_length=26
	local head_length=14
	local tail_length=9

	if [ "${#name}" -le "$max_length" ]; then
		printf '%s' "$name"
		return
	fi

	printf '%s…%s' "${name:0:$head_length}" "${name: -$tail_length}"
}

tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F '#{session_created} #{session_name}' 2>/dev/null \
	| sort -n \
	| cut -d ' ' -f 2- \
	| while IFS= read -r session; do
	display_name="$(format_session_name "$session")"

	if [ "$session" = "$current" ]; then
		echo -n "#[bg=#101320,fg=#a6da95]#[bg=#a6da95,fg=#101320,bold]  $display_name #[bg=#101320,fg=#a6da95] "
	else
		echo -n "#[bg=#101320,fg=#1f2438]#[bg=#1f2438,fg=#9aa3bc] $display_name #[bg=#101320,fg=#1f2438] "
	fi
done
