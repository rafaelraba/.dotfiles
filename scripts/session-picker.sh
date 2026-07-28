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
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
# shellcheck source=agent-status/store.sh
source "$ROOT/agent-status/store.sh"
# shellcheck source=agent-status/order.sh
source "$ROOT/agent-status/order.sh"
agent_status_load_config || exit 0

# Bulk snapshots have pane identity in field four; retain the legacy picker for
# older session-list captures.
IFS=$'\t' read -r _ _ _ snapshot_pane _ < "${sessions_file:-/dev/null}" || true
if [[ "$snapshot_pane" == %* ]]; then
	picker_state() {
		local session="$1" pane="$2" safe_session
		safe_session="$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')"
		store_effective "$PANE_DIR/${safe_session}_${pane//%/_}"
	}
	picker_dot_color() {
		case "$1" in running) printf '125;174;163' ;; permission) printf '238;212;159' ;; waiting_for_input|blocked) printf '216;166;87' ;; done) printf '169;182;101' ;; error) printf '234;105;98' ;; *) printf '146;131;116' ;; esac
	}
	picker_rows() {
		local last_session='' last_window='' session index window pane command title path state marker sep=$'\037'
		while IFS=$'\t' read -r session index window pane command title path; do
			[[ -n "$session" && "$pane" == %* ]] || continue
			command="${command//$'\t'/ }"; title="${title//$'\t'/ }"; path="${path//$'\t'/ }"
			if [[ "$session" != "$last_session" ]]; then
				marker='  '; [[ "$session" == "$current" ]] && marker='› '
				printf 's%s%s\t%s▾ %s\n' "$sep" "$session" "$marker" "$session"; last_session="$session"; last_window=''
			fi
			if [[ "$index:$window" != "$last_window" ]]; then printf 'w%s%s%s%s\t  ├─ %s · %s\n' "$sep" "$session" "$sep" "$index" "$index" "$window"; last_window="$index:$window"; fi
			state="$(picker_state "$session" "$pane")"
			printf 'p%s%s\t  │  \033[38;2;%sm●\033[0m %s%s\n' "$sep" "$pane" "$(picker_dot_color "$state")" "$command" "${path:+ · $path}"
		done < <(agent_status_order_session_rows < "$sessions_file")
	}
	selected="$({ picker_rows || true; } | fzf --ansi --layout=reverse --no-border --delimiter=$'\t' --with-nth=2.. --prompt=' search panes › ' --header='Enter switch · ↑/↓ move · Esc close' --pointer='❯ ' --cycle --no-info --no-sort)" || exit 0
	target="${selected%%$'\t'*}"
	type="${target%%$'\037'*}"; payload="${target#*$'\037'}"
	case "$type" in
		s) tmux switch-client -t "=$payload" ;;
		w) session="${payload%%$'\037'*}"; index="${payload#*$'\037'}"; tmux switch-client -t "=$session" && tmux select-window -t ":$index" ;;
		p) tmux switch-client -t "$payload" ;;
	esac
	exit 0
fi

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

agent_state() {
	"$ROOT/agent-status.sh" summary "$1" 2>/dev/null || printf 'state=idle\n'
}

state_color() {
	case "$1" in
		running) printf '125;174;163' ;;
		blocked) printf '216;166;87' ;;
		done) printf '169;182;101' ;;
		error) printf '234;105;98' ;;
		*) printf '146;131;116' ;;
	esac
}

active_tool() {
	local window_name="$1"
	local command="$2"
	local pane_title="$3"

	case "$pane_title" in
	π*) printf 'pi' ;;
	*)
		case "$window_name" in
		opencode | nvim | claude | pi) printf '%s' "$window_name" ;;
		*) printf '%s' "$command" ;;
		esac
		;;
	esac
}

project_name() {
	local path="${1%/}"

	if [[ -z "$path" || "$path" == "/" ]]; then
		printf '/'
		return
	fi

	printf '%s' "${path##*/}"
}

initial_selection_position() {
	local names=()
	local name
	local current_index=-1
	local count i

	if [[ -n "${sessions_file:-}" && -r "$sessions_file" ]]; then
		while IFS=$'\t' read -r name _; do
			[[ -n "$name" ]] && names+=("$name")
		done < <(agent_status_order_session_rows < "$sessions_file")
	else
		while IFS= read -r name; do
			[[ -n "$name" ]] && names+=("$name")
		done < <(tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F '#{session_name}' 2>/dev/null | agent_status_order_sessions)
	fi

	count=${#names[@]}
	for i in "${!names[@]}"; do
		if [[ "${names[$i]}" == "$current" ]]; then
			current_index=$i
			break
		fi
	done

	if ((count == 0 || current_index == -1)); then
		printf '1'
		return
	fi

	# The active session is first; fzf positions are one-based, so select next.
	if ((count > 1)); then
		printf '2'
	else
		printf '1'
	fi
}

session_rows() {
	local names=()
	local projects=()
	local tools=()
	local name path window_name command pane_title tool project
	local current_index=-1
	local count start offset i summary state state_color symbol label name_width tool_width project_width

	# Leer sesiones desde archivo pre-capturado o consultar tmux directamente
	if [[ -n "${sessions_file:-}" && -r "$sessions_file" ]]; then
		while IFS=$'\t' read -r name _ _ path window_name command pane_title; do
			[[ -n "$name" ]] || continue
			if [[ "$name" == "$current" ]]; then
				current_index=${#names[@]}
			fi
			names+=("$name")
			tools+=("$(active_tool "$window_name" "$command" "$pane_title")")
			projects+=("$(project_name "$path")")
		done < <(agent_status_order_session_rows < "$sessions_file")
	else
		while IFS=$'\t' read -r name _ _ path window_name command pane_title; do
			[[ -n "$name" ]] || continue
			if [[ "$name" == "$current" ]]; then
				current_index=${#names[@]}
			fi
			names+=("$name")
			tools+=("$(active_tool "$window_name" "$command" "$pane_title")")
			projects+=("$(project_name "$path")")
		done < <(
			tmux list-sessions \
				-f '#{?#{m:_*,#{session_name}},0,1}' \
				-F $'#{session_name}\t#{session_windows}\t#{session_attached}\t#{pane_current_path}\t#{window_name}\t#{pane_current_command}\t#{pane_title}' 2>/dev/null \
				| agent_status_order_session_rows
		)
	fi

	count=${#names[@]}
	((count > 0)) || return 0

	name_width=18
	tool_width=8
	project_width=8
	for name in "${names[@]}"; do
		if ((${#name} > name_width)); then
			name_width=${#name}
		fi
	done
	for tool in "${tools[@]}"; do
		if ((${#tool} > tool_width)); then
			tool_width=${#tool}
		fi
	done
	for project in "${projects[@]}"; do
		if ((${#project} > project_width)); then
			project_width=${#project}
		fi
	done

	start=0
	if ((current_index >= 0)); then
		start=$current_index
	fi

	for ((offset = 0; offset < count; offset++)); do
		i=$(((start + offset) % count))
		name="${names[$i]}"
		tool="${tools[$i]}"
		project="${projects[$i]}"
		summary="$(agent_state "$name")"
		state="${summary#state=}"
		state="${state%%$'\t'*}"
		state_color="$(state_color "$state")"
		symbol="$(agent_status_state_symbol "$state")"
		label="$(agent_status_state_label "$state")"

		if [[ "$name" == "$current" ]]; then
			# The active session is a distinct visual layer, not a state color.
			row_prefix=$'\033[48;2;50;45;64m'
			name_color="1;38;2;221;199;161"
			marker=$'\033[38;2;211;134;155m› '
		else
			row_prefix=""
			name_color="38;2;146;131;116"
			marker="  "
		fi
		win_color="38;2;125;174;163"

		if [[ -n "${NO_COLOR:-}${AGENT_STATUS_NO_COLOR:-}" ]]; then
			printf '%s\t%s%-*s  %-*s  %-*s  %s %s\n' "$name" "$marker" "$name_width" "$name" "$tool_width" "$tool" "$project_width" "$project" "$symbol" "$label"
		else
			printf '%s\t%s%s\033[%sm%-*s  \033[38;2;125;174;163m%-*s  \033[38;2;146;131;116m󰉋 %-*s  \033[38;2;%sm%s %-8s\033[0m\n' \
				"$name" "$row_prefix" "$marker" "$name_color" "$name_width" "$name" "$tool_width" "$tool" "$project_width" "$project" "$state_color" "$symbol" "$label"
		fi
	done
}

initial_selection="$(initial_selection_position)"

selected="$({ session_rows || true; } |
	fzf \
		--ansi \
		--layout=reverse \
		--no-border \
		--delimiter=$'\t' \
		--with-nth=2.. \
		--prompt='  filter › ' \
		--pointer='❯ ' \
		--marker='• ' \
		--ellipsis='…' \
		--cycle \
		--bind="start:pos($initial_selection)" \
		--scroll-off=1 \
		--no-info \
		--tiebreak=index \
		--no-sort \
		--color="${FZF_COLORS}" |
	cut -f1)" || exit 0

[[ -n "$selected" ]] && tmux switch-client -t "$selected"
