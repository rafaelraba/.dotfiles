#!/usr/bin/env bash
set -euo pipefail

# Generic local protocol for agent state by tmux session/pane.
# Any CLI agent can call this script without coupling tmux to that agent.
#
# Usage:
#   agent-status.sh set <state> [session] [pane]
#   agent-status.sh get [session]
#   agent-status.sh clear [session] [pane]
#
# States:
#   running      Agent is actively working.
#   idle         Agent is idle / finished.
#   blocked      Agent is waiting for human input/approval.
#   done         Agent finished and needs review/attention.
#   error        Agent needs attention because something failed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
# shellcheck source=agent-status/store.sh
source "$ROOT/agent-status/store.sh"
# shellcheck source=agent-status/order.sh
source "$ROOT/agent-status/order.sh"
# shellcheck source=agent-status/notify.sh
source "$ROOT/agent-status/notify.sh"
agent_status_load_config || { printf 'Invalid agent-status configuration.\n' >&2; exit 1; }

usage() {
	cat >&2 <<'EOF'
Usage:
  agent-status.sh set <state> [session] [pane] [source] [event_id]
  agent-status.sh get [session]
  agent-status.sh summary [session]
  agent-status.sh clear [session] [pane]
  agent-status.sh inspect [session] [pane]
  agent-status.sh doctor
EOF
}

current_session() {
	tmux display-message -p '#S' 2>/dev/null || true
}

current_pane() {
	tmux display-message -p '#{pane_id}' 2>/dev/null || true
}

sanitize_session() {
	local session="$1"
	printf '%s' "$session" | tr -c '[:alnum:]_.-' '_'
}

status_file() {
	local session="$1"
	printf '%s/%s' "$SESSION_DIR" "$(sanitize_session "$session")"
}

pane_file() {
	local session="$1"
	local pane="$2"
	printf '%s/%s_%s' "$PANE_DIR" "$(sanitize_session "$session")" "$(sanitize_session "$pane")"
}

resolve_session() {
	local session="${1:-}"

	if [[ -z "$session" ]]; then
		session="$(current_session)"
	fi

	if [[ -z "$session" ]]; then
		printf 'No tmux session provided and none could be detected.\n' >&2
		exit 1
	fi

	printf '%s' "$session"
}

resolve_pane() {
	local pane="${1:-}"

	if [[ -z "$pane" ]]; then
		pane="${TMUX_PANE:-}"
	fi

	if [[ -z "$pane" ]]; then
		pane="$(current_pane)"
	fi

	printf '%s' "$pane"
}

normalize_state() {
	case "$1" in
	permission|waiting_for_input|running|blocked|done|idle|error) printf '%s' "$1" ;;
	*) printf 'blocked' ;;
	esac
}

state_priority() {
	case "$1" in
	error) printf '70' ;;
	permission) printf '60' ;;
	waiting_for_input) printf '50' ;;
	blocked) printf '40' ;;
	done) printf '30' ;;
	running) printf '20' ;;
	idle) printf '10' ;;
	*) printf '0' ;;
	esac
}

is_live_pane() {
	local pane="$1"
	local live_panes="$2"
	local live_pane

	while IFS= read -r live_pane; do
		[[ "$(sanitize_session "$live_pane")" = "$pane" ]] && return 0
	done <<<"$live_panes"

	return 1
}

aggregate_session_state() {
	local session="$1"
	local safe_session live_panes tmux_available=1
	safe_session="$(sanitize_session "$session")"
	local best_state="idle"
	local best_priority=10
	local file pane state priority

	if ! live_panes="$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null)"; then
		tmux_available=0
	fi

	file="$(status_file "$session")"
	if [[ -f "$file" ]]; then
		state="$(store_effective "$file")"
		priority="$(state_priority "$state")"
		if ((priority > best_priority)); then
			best_state="$state"
			best_priority="$priority"
		fi
	fi

	for file in "$PANE_DIR/${safe_session}_"*; do
		[[ -f "$file" ]] || continue
		pane="${file##*/${safe_session}_}"
		if ((tmux_available)) && ! is_live_pane "$pane" "$live_panes"; then
			rm -f "$file"
			continue
		fi

		state="$(store_effective "$file")"
		priority="$(state_priority "$state")"
		if ((priority > best_priority)); then
			best_state="$state"
			best_priority="$priority"
		fi
	done

	printf '%s\n' "$best_state"
}

aggregate_session_count() {
  local session="$1" wanted="$2" safe_session file pane live_panes tmux_available=1 count=0 state
  safe_session="$(sanitize_session "$session")"
  if ! live_panes="$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null)"; then
    tmux_available=0
  fi
  file="$(status_file "$session")"
  [[ -f "$file" && "$(store_effective "$file")" == "$wanted" ]] && ((count++))
  for file in "$PANE_DIR/${safe_session}_"*; do
    [[ -f "$file" ]] || continue
    pane="${file##*/${safe_session}_}"
    if ((tmux_available)) && ! is_live_pane "$pane" "$live_panes"; then
      rm -f "$file"
      continue
    fi
    state="$(store_effective "$file")"
    [[ "$state" == "$wanted" ]] && ((count++))
  done
  printf '%s' "$count"
}

aggregate_session_summary() {
  local session="$1" state count
  state="$(aggregate_session_state "$session")"
  printf 'state=%s' "$state"
  for state in error permission waiting_for_input blocked done running; do
    count="$(aggregate_session_count "$session" "$state")"
    ((count > 0)) && printf '\t%s=%s' "$state" "$count"
  done
  printf '\n'
}

command="${1:-}"
shift || true

case "$command" in
set)
	state="${1:-}"
	shift || true
	session="$(resolve_session "${1:-}")"
	pane="$(resolve_pane "${2:-}")"
	if store_set "$state" "$session" "$pane" "${3:-unknown}" "${4:-0}"; then
		notify_transition "$(store_normalize "$state")" "$session" "$pane" || true
	else
		[[ $? == 2 ]] || exit 1
	fi
	;;
get)
	session="$(resolve_session "${1:-}")"
	aggregate_session_state "$session"
	;;
summary)
	session="$(resolve_session "${1:-}")"
	aggregate_session_summary "$session"
	;;
clear)
	session="$(resolve_session "${1:-}")"
	pane="$(resolve_pane "${2:-}")"
	store_clear "$session" "$pane"
	;;
	inspect)
		session="$(resolve_session "${1:-}")"
		pane="$(resolve_pane "${2:-}")"
		file="$(store_path "$session" "$pane")"
		store_inspect "$file"
		;;
	doctor)
	printf 'config_version\t%s\nstate_dir\t%s\n' "$AGENT_STATUS_CONFIG_VERSION" "$STATUS_DIR"
	;;
*)
	usage
	exit 1
	;;
esac
