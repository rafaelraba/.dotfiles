#!/usr/bin/env bash
# Muestra el contexto de la sesión actual y cuántas sesiones adicionales hay.
# Uso: ~/.dotfiles/scripts/status-sessions.sh <session_actual>

current="$1"
bar_bg="#0b0f1a"
max_visible_sessions=5
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
	local session="$1" row_session _ _ pane _ state best=idle priority best_priority=10 safe_session runtime_state
	runtime_state="$(runtime_session_state "$session")"
	if [[ -n "$runtime_state" ]]; then
		printf '%s\n' "$runtime_state"
		return
	fi
	safe_session="$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')"
	while IFS=$'\t' read -r row_session _ _ pane _; do
		[[ "$row_session" == "$session" ]] || continue
		state="$(store_effective "$PANE_DIR/${safe_session}_${pane//%/_}")"
		case "$state" in error) priority=70 ;; permission) priority=60 ;; waiting_for_input) priority=50 ;; blocked) priority=40 ;; done) priority=30 ;; running) priority=20 ;; *) priority=10 ;; esac
		((priority > best_priority)) && { best="$state"; best_priority=$priority; }
	done <<<"$snapshot"
	printf '%s\n' "$best"
}

runtime_session_state() {
	local wanted="$1" session state
	while IFS=$'\t' read -r session state; do
		[[ "$session" == "$wanted" ]] && { printf '%s' "$state"; return; }
	done <<<"${runtime_sessions:-}"
}

runtime_session_states() {
	AGENT_STATUS_RUNTIME_INVENTORY="$snapshot" python3 -c '
import json
import os
import re
import sys

try:
    data = json.load(sys.stdin)
    if data.get("schema_version") != 2:
        raise ValueError
    inventory = set()
    sessions = set()
    for row in os.environ["AGENT_STATUS_RUNTIME_INVENTORY"].splitlines():
        fields = row.split("\t")
        if len(fields) < 4:
            continue
        sessions.add(fields[0])
        inventory.add((fields[0], re.sub(r"[^A-Za-z0-9_.-]", "_", fields[3])))
    valid = {"running", "permission", "waiting_for_input", "blocked", "done", "idle", "error"}
    for pane in data["panes"]:
        if not isinstance(pane, dict) or (pane.get("session"), pane.get("pane")) not in inventory or pane.get("state") not in valid:
            raise ValueError
    rows = []
    for item in data["sessions"]:
        if not isinstance(item, dict) or item.get("name") not in sessions or item.get("state") not in valid:
            raise ValueError
        rows.append((item["name"], item["state"]))
    if len({name for name, _ in rows}) != len(rows):
        raise ValueError
    print("".join(f"{name}\t{state}\n" for name, state in sorted(rows)), end="")
except (KeyError, TypeError, ValueError, json.JSONDecodeError):
    sys.exit(1)
'
}

runtime_fast_session_states() {
	local runtime_path trusted_path output session state extra seen=''
	[[ "${AGENT_STATUS_RUNTIME_ENABLED:-0}" == 1 ]] || return 1
	store_has_dirty_markers && return 1
	runtime_path="${AGENT_STATUS_RUNTIME_PATH:-$ROOT/agent-status-runtime/bin/agent-status-runtime}"
	trusted_path="${AGENT_STATUS_RUNTIME_FAST_PATH:-$ROOT/agent-status-runtime/bin/agent-status-runtime}"
	[[ "$runtime_path" == "$trusted_path" && "$runtime_path" = /* && -x "$runtime_path" ]] || return 1
	output="$("$runtime_path" socket-sessions --root "$STATUS_DIR" <<<"$snapshot" 2>/dev/null)" || return 1
	[[ -z "$output" ]] && return 0
	while IFS=$'\t' read -r session state extra; do
		[[ -n "$session" && -z "$extra" && "$session" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || return 1
		case "$state" in running|permission|waiting_for_input|blocked|done|idle|error) ;; *) return 1 ;; esac
		case $'\n'"$seen" in *$'\n'"$session"$'\n'*) return 1 ;; esac
		seen+="$session"$'\n'
	done <<<"$output"
	printf '%s' "$output"
}

status_bg() {
	local state="$1"

	case "$state" in
		running) printf '%s' "${AGENT_STATUS_PALETTE_RUNNING:-#8aadf4}" ;;
		permission) printf '%s' "${AGENT_STATUS_PALETTE_PERMISSION:-#eed49f}" ;;
		waiting_for_input) printf '%s' "${AGENT_STATUS_PALETTE_WAITING_FOR_INPUT:-#f5a97f}" ;;
		blocked) printf '%s' "${AGENT_STATUS_PALETTE_BLOCKED:-#c6a0f6}" ;;
		done) printf '%s' "${AGENT_STATUS_PALETTE_DONE:-#a6da95}" ;;
		error) printf '%s' "${AGENT_STATUS_PALETTE_ERROR:-#ed8796}" ;;
		# Idle tabs use a fixed identity accent, separate from lifecycle palettes.
		*) printf '#6c8f91' ;;
	esac
}

render_session_tab() {
	local session="$1"
	local is_current="$2"
	local tab_number="$3"
	local display_name state color symbol summary
	summary="$(session_status "$session")"
	state="$summary"
	if [[ -n "${NO_COLOR:-}${AGENT_STATUS_NO_COLOR:-}" ]]; then
		case "$state" in error) symbol='!' ;; permission) symbol='?' ;; waiting_for_input) symbol='…' ;; blocked) symbol='#' ;; done) symbol='✓' ;; running) symbol='›' ;; *) symbol='·' ;; esac
		printf ' [%s %s %s] ' "$symbol" "$session" "$tab_number"
		return
	fi
	color="$(status_bg "$state")"

	if [ "$is_current" = "true" ]; then
		echo -n " #[bg=$bar_bg,fg=#494d64]#[bg=#494d64,fg=#ffffff,bold] $session #[bg=$color,fg=#0b0f1a,bold] $tab_number #[bg=$bar_bg,fg=$color]"
		return
	fi

	display_name="$(compact_session_name "$session")"
	echo -n " #[bg=$bar_bg,fg=#1f2438]#[bg=#1f2438,fg=#ffffff,bold] $display_name #[bg=$color,fg=#0b0f1a,bold] $tab_number #[bg=$bar_bg,fg=$color]"
}

sessions=()
snapshot="$(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}\t#{pane_start_command}\t#{pane_pid}' 2>/dev/null || true)"
AGENT_STATUS_PANE_SNAPSHOT="$snapshot" "$ROOT/codex-status-refresh.sh" >/dev/null 2>&1 || true
if runtime_sessions="$(runtime_fast_session_states)"; then
	runtime_snapshot=''
else
	runtime_snapshot="$(AGENT_STATUS_PANE_SNAPSHOT="$snapshot" "$ROOT/agent-status.sh" runtime-snapshot 2>/dev/null || true)"
	runtime_sessions="$(printf '%s' "$runtime_snapshot" | runtime_session_states 2>/dev/null || true)"
fi
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
for i in "${!sessions[@]}"; do
	((visible_sessions < max_visible_sessions)) || break
	# Reserve the final slot for an off-screen current session without reordering
	# the earlier non-current sessions.
	if [ "$i" -eq $((max_visible_sessions - 1)) ] && [ "$current_index" -ge "$max_visible_sessions" ]; then
		i="$current_index"
	fi
	session="${sessions[$i]}"
	tab_number=$((i + 1))
	[[ "$session" == "$current" ]] && render_session_tab "$session" true "$tab_number" || render_session_tab "$session" false "$tab_number"
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
