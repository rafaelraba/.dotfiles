#!/usr/bin/env bash
# Muestra las sesiones de tmux como pestañas de proyectos
# Uso: ~/.dotfiles/scripts/status-sessions.sh <session_actual>

current="$1"
bar_bg="#0b0f1a"

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

session_status() {
	~/.dotfiles/scripts/agent-status.sh get "$1" 2>/dev/null || printf 'idle\n'
}

status_bg() {
	local state="$1"

	case "$state" in
		running) printf '#8aadf4' ;;
		blocked) printf '#eed49f' ;;
		done) printf '#a6da95' ;;
		error) printf '#ed8796' ;;
		*) printf '#3b4261' ;;
	esac
}

status_dot() {
	local state="$1"
	local color
	color="$(status_bg "$state")"

	case "$1" in
		running | blocked | done | error) printf '#[fg=%s]●' "$color" ;;
		*) printf '#[fg=#3b4261]●' ;;
	esac
}

tab_bg() {
	local is_current="$1"

	if [ "$is_current" = "true" ]; then
		printf '#363a4f'
	else
		printf '#1f2438'
	fi
}

tab_fg() {
	local is_current="$1"

	if [ "$is_current" = "true" ]; then
		printf '#cad3f5'
	else
		printf '#9aa3bc'
	fi
}

tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F '#{session_created} #{session_name}' 2>/dev/null \
	| sort -n \
	| cut -d ' ' -f 2- \
	| while IFS= read -r session; do
	display_name="$(format_session_name "$session")"
	state="$(session_status "$session")"
	dot="$(status_dot "$state")"

	if [ "$session" = "$current" ]; then
		bg="$(tab_bg true)"
		fg="$(tab_fg true)"
		echo -n "#[bg=$bar_bg,fg=$bg]#[bg=$bg,fg=$fg,bold]  $dot #[bg=$bg,fg=$fg,bold]$display_name  #[bg=$bar_bg,fg=$bg] "
	else
		bg="$(tab_bg false)"
		fg="$(tab_fg false)"
		echo -n "#[bg=$bar_bg,fg=$bg]#[bg=$bg,fg=$fg]  $dot #[bg=$bg,fg=$fg]$display_name  #[bg=$bar_bg,fg=$bg] "
	fi
done
