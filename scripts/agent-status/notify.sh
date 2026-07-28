#!/usr/bin/env bash

notify_debug() {
  [[ "${AGENT_STATUS_DEBUG:-0}" == 1 ]] && printf 'agent-status notify: %s\n' "$*" >&2
}

notify_now() {
  local now="${AGENT_STATUS_NOW:-$(date +%s)}"
  [[ "$now" =~ ^[0-9]+$ ]] || now="$(date +%s)"
  printf '%s' "$now"
}

notify_attention_state() {
  local state="$1" configured
  for configured in "${AGENT_STATUS_SOUND_STATES[@]}"; do
    [[ "$state" == "$configured" ]] && return 0
  done
  return 1
}

notify_lock() {
  local lock="$STATUS_DIR/.notify.lock" attempt=0 age
  while ! mkdir "$lock" 2>/dev/null; do
    age=$(( $(notify_now) - $(date -r "$lock" +%s 2>/dev/null || printf 0) ))
    ((age > 5)) && rmdir "$lock" 2>/dev/null || true
    ((++attempt < 100)) || return 1
    sleep 0.02
  done
}

notify_transition() {
  local state="$1" session="$2" pane="$3" backend="$AGENT_STATUS_SOUND_BACKEND"
  local sound="$AGENT_STATUS_SOUND_FILE" ledger key now last=0 tmp
  [[ "$AGENT_STATUS_SOUND_ENABLED" == 1 ]] || return 0
  notify_attention_state "$state" || return 0
  case "$backend" in afplay|paplay) ;; *) notify_debug "unsupported backend: $backend"; return 0 ;; esac
  command -v "$backend" >/dev/null 2>&1 || { notify_debug "backend unavailable: $backend"; return 0; }
  [[ -r "$sound" ]] || { notify_debug "sound file unavailable: $sound"; return 0; }

  mkdir -p "$STATUS_DIR" || return 0
  notify_lock || { notify_debug 'notification lock unavailable'; return 0; }
  ledger="$STATUS_DIR/notifications.tsv"
  key="${state}|$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')|$(printf '%s' "$pane" | tr -c '[:alnum:]_.-' '_')"
  now="$(notify_now)"
  [[ -f "$ledger" ]] && last="$(awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$ledger")"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if ((now - last < AGENT_STATUS_SOUND_COOLDOWN)); then
    rmdir "$STATUS_DIR/.notify.lock"
    return 0
  fi
  if ! "$backend" "$sound"; then
    notify_debug "backend failed: $backend"
    rmdir "$STATUS_DIR/.notify.lock"
    return 0
  fi
  tmp="$(mktemp "${ledger}.tmp.XXXXXX")"
  { printf '%s\t%s\n' "$key" "$now"; [[ -f "$ledger" ]] && awk -F '\t' -v key="$key" '$1 != key' "$ledger"; } >"$tmp"
  mv -f "$tmp" "$ledger"
  rmdir "$STATUS_DIR/.notify.lock"
}
