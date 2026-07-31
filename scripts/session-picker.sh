#!/usr/bin/env bash
set -euo pipefail

# Compact session picker using the Gruvbox Material dark hard palette.
# Usage: ~/.dotfiles/scripts/session-picker.sh [current_session] [sessions_file] [session_count]
#
#   current_session : nombre de la sesión actual (opcional, se detecta automáticamente)
#   sessions_file   : archivo con output pre-capturado de `tmux list-sessions`
#                     (opcional; si no se provee, se consulta a tmux directamente)
#
# El archivo de sesiones evita inconsistencias cuando el script corre dentro
# de un display-popup, que en tmux ≥3.6 puede reportar datos desactualizados.

current="${1:-$(tmux display-message -p '#S' 2>/dev/null || true)}"
sessions_file="${2:-}"
session_count="${3:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
# shellcheck source=agent-status/store.sh
source "$ROOT/agent-status/store.sh"
# shellcheck source=agent-status/order.sh
source "$ROOT/agent-status/order.sh"
agent_status_load_config || exit 0

active_tool() {
	local window_name="$1"
	local command="$2"
	local pane_title="$3"
	local start_command="${4:-}"
	local source="${5:-}"
	local codex_descendant="${6:-}"

	case "$source" in
	claude | codex | opencode | nvim | pi) printf '%s' "$source" ;;
	*)
		case "$pane_title" in
		*π*) printf 'pi' ;;
		*Claude\ Code*) printf 'claude' ;;
		Codex | Codex\ CLI) printf 'codex' ;;
		*)
			case "$command:$start_command" in
			*claude* | *Claude*) printf 'claude' ;;
			codex:* | */codex:* | *:codex | *:/codex | *:codex\ * | *:/codex\ *) printf 'codex' ;;
			opencode:* | *:opencode | *:opencode\ *) printf 'opencode' ;;
			nvim:* | *:nvim | *:nvim\ *) printf 'nvim' ;;
			pi:* | *:pi | *:pi\ *) printf 'pi' ;;
			*) [[ "$codex_descendant" == 1 ]] && printf 'codex' || printf '%s' "$command" ;;
			esac
			;;
		esac
		;;
	esac
}

codex_ancestor_pids() {
	local process_snapshot="$1"

	awk '
		function basename(path, count, parts) {
			count = split(path, parts, "/")
			return parts[count]
		}
		$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
			parent[$1] = $2
			if (basename($3) == "codex") strong[$1] = 1
			for (field = 4; field <= NF; field++) {
				name = basename($field)
				if (name == "codex" || name == "codex.js") strong[$1] = 1
			}
		}
		END {
			for (pid in strong) {
				ancestor = pid
				while (ancestor != "" && !codex[ancestor]) {
					codex[ancestor] = 1
					ancestor = parent[ancestor]
				}
			}
			for (pid in codex) print pid
		}
	' <<<"$process_snapshot"
}

producer_ancestor_pids() {
	local process_snapshot="$1"

	awk '
		function basename(path, count, parts) {
			count = split(path, parts, "/")
			return parts[count]
		}
		$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
			parent[$1] = $2
			for (field = 3; field <= NF; field++) {
				name = basename($field)
				if (name == "claude" || name == "opencode" || name == "pi") strong[name, $1] = 1
			}
		}
		END {
			for (key in strong) {
				split(key, parts, SUBSEP)
				source = parts[1]
				ancestor = parts[2]
				while (ancestor != "" && !live[source, ancestor]) {
					live[source, ancestor] = 1
					ancestor = parent[ancestor]
				}
			}
			for (key in live) {
				split(key, parts, SUBSEP)
				print parts[1] "\t" parts[2]
			}
		}
	' <<<"$process_snapshot"
}

picker_source() {
	local session="$1"
	local pane="$2"
	local safe_session file _ source

	safe_session="$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')"
	file="$PANE_DIR/${safe_session}_${pane//%/_}"
	[[ -f "$file" ]] || return
	IFS=$'\t' read -r _ _ _ source _ < "$file" || true
	printf '%s' "$source"
}

project_name() {
	local path="${1%/}"

	if [[ -z "$path" || "$path" == "/" ]]; then
		printf '/'
		return
	fi

	printf '%s' "${path##*/}"
}

FZF_MODAL_BIND="ctrl-j:down,ctrl-k:up,j:down,k:up,/:change-prompt(  filter › )+unbind(j,k,/)"
FZF_PICKER_HEADER='Enter switch · j/k or ↑/↓ move · Ctrl-j/k navigate · / search · Esc close'

BG="#282828"
FG="#a89984"
FG_ACTIVE="#ebdbb2"
SUBTLE="#928374"
AMBER="#d79921"
DIM="#504945"

state_color() {
	case "$1" in
		running) printf '125;174;163' ;;
		permission) printf '238;212;159' ;;
		blocked | waiting_for_input) printf '216;166;87' ;;
		done) printf '169;182;101' ;;
		error) printf '234;105;98' ;;
		*) printf '146;131;116' ;;
	esac
}

pane_state() {
	local session="$1" pane="$2" safe_session file

	safe_session="$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')"
	file="$PANE_DIR/${safe_session}_${pane//%/_}"
	store_effective "$file"
}

state_dot() {
	local color

	[[ -n "${NO_COLOR:-}${AGENT_STATUS_NO_COLOR:-}" ]] && { printf '●'; return; }
	color="$(state_color "$1")"
	printf '\033[38;2;%sm●\033[0m' "$color"
}

# Match Herdr's navigator: the focused row is a single amber surface, not a
# muted background behind otherwise independently colored tree fragments.
FZF_COLORS="bg:${BG},bg+:${AMBER},gutter:${BG},fg:${FG},fg+:${BG}"
FZF_COLORS="${FZF_COLORS},hl:${AMBER},hl+:${BG},border:${DIM},label:${FG}"
FZF_COLORS="${FZF_COLORS},header:${SUBTLE},pointer:${BG},marker:${BG},prompt:${AMBER}"
FZF_COLORS="${FZF_COLORS},spinner:${AMBER},info:${SUBTLE},query:${FG_ACTIVE},separator:${DIM},scrollbar:${SUBTLE}"

# Bulk snapshots have pane identity in field four; retain the legacy picker for
# older session-list captures.
IFS=$'\t' read -r _ _ _ snapshot_pane _ < "${sessions_file:-/dev/null}" || true
if [[ "$snapshot_pane" == %* ]]; then
	picker_rows() {
		local last_session='' session index window pane command title path start_command pane_pid source tool state dot marker sep=$'\037'
		local process_snapshot='' codex_pids='' producer_pids='' codex_descendant source_live
		if cut -f9 "$sessions_file" | grep -qE '^[0-9]+$'; then
			process_snapshot="$(ps -axo pid=,ppid=,comm=,args= 2>/dev/null || true)"
			codex_pids="$(codex_ancestor_pids "$process_snapshot")"
			producer_pids="$(producer_ancestor_pids "$process_snapshot")"
		fi
		while IFS=$'\034' read -r session index window pane command title path start_command pane_pid; do
			[[ -n "$session" && "$pane" == %* ]] || continue
			[[ "$session" == _* ]] && continue
			command="${command//$'\t'/ }"; title="${title//$'\t'/ }"; path="${path//$'\t'/ }"; start_command="${start_command//$'\t'/ }"
			if [[ "$session" != "$last_session" ]]; then
				marker='  '; [[ "$session" == "$current" ]] && marker='◆ '
				printf 's%s%s\t%s▾ %s\t%s\n' "$sep" "$session" "$marker" "$session" "$path"
				last_session="$session"
			fi
			source="$(picker_source "$session" "$pane")"
			codex_descendant=0
			if [[ "$pane_pid" =~ ^[0-9]+$ ]]; then
				case $'\n'"$codex_pids"$'\n' in
				*$'\n'"$pane_pid"$'\n'*) codex_descendant=1 ;;
				esac
			fi
			source_live=0
			case $'\n'"$producer_pids"$'\n' in
			*$'\n'"$source"$'\t'"$pane_pid"$'\n'*) source_live=1 ;;
			esac
			if [[ "$codex_descendant" == 1 && "$source_live" == 0 ]]; then
				case "$source" in claude | opencode | pi) source='' ;; esac
			fi
			tool="$(active_tool "$window" "$command" "$title" "$start_command" "$source" "$codex_descendant")"
			state="$(pane_state "$session" "$pane")"
			dot="$(state_dot "$state")"
			printf 'p%s%s\t  └─ %s %s\t%s\n' "$sep" "$pane" "$dot" "$tool" "$path"
		done < <(agent_status_order_session_rows < "$sessions_file" | tr '\t' '\034')
	}
	selected="$({ picker_rows || true; } | fzf --ansi --highlight-line --layout=reverse --border=rounded --border-label=" workspace · $session_count sessions " --delimiter=$'\t' --with-nth=2 --prompt='  navigate › ' --header="$FZF_PICKER_HEADER" --pointer='❯ ' --cycle --bind="$FZF_MODAL_BIND" --preview='printf "  %s\\n" {3}' --preview-window='down,1,wrap,border-top' --no-info --no-sort --color="${FZF_COLORS}")" || exit 0
	target="${selected%%$'\t'*}"
	type="${target%%$'\037'*}"; payload="${target#*$'\037'}"
	case "$type" in
		s) tmux switch-client -t "=$payload" ;;
		p) tmux switch-client -t "$payload" ;;
	esac
	exit 0
fi

agent_state() {
	"$ROOT/agent-status.sh" summary "$1" 2>/dev/null || printf 'state=idle\n'
}

initial_selection_position() {
	local names=()
	local name
	local current_index=-1
	local count i

	if [[ -n "${sessions_file:-}" && -r "$sessions_file" ]]; then
		while IFS=$'\t' read -r name _; do
			[[ -n "$name" && "$name" != _* ]] && names+=("$name")
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
	local paths=()
	local tools=()
	local name path window_name command pane_title tool project
	local current_index=-1
	local count start offset i summary state state_color symbol label name_width tool_width

	# Leer sesiones desde archivo pre-capturado o consultar tmux directamente
	if [[ -n "${sessions_file:-}" && -r "$sessions_file" ]]; then
		while IFS=$'\t' read -r name _ _ path window_name command pane_title; do
			[[ -n "$name" ]] || continue
			[[ "$name" == _* ]] && continue
			if [[ "$name" == "$current" ]]; then
				current_index=${#names[@]}
			fi
			names+=("$name")
			tools+=("$(active_tool "$window_name" "$command" "$pane_title")")
			paths+=("$path")
		done < <(agent_status_order_session_rows < "$sessions_file")
	else
		while IFS=$'\t' read -r name _ _ path window_name command pane_title; do
			[[ -n "$name" ]] || continue
			if [[ "$name" == "$current" ]]; then
				current_index=${#names[@]}
			fi
			names+=("$name")
			tools+=("$(active_tool "$window_name" "$command" "$pane_title")")
			paths+=("$path")
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

	start=0
	if ((current_index >= 0)); then
		start=$current_index
	fi

	for ((offset = 0; offset < count; offset++)); do
		i=$(((start + offset) % count))
		name="${names[$i]}"
		tool="${tools[$i]}"
		project="${paths[$i]}"
		summary="$(agent_state "$name")"
		state="${summary#state=}"
		state="${state%%$'\t'*}"
		state_color="$(state_color "$state")"
		symbol="$(agent_status_state_symbol "$state")"
		label="$(agent_status_state_label "$state")"

		if [[ "$name" == "$current" ]]; then
			# The active session is a distinct visual layer, not a state color.
			row_prefix=$'\033[48;2;60;56;46m'
			name_color="1;38;2;189;174;147"
			marker=$'\033[38;2;215;153;33m› '
		else
			row_prefix=""
			name_color="38;2;168;153;132"
			marker="  "
		fi
		win_color="38;2;189;174;147"

		if [[ -n "${NO_COLOR:-}${AGENT_STATUS_NO_COLOR:-}" ]]; then
			printf '%s\t%s%-*s  %-*s  %s %s\t%s\n' "$name" "$marker" "$name_width" "$name" "$tool_width" "$tool" "$symbol" "$label" "$project"
		else
			printf '%s\t%s%s\033[%sm%-*s  \033[38;2;189;174;147m%-*s  \033[38;2;%sm%s %-8s\033[0m\t%s\n' \
				"$name" "$row_prefix" "$marker" "$name_color" "$name_width" "$name" "$tool_width" "$tool" "$state_color" "$symbol" "$label" "$project"
		fi
	done
}

initial_selection="$(initial_selection_position)"

selected="$({ session_rows || true; } |
	fzf \
		--ansi \
		--highlight-line \
		--layout=reverse \
		--border=rounded \
		--border-label=" workspace · $session_count sessions " \
		--delimiter=$'\t' \
		--with-nth=2 \
		--prompt='  navigate › ' \
		--pointer='❯ ' \
		--marker='• ' \
		--ellipsis='…' \
		--cycle \
		--bind="start:pos($initial_selection)" \
		--bind="$FZF_MODAL_BIND" \
		--preview='printf "  %s\\n" {3}' \
		--preview-window='down,1,wrap,border-top' \
		--header="$FZF_PICKER_HEADER" \
		--scroll-off=1 \
		--no-info \
		--tiebreak=index \
		--no-sort \
		--color="${FZF_COLORS}" |
	cut -f1)" || exit 0

[[ -n "$selected" ]] && tmux switch-client -t "$selected"
