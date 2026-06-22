#!/usr/bin/env bash
set -euo pipefail

# Compact session picker using the Gruvbox Material dark hard palette.
# Usage: ~/.dotfiles/scripts/session-picker.sh [current_session] [sessions_file]
#
#   current_session : nombre de la sesión actual (opcional, se detecta automáticamente)
#   sessions_file   : archivo con output pre-capturado de `tmux list-sessions`
#                     (opcional; si no se provee, se consulta a tmux directamente)
#
# El archivo de sesiones evita inconsistencias cuando el script corre dentro
# de un display-popup, que en tmux ≥3.6 puede reportar datos desactualizados.

current="${1:-$(tmux display-message -p '#S' 2>/dev/null || true)}"
sessions_file="${2:-}"

# Gruvbox Material dark hard.
BG="#1d2021"
BG_ACTIVE="#282828"
FG="#d4be98"
FG_ACTIVE="#ddc7a1"
SUBTLE="#928374"
GREEN="#a9b665"
BLUE="#7daea3"
VIOLET="#d3869b"
RED="#ea6962"
ORANGE="#d8a657"
DIM="#665c54"

FZF_COLORS="bg:${BG},bg+:${BG_ACTIVE},gutter:${BG},fg:${FG},fg+:${FG_ACTIVE}"
FZF_COLORS="${FZF_COLORS},hl:${GREEN},hl+:${GREEN},border:${GREEN},label:${VIOLET}"
FZF_COLORS="${FZF_COLORS},header:${SUBTLE},pointer:${ORANGE},marker:${FG_ACTIVE},prompt:${GREEN}"
FZF_COLORS="${FZF_COLORS},spinner:${BLUE},info:${SUBTLE},query:${FG_ACTIVE},separator:${SUBTLE},scrollbar:${SUBTLE}"

session_rows() {
	local names=()
	local attacheds=()
	local windows=()
	local paths=()
	local name attached window_count path
	local current_index=-1
	local count start offset i state state_color project

	# Leer sesiones desde archivo pre-capturado o consultar tmux directamente
	if [[ -n "${sessions_file:-}" && -r "$sessions_file" ]]; then
		while IFS=$'\t' read -r name window_count attached path; do
			[[ -n "$name" ]] || continue
			if [[ "$name" == "$current" ]]; then
				current_index=${#names[@]}
			fi
			names+=("$name")
			attacheds+=("$attached")
			windows+=("$window_count")
			paths+=("$path")
		done < "$sessions_file"
	else
		while IFS=$'\t' read -r name window_count attached path; do
			[[ -n "$name" ]] || continue
			if [[ "$name" == "$current" ]]; then
				current_index=${#names[@]}
			fi
			names+=("$name")
			attacheds+=("$attached")
			windows+=("$window_count")
			paths+=("$path")
		done < <(
			tmux list-sessions \
				-f '#{?#{m:_*,#{session_name}},0,1}' \
				-F $'#{session_name}\t#{session_windows}\t#{session_attached}\t#{pane_current_path}' 2>/dev/null
		)
	fi

	count=${#names[@]}
	((count > 0)) || return 0

	# Rotate the list so Enter switches to the next session by default.
	start=0
	if ((count > 1)); then
		if ((current_index >= 0)); then
			start=$(((current_index + 1) % count))
		else
			for ((idx = 0; idx < count; idx++)); do
				if ((attacheds[idx] > 0)); then
					start=$(((idx + 1) % count))
					break
				fi
			done
		fi
	fi

	for ((offset = 0; offset < count; offset++)); do
		i=$(((start + offset) % count))
		name="${names[$i]}"
		attached="${attacheds[$i]}"
		window_count="${windows[$i]}"
		path="${paths[$i]}"
		project="${path##*/}"
		[[ -n "$project" ]] || project="/"

		if ((attached > 0)); then
			state="online"
			state_color="169;182;101"
		else
			state="idle"
			state_color="146;131;116"
		fi

		if ((attached > 0)); then
			# Online: warm, alive, bold
			name_color="1;38;2;221;199;161"
			win_color="38;2;125;174;163"
			path_color="38;2;146;131;116"
		else
			# Idle: dimmed, readable gray
			name_color="38;2;146;131;116"
			win_color="38;2;102;92;84"
			path_color="38;2;80;73;69"
		fi

		if [[ "$name" == "$current" ]]; then
			# Current session gets a subtle warm marker.
			marker=$'\033[38;2;216;166;87m●\033[0m '
		else
			marker="  "
		fi

		printf '%s\t%s\033[%sm%-20.20s\033[0m  \033[%sm󰓩 %2s\033[0m  \033[%sm󰉋 %-13.13s\033[0m  \033[38;2;%sm● %s\033[0m\n' \
			"$name" "$marker" "$name_color" "$name" "$win_color" "$window_count" "$path_color" "$project" "$state_color" "$state"
	done
}

selected="$({ session_rows || true; } |
	fzf \
		--ansi \
		--layout=reverse \
		--no-border \
		--delimiter=$'\t' \
		--with-nth=2.. \
		--prompt='  switch › ' \
		--pointer='❯ ' \
		--marker='• ' \
		--ellipsis='…' \
		--cycle \
		--scroll-off=1 \
		--no-info \
		--header='  name                  windows  project        state     ↑/↓ navigate  ↵ switch  esc cancel' \
		--tiebreak=index \
		--no-sort \
		--color="${FZF_COLORS}" |
	cut -f1)" || exit 0

[[ -n "$selected" ]] && tmux switch-client -t "$selected"
