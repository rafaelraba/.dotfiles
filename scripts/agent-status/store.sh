#!/usr/bin/env bash

store_now() {
  local now="${AGENT_STATUS_NOW:-$(date +%s)}"
  [[ "$now" =~ ^[0-9]+$ ]] || now="$(date +%s)"
  printf '%s' "$now"
}

store_normalize() {
  case "$1" in
    running|permission|waiting_for_input|blocked|done|idle|error) printf '%s' "$1" ;;
    *) printf 'blocked' ;;
  esac
}

store_lock() {
  local lock="$STATUS_DIR/.lock" attempt=0 age
  while ! mkdir "$lock" 2>/dev/null; do
    age=$(( $(store_now) - $(date -r "$lock" +%s 2>/dev/null || printf 0) ))
    ((age > 5)) && rm -rf "$lock"
    ((++attempt < 100)) || return 1
    sleep 0.02
  done
}

store_path() {
  local session="$1" pane="$2"
  [[ -n "$pane" ]] && pane_file "$session" "$pane" || status_file "$session"
}

store_dirty_path() {
  printf '%s/.runtime-dirty/%s' "$STATUS_DIR" "$(basename "$1")"
}

store_mark_dirty() {
  local path="$1" token="$2" marker
  marker="$(store_dirty_path "$path")"
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$token" >"$marker"
}

store_clear_dirty_if_matching() {
  local path="$1" token="$2" marker
  marker="$(store_dirty_path "$path")"
  [[ -f "$marker" && "$(<"$marker")" == "$token" ]] && rm -f "$marker"
}

store_has_dirty_markers() {
  [[ -d "$STATUS_DIR/.runtime-dirty" ]] && find "$STATUS_DIR/.runtime-dirty" -type f -print -quit | grep -q .
}

# One render-local tmux view. Callers may pass this output through
# AGENT_STATUS_PANE_SNAPSHOT rather than repeatedly asking tmux for panes.
store_bulk_snapshot() {
  if [[ -n "${AGENT_STATUS_PANE_SNAPSHOT:-}" ]]; then
    printf '%s\n' "$AGENT_STATUS_PANE_SNAPSHOT"
    return
  fi
  tmux list-panes -a -F $'#{session_name}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}\t#{pane_start_command}\t#{pane_pid}' 2>/dev/null || true
}

store_effective() {
  local file="$1" state updated source event age ttl
  [[ -f "$file" ]] || { printf 'idle'; return; }
  IFS=$'\t' read -r _ state updated source event <"$file" || true
  if [[ -z "$updated" ]]; then
    read -r state <"$file" || true
    store_normalize "$state"
    return
  fi
  [[ "$updated" =~ ^[0-9]+$ ]] || { printf 'idle'; return; }
  state="$(store_normalize "$state")"
  ttl="$AGENT_STATUS_ACTIVE_TTL"
  [[ "$state" =~ ^(done|idle|error)$ ]] && ttl="$AGENT_STATUS_TERMINAL_TTL"
  age=$(( $(store_now) - updated ))
  ((age > ttl)) && { printf 'idle'; return; }
  printf '%s' "$state"
}

store_inspect() {
  local file="$1" _ state updated source event now age ttl reason="missing"
  local stored_state="idle" effective_state="idle"

  [[ -f "$file" ]] || {
    printf 'effective_state\t%s\nstored_state\t%s\nage\t\nstale_reason\t%s\n' "$effective_state" "$stored_state" "$reason"
    return
  }

  IFS=$'\t' read -r _ state updated source event <"$file" || true
  stored_state="$(store_normalize "$state")"
  if [[ -z "$updated" ]]; then
    reason="legacy"
  elif [[ ! "$updated" =~ ^[0-9]+$ ]]; then
    stored_state="idle"
    reason="malformed"
  else
    now="$(store_now)"
    age=$((now - updated))
    ((age < 0)) && age=0
    ttl="$AGENT_STATUS_ACTIVE_TTL"
    [[ "$stored_state" =~ ^(done|idle|error)$ ]] && ttl="$AGENT_STATUS_TERMINAL_TTL"
    reason="fresh"
    ((age > ttl)) && reason="expired"
  fi
  effective_state="$(store_effective "$file")"
  printf 'effective_state\t%s\nstored_state\t%s\nage\t%s\nstale_reason\t%s\n' "$effective_state" "$stored_state" "${age:-}" "$reason"
}

store_set() {
  local requested="$1" session="$2" pane="$3" source="${4:-unknown}" event="${5:-0}"
  local path old_event now tmp state
  state="$(store_normalize "$requested")"
  [[ "$source" =~ ^[[:alnum:]_.-]+$ && "$event" =~ ^[0-9]+$ ]] || return 1
  mkdir -p "$SESSION_DIR" "$PANE_DIR"
  store_lock || return 1
  path="$(store_path "$session" "$pane")"
  old_event=0
  [[ -f "$path" ]] && IFS=$'\t' read -r _ _ _ _ old_event <"$path" || true
  if [[ "$old_event" =~ ^[0-9]+$ ]] && ((event < old_event)); then
    rmdir "$STATUS_DIR/.lock"
    return 2
  fi
  now="$(store_now)"
  [[ "${AGENT_STATUS_RUNTIME_ENABLED:-0}" == 1 ]] && store_mark_dirty "$path" "$event"
  tmp="$(mktemp "${path}.tmp.XXXXXX")"
  printf '1\t%s\t%s\t%s\t%s\n' "$state" "$now" "$source" "$event" >"$tmp"
  mv -f "$tmp" "$path"
  rmdir "$STATUS_DIR/.lock"
}

store_clear() {
  local session="$1" pane="$2"
  [[ -n "$pane" ]] && rm -f "$(store_path "$session" "$pane")" || rm -f "$(store_path "$session" '')" "$PANE_DIR/$(sanitize_session "$session")_"*
}
