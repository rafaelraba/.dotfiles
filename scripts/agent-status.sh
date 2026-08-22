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
  agent-status.sh runtime-snapshot
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

aggregate_session_state() {
	local session="$1" row_session _ _ pane _ best_state=idle best_priority=10 state priority snapshot file matched=0
	snapshot="$(store_bulk_snapshot)"
	if [[ -n "$snapshot" ]]; then
		while IFS=$'\t' read -r row_session _ _ pane _; do
			[[ "$row_session" == "$session" ]] || continue; matched=1
			state="$(store_effective "$(pane_file "$session" "$pane")")"; priority="$(state_priority "$state")"
			((priority > best_priority)) && { best_state="$state"; best_priority="$priority"; }
		done <<<"$snapshot"
	fi
	if (( ! matched )); then
		for file in "$PANE_DIR/$(sanitize_session "$session")_"*; do
			[[ -f "$file" ]] || continue; state="$(store_effective "$file")"; priority="$(state_priority "$state")"
			((priority > best_priority)) && { best_state="$state"; best_priority="$priority"; }
		done
	fi
	state="$(store_effective "$(status_file "$session")")"
	priority="$(state_priority "$state")"
	((priority > best_priority)) && best_state="$state"
	printf '%s\n' "$best_state"
}

aggregate_session_count() {
  local session="$1" wanted="$2" row_session _ _ pane _ count=0 state snapshot file matched=0
  snapshot="$(store_bulk_snapshot)"
  if [[ -n "$snapshot" ]]; then
    while IFS=$'\t' read -r row_session _ _ pane _; do
      [[ "$row_session" == "$session" ]] || continue; matched=1
      state="$(store_effective "$(pane_file "$session" "$pane")")"; [[ "$state" == "$wanted" ]] && ((count++))
    done <<<"$snapshot"
  fi
  if (( ! matched )); then
    for file in "$PANE_DIR/$(sanitize_session "$session")_"*; do
      [[ -f "$file" ]] && [[ "$(store_effective "$file")" == "$wanted" ]] && ((count++))
    done
  fi
  [[ "$(store_effective "$(status_file "$session")")" == "$wanted" ]] && ((count++))
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

agent_status_runtime_snapshot() {
	local runtime_path now snapshot
	[[ "${AGENT_STATUS_RUNTIME_ENABLED:-0}" == "1" ]] || return 1
	runtime_path="${AGENT_STATUS_RUNTIME_PATH:-$ROOT/agent-status-runtime/bin/agent-status-runtime}"
	[[ "$runtime_path" = /* && -x "$runtime_path" ]] || return 1
	now="$(store_now)"
	snapshot="$(AGENT_STATUS_RUNTIME_DIRTY="$(store_has_dirty_markers && printf 1 || true)" AGENT_STATUS_RUNTIME_INVENTORY="$(store_bulk_snapshot)" python3 - "$runtime_path" "$STATUS_DIR" "$now" <<'PY'
import subprocess
import sys
import json
import os
import re

VALID_STATES = {"running", "permission", "waiting_for_input", "blocked", "done", "idle", "error"}
STATE_PRIORITY = {"error": 70, "permission": 60, "waiting_for_input": 50, "blocked": 40, "done": 30, "running": 20, "idle": 10}
ID_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")

def require_record(record, required, allowed):
    if not isinstance(record, dict) or not required <= record.keys() or not record.keys() <= allowed:
        raise ValueError
    if "token" in record and not isinstance(record["token"], str):
        raise ValueError

def aggregate(panes):
    sessions = {}
    for pane in panes:
        if STATE_PRIORITY[pane["state"]] > STATE_PRIORITY.get(sessions.get(pane["session"]), 0):
            sessions[pane["session"]] = pane["state"]
    return sessions

def filtered_candidate(response, inventory):
    if not isinstance(response, dict) or set(response) != {"type", "snapshot"} or response["type"] != "snapshot":
        raise ValueError
    candidate = response["snapshot"]
    if not isinstance(candidate, dict) or set(candidate) != {"schema_version", "epoch", "revision", "panes", "sessions"}:
        raise ValueError
    if candidate["schema_version"] != 2 or not isinstance(candidate["epoch"], str) or not candidate["epoch"]:
        raise ValueError
    if type(candidate["revision"]) is not int or candidate["revision"] < 0:
        raise ValueError
    if not isinstance(candidate["panes"], list) or not isinstance(candidate["sessions"], list):
        raise ValueError

    pane_identities = set()
    for pane in candidate["panes"]:
        require_record(pane, {"session", "pane", "state"}, {"session", "pane", "state", "token"})
        identity = (pane["session"], pane["pane"])
        if not all(isinstance(value, str) and ID_PATTERN.fullmatch(value) for value in identity):
            raise ValueError
        if pane["state"] not in VALID_STATES or identity in pane_identities:
            raise ValueError
        pane_identities.add(identity)

    session_states = {}
    session_records = {}
    for session in candidate["sessions"]:
        require_record(session, {"name", "state"}, {"name", "state", "token"})
        if not isinstance(session["name"], str) or not ID_PATTERN.fullmatch(session["name"]):
            raise ValueError
        if session["state"] not in VALID_STATES or session["name"] in session_states:
            raise ValueError
        session_states[session["name"]] = session["state"]
        session_records[session["name"]] = session
    if session_states != aggregate(candidate["panes"]):
        raise ValueError

    panes = sorted((pane for pane in candidate["panes"] if (pane["session"], pane["pane"]) in inventory), key=lambda pane: (pane["session"], pane["pane"]))
    live_states = aggregate(panes)
    sessions = []
    for name in sorted(live_states):
        session = {"name": name, "state": live_states[name]}
        source = session_records[name]
        if source["state"] == session["state"] and "token" in source:
            session["token"] = source["token"]
        sessions.append(session)
    return {**candidate, "panes": panes, "sessions": sessions}

def run(command):
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=1.0,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return b""
    return completed.stdout if completed.returncode == 0 and len(completed.stdout) <= 65536 else b""

daemon = b"" if __import__("os").environ.get("AGENT_STATUS_RUNTIME_DIRTY") else run([sys.argv[1], "socket-snapshot", "--root", sys.argv[2], "--now", sys.argv[3]])
if daemon:
    try:
        response = json.loads(daemon)
        inventory = {(row.split("\t")[0], re.sub(r"[^A-Za-z0-9_.-]", "_", row.split("\t")[3])) for row in os.environ["AGENT_STATUS_RUNTIME_INVENTORY"].splitlines() if len(row.split("\t")) >= 4}
        candidate = filtered_candidate(response, inventory)
        sys.stdout.buffer.write(b"__agent_status_daemon__\n" + json.dumps(candidate, separators=(",", ":")).encode() + b"\n")
        sys.exit(0)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        pass

try:
    completed = subprocess.run(
        [sys.argv[1], "snapshot", "--root", sys.argv[2], "--now", sys.argv[3]],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=1.0,
        check=False,
    )
except (OSError, subprocess.TimeoutExpired):
    sys.exit(1)

if completed.returncode != 0 or len(completed.stdout) > 65536:
    sys.exit(1)
sys.stdout.buffer.write(completed.stdout)
PY
)" || return 1
	if [[ "$snapshot" == __agent_status_daemon__$'\n'* ]]; then
		snapshot="${snapshot#*$'\n'}"
		store_has_dirty_markers && AGENT_STATUS_RUNTIME_RETRY=1 agent_status_runtime_snapshot && return
	fi
	printf '%s\n' "$snapshot"
}

agent_status_runtime_publish() {
	local state="$1" session="$2" pane="$3" source="$4" token="$5" path runtime_path
	[[ "${AGENT_STATUS_RUNTIME_ENABLED:-0}" == "1" ]] || return 1
	runtime_path="${AGENT_STATUS_RUNTIME_PATH:-$ROOT/agent-status-runtime/bin/agent-status-runtime}"
	[[ "$runtime_path" = /* && -x "$runtime_path" ]] || return 1
	path="$(store_path "$session" "$pane")"
	"$runtime_path" publish --root "$STATUS_DIR" --session "$session" --pane "${pane//%/_}" --source "$source" --state "$state" --producer-revision "$token" 2>/dev/null | grep -q '"type":"ack"' || return 1
	store_clear_dirty_if_matching "$path" "$token"
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
		agent_status_runtime_publish "$(store_normalize "$state")" "$session" "$pane" "${3:-unknown}" "${4:-0}" || true
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
	snapshot)
		store_bulk_snapshot
		;;
	doctor)
		printf 'config_version\t%s\nstate_dir\t%s\nsound_enabled\t%s\nsound_backend\t%s\nsound_file\t%s\nsound_status\t%s\n' \
			"$AGENT_STATUS_CONFIG_VERSION" "$STATUS_DIR" "$AGENT_STATUS_SOUND_ENABLED" \
			"$AGENT_STATUS_SOUND_BACKEND" "$AGENT_STATUS_SOUND_FILE" "$(notify_sound_status)"
		;;
	runtime-snapshot)
		agent_status_runtime_snapshot
		;;
	*)
	usage
	exit 1
	;;
esac
