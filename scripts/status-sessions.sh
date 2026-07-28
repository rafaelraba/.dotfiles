#!/usr/bin/env bash
# Muestra el contexto de la sesión actual y cuántas sesiones adicionales hay.
# Uso: ~/.dotfiles/scripts/status-sessions.sh <session_actual>

current="$1"
bar_bg="#0b0f1a"
max_visible_sessions=3
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
# shellcheck source=agent-status/order.sh
source "$ROOT/agent-status/order.sh"
agent_status_load_config || exit 0

compact_session_name() {
	local name="$1"
	local max_length=14
	local normalized first_word last_word
	local -a words

	if [ "${#name}" -le "$max_length" ]; then
		printf '%s' "$name"
		return
	fi

	normalized="${name//[_-]/ }"
	read -r -a words <<< "$normalized"
	first_word="${words[0]}"
	last_word="${words[${#words[@]} - 1]}"

	if [ "${#words[@]}" -gt 1 ]; then
		printf '%s…%s' "${first_word:0:8}" "${last_word:0:4}"
		return
	fi

	printf '%s…%s' "${name:0:8}" "${name: -4}"
}

session_status() {
	"$ROOT/agent-status.sh" summary "$1" 2>/dev/null || printf 'state=idle\n'
}

status_bg() {
	local state="$1"

	case "$state" in
		running) printf '#8aadf4' ;;
		permission) printf '#eed49f' ;;
		waiting_for_input) printf '#f5a97f' ;;
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
		idle) printf '#[fg=#3b4261]●' ;;
		*) printf '#[fg=%s]●' "$color" ;;
	esac
}

render_session_tab() {
	local session="$1"
	local is_current="$2"
	local display_name summary state dot counts symbol label
	summary="$(session_status "$session")"
	state="${summary#state=}"
	state="${state%%$'\t'*}"
	counts="${summary#*$'\t'}"
	[[ "$counts" == "$summary" ]] && counts=""
	symbol="$(agent_status_state_symbol "$state")"
	label="$(agent_status_state_label "$state")"
	if [[ -n "${NO_COLOR:-}${AGENT_STATUS_NO_COLOR:-}" ]]; then
		printf ' [%s %s:%s%s] ' "$symbol" "$label" "$session" "${counts:+ $counts}"
		return
	fi

	if [ "$is_current" = "true" ]; then
		display_name="$session"
		dot="$(status_dot "$state")"
		echo -n " #[bg=$bar_bg,fg=#363a4f]#[bg=#363a4f,fg=#cad3f5,bold]  $dot #[bg=#363a4f,fg=#cad3f5,bold]$symbol $label:$display_name${counts:+ $counts}  #[bg=$bar_bg,fg=#363a4f]"
		return
	fi

	display_name="$(compact_session_name "$session")"
	echo -n " #[bg=$bar_bg,fg=#1f2438]#[bg=#1f2438,fg=#9aa3bc] $symbol $display_name #[bg=$bar_bg,fg=#1f2438]"
}

sessions=()
while IFS= read -r session; do
	[[ -n "$session" ]] && sessions+=("$session")
done < <(
	tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F '#{session_created} #{session_name}' 2>/dev/null \
		| cut -d ' ' -f 2- \
		| agent_status_order_sessions
)

session_count=${#sessions[@]}
current_index=-1
for i in "${!sessions[@]}"; do
	if [[ "${sessions[$i]}" = "$current" ]]; then
		current_index=$i
		break
	fi
done

if ((current_index == -1 || session_count == 1)); then
	render_session_tab "$current" true
	visible_sessions=1
elif ((session_count == 2)); then
	render_session_tab "$current" true
	render_session_tab "${sessions[$(((current_index + 1) % session_count))]}" false
	visible_sessions=2
else
	previous_index=$(((current_index - 1 + session_count) % session_count))
	next_index=$(((current_index + 1) % session_count))
	render_session_tab "${sessions[$previous_index]}" false
	render_session_tab "$current" true
	render_session_tab "${sessions[$next_index]}" false
	visible_sessions=$max_visible_sessions
fi

remaining_sessions=$((session_count - visible_sessions))

if [ "$remaining_sessions" -gt 0 ]; then
	echo -n " #[fg=#9aa3bc]+$remaining_sessions"
fi

echo -n ' '
