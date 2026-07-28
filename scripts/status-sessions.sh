#!/usr/bin/env bash
# Muestra el contexto de la sesión actual y cuántas sesiones adicionales hay.
# Uso: ~/.dotfiles/scripts/status-sessions.sh <session_actual>

current="$1"
bar_bg="#0b0f1a"
max_visible_sessions=3
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
# shellcheck source=agent-status/store.sh
source "$ROOT/agent-status/store.sh"
# shellcheck source=agent-status/order.sh
source "$ROOT/agent-status/order.sh"
agent_status_load_config || exit 0
export AGENT_STATUS_NOW="${AGENT_STATUS_NOW:-$(date +%s)}"
if [[ -n "${AGENT_STATUS_TIMING_FILE:-}" ]]; then
	render_started="$(python3 -c 'import time; print(time.perf_counter())')"
fi

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
	local session="$1" row_session _ _ pane _ state best=idle priority best_priority=10 safe_session
	safe_session="$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')"
	while IFS=$'\t' read -r row_session _ _ pane _; do
		[[ "$row_session" == "$session" ]] || continue
		state="$(store_effective "$PANE_DIR/${safe_session}_${pane//%/_}")"
		case "$state" in error) priority=70 ;; permission) priority=60 ;; waiting_for_input) priority=50 ;; blocked) priority=40 ;; done) priority=30 ;; running) priority=20 ;; *) priority=10 ;; esac
		((priority > best_priority)) && { best="$state"; best_priority=$priority; }
	done <<<"$snapshot"
	printf '%s\n' "$best"
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
	local display_name state dot symbol summary
	summary="$(session_status "$session")"
	state="$summary"
	if [[ -n "${NO_COLOR:-}${AGENT_STATUS_NO_COLOR:-}" ]]; then
		case "$state" in error) symbol='!' ;; permission) symbol='?' ;; waiting_for_input) symbol='…' ;; blocked) symbol='#' ;; done) symbol='✓' ;; running) symbol='›' ;; *) symbol='·' ;; esac
		printf ' [%s %s] ' "$symbol" "$session"
		return
	fi
	dot="$(status_dot "$state")"

	if [ "$is_current" = "true" ]; then
		echo -n " #[bg=$bar_bg,fg=#363a4f]#[bg=#363a4f,fg=#ffffff,bold] $dot#[fg=#ffffff] $session #[bg=$bar_bg,fg=#363a4f]"
		return
	fi

	display_name="$(compact_session_name "$session")"
	echo -n " #[bg=$bar_bg,fg=#1f2438]#[bg=#1f2438,fg=#ffffff,bold] $dot#[fg=#ffffff] $display_name #[bg=$bar_bg,fg=#1f2438]"
}

sessions=()
snapshot="$(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}' 2>/dev/null || true)"
while IFS= read -r session; do
	[[ -n "$session" ]] && sessions+=("$session")
done < <(
	tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F $'#{session_created}\t#{session_id}\t#{session_name}' 2>/dev/null \
		| LC_ALL=C sort -t $'\t' -k1,1n -k2.2n \
		| cut -f 3- \
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

visible_sessions=0
for session in "${sessions[@]}"; do
	((visible_sessions < max_visible_sessions)) || break
	[[ "$session" == "$current" ]] && render_session_tab "$session" true || render_session_tab "$session" false
	((++visible_sessions))
done

remaining_sessions=$((session_count - visible_sessions))

if [ "$remaining_sessions" -gt 0 ]; then
	echo -n " #[fg=#9aa3bc]+$remaining_sessions"
fi

echo -n ' '
if [[ -n "${AGENT_STATUS_TIMING_FILE:-}" ]]; then
	python3 -c "import time; print((time.perf_counter() - $render_started) * 1000)" >>"$AGENT_STATUS_TIMING_FILE"
fi
