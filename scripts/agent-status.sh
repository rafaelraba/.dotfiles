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

readonly STATUS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-status"
readonly SESSION_DIR="$STATUS_DIR/sessions"
readonly PANE_DIR="$STATUS_DIR/panes"

usage() {
	cat >&2 <<'EOF'
Usage:
  agent-status.sh set <running|blocked|done|idle|error> [session] [pane]
  agent-status.sh get [session]
  agent-status.sh clear [session] [pane]
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

validate_state() {
	case "$1" in
	running | blocked | done | idle | error) return 0 ;;
	*)
		printf 'Invalid state: %s\n' "$1" >&2
		usage
		exit 1
		;;
	esac
}

normalize_state() {
	case "$1" in
	triage | needs_input | permission) printf 'blocked' ;;
	running | blocked | done | idle | error) printf '%s' "$1" ;;
	*) printf 'idle' ;;
	esac
}

state_priority() {
	case "$1" in
	error) printf '50' ;;
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
	local safe_session live_panes
	safe_session="$(sanitize_session "$session")"
	local best_state="idle"
	local best_priority=10
	local file pane state priority

	if ! live_panes="$(tmux list-panes -t "$session" -F '#{pane_id}' 2>/dev/null)"; then
		printf '%s\n' "$best_state"
		return
	fi

	file="$(status_file "$session")"
	if [[ -f "$file" ]]; then
		read -r state <"$file"
		state="$(normalize_state "$state")"
		priority="$(state_priority "$state")"
		if ((priority > best_priority)); then
			best_state="$state"
			best_priority="$priority"
		fi
	fi

	for file in "$PANE_DIR/${safe_session}_"*; do
		[[ -f "$file" ]] || continue
		pane="${file##*/${safe_session}_}"
		if ! is_live_pane "$pane" "$live_panes"; then
			rm -f "$file"
			continue
		fi

		read -r state <"$file"
		state="$(normalize_state "$state")"
		priority="$(state_priority "$state")"
		if ((priority > best_priority)); then
			best_state="$state"
			best_priority="$priority"
		fi
	done

	printf '%s\n' "$best_state"
}

command="${1:-}"
shift || true

case "$command" in
set)
	state="${1:-}"
	shift || true
	validate_state "$state"
	session="$(resolve_session "${1:-}")"
	pane="$(resolve_pane "${2:-}")"
	mkdir -p "$SESSION_DIR" "$PANE_DIR"
	if [[ -n "$pane" ]]; then
		printf '%s\n' "$state" >"$(pane_file "$session" "$pane")"
	else
		printf '%s\n' "$state" >"$(status_file "$session")"
	fi
	;;
get)
	session="$(resolve_session "${1:-}")"
	aggregate_session_state "$session"
	;;
clear)
	session="$(resolve_session "${1:-}")"
	pane="$(resolve_pane "${2:-}")"
	if [[ -n "$pane" ]]; then
		rm -f "$(pane_file "$session" "$pane")"
	else
		rm -f "$(status_file "$session")" "$PANE_DIR/$(sanitize_session "$session")_"*
	fi
	;;
*)
	usage
	exit 1
	;;
esac
