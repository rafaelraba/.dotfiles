#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS="$ROOT/agent-status.sh"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
agent_status_load_config || exit 0
snapshot="${AGENT_STATUS_PANE_SNAPSHOT:-}"
lock="$STATUS_DIR/.codex-refresh.lock"
lock_owner="$lock/owner"

release_lock() {
  [[ -f "$lock_owner" && "$(<"$lock_owner")" == "$$" ]] && rm -rf "$lock"
}

mkdir -p "$STATUS_DIR"
if ! mkdir "$lock" 2>/dev/null; then
  owner=''
  [[ -f "$lock_owner" ]] && read -r owner <"$lock_owner" || true
  if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
    exit 0
  fi
  if [[ -z "$owner" ]]; then
    lock_age=$(( $(date +%s) - $(date -r "$lock" +%s 2>/dev/null || printf 0) ))
    ((lock_age > 5)) || exit 0
  fi
  rm -rf "$lock"
  mkdir "$lock" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" >"$lock_owner"
trap release_lock EXIT
trap 'exit 0' HUP INT TERM

if [[ -z "$snapshot" ]]; then
  snapshot="$(tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}\t#{pane_start_command}\t#{pane_pid}' 2>/dev/null || true)"
fi
[[ -n "$snapshot" ]] || exit 0

codex_ancestor_pids() {
  awk '
    function base(path, n, parts) { n = split(path, parts, "/"); return parts[n] }
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
      parent[$1] = $2
      if (base($3) == "codex") found[$1] = 1
      for (i = 4; i <= NF; i++) if (base($i) == "codex" || base($i) == "codex.js") found[$1] = 1
    }
    END {
      for (pid in found) {
        current = pid
        while (current != "" && !result[current]) { result[current] = 1; current = parent[current] }
      }
      for (pid in result) print pid
    }
  '
}

producer_ancestor_pids() {
  awk '
    function base(path, n, parts) { n = split(path, parts, "/"); return parts[n] }
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
      parent[$1] = $2
      for (i = 3; i <= NF; i++) {
        name = base($i)
        if (name == "claude" || name == "opencode" || name == "pi") found[name, $1] = 1
      }
    }
    END {
      for (key in found) {
        split(key, parts, SUBSEP)
        source = parts[1]
        current = parts[2]
        while (current != "" && !seen[source, current]) {
          seen[source, current] = 1
          current = parent[current]
        }
      }
      for (key in seen) {
        split(key, parts, SUBSEP)
        print parts[1] "\t" parts[2]
      }
    }
  '
}

classify_screen() {
  local screen="$1"
  if printf '%s\n' "$screen" | grep -Eq '^[[:space:]]*([•◦∙][[:space:]]+)?Working \([^)]*esc to interrupt\)[[:space:]]*$|^[[:space:]]*Working\.\.\.[[:space:]]*$'; then
    printf 'running'
  elif printf '%s\n' "$screen" | grep -Eq '(^|[[:space:]])(Allow command|Approve (this|command)|Do you want to allow|Press enter to confirm)[?[:space:]]|^[[:space:]]*[›>]?[[:space:]]*[0-9]+\.[[:space:]].*(Approve|Allow)'; then
    printf 'permission'
  elif printf '%s\n' "$screen" | grep -Eq '^[[:space:]]*(Question|Your answer|Select an option|Enter your response)(:|[[:space:]])'; then
    printf 'waiting_for_input'
  else
    printf 'idle'
  fi
}

process_snapshot="$(ps -axo pid=,ppid=,comm=,args= 2>/dev/null || true)"
codex_pids="$(printf '%s\n' "$process_snapshot" | codex_ancestor_pids)"
producer_pids="$(printf '%s\n' "$process_snapshot" | producer_ancestor_pids)"
live_keys=''

while IFS=$'\034' read -r session _ _ pane _ _ _ _ pane_pid; do
  [[ -n "$session" && "$pane" == %* && "$pane_pid" =~ ^[0-9]+$ ]] || continue
  case $'\n'"$codex_pids"$'\n' in
    *$'\n'"$pane_pid"$'\n'*) ;;
    *) continue ;;
  esac
  live_keys="$live_keys$session"$'\034'"$pane"$'\n'
  file="$PANE_DIR/$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')_${pane//%/_}"
  source=''; previous='idle'
  if [[ -f "$file" ]]; then
    IFS=$'\t' read -r _ previous _ source _ <"$file" || true
  fi
  case "$source" in
    claude|opencode|pi)
      case $'\n'"$producer_pids"$'\n' in
        *$'\n'"$source"$'\t'"$pane_pid"$'\n'*) continue ;;
      esac
      ;;
  esac
  screen="$(tmux capture-pane -p -t "$pane" -S -12 -E - 2>/dev/null || true)"
  state="$(classify_screen "$screen")"
  if [[ "$state" == idle && "$previous" == running && "$source" == codex ]]; then state=done; fi
  if [[ "$state" == idle && "$previous" == done && "$source" == codex ]]; then continue; fi
  now="${AGENT_STATUS_NOW:-$(date +%s)}"
  "$STATUS" set "$state" "$session" "$pane" codex "$((now * 1000))" >/dev/null 2>&1 || true
done < <(printf '%s\n' "$snapshot" | tr '\t' '\034')

for file in "$PANE_DIR"/*; do
  [[ -f "$file" ]] || continue
  IFS=$'\t' read -r _ _ _ source _ <"$file" || true
  [[ "$source" == codex ]] || continue
  matched=0
  while IFS=$'\034' read -r session _ _ pane _; do
    key="$session"$'\034'"$pane"
    case $'\n'"$live_keys" in *$'\n'"$key"$'\n'*) matched=1; break ;; esac
  done < <(printf '%s\n' "$snapshot" | tr '\t' '\034')
  ((matched)) || rm -f "$file"
done
