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

notify_sound_status() {
  local backend="$AGENT_STATUS_SOUND_BACKEND" sound="${1:-$AGENT_STATUS_SOUND_FILE}"
  [[ "$AGENT_STATUS_SOUND_ENABLED" == 1 ]] || { printf 'disabled'; return; }
  case "$backend" in afplay|paplay) ;; *) printf 'unsupported_backend'; return ;; esac
  command -v "$backend" >/dev/null 2>&1 || { printf 'backend_missing'; return; }
  [[ -r "$sound" ]] || { printf 'file_missing'; return; }
  printf 'ready'
}

notify_unlock() {
  local token="$1" lock="$STATUS_DIR/.notify.lock"
  [[ "$token" =~ ^owner\.[0-9]+\.[0-9]+$ ]] || return 1
  rmdir "$lock/$token" 2>/dev/null || return 1
  rmdir "$lock" 2>/dev/null || true
}

notify_reclaim_lock() {
  local lock="$STATUS_DIR/.notify.lock" owner token
  for owner in "$lock"/owner.*; do
    [[ -d "$owner" ]] || continue
    token="${owner##*/}"
    notify_unlock "$token"
    return
  done
  rmdir "$lock" 2>/dev/null || true
}

notify_lock() {
  local lock="$STATUS_DIR/.notify.lock" attempt=0 age token
  NOTIFY_LOCK_TOKEN=''
  while ! mkdir "$lock" 2>/dev/null; do
    age=$(( $(notify_now) - $(date -r "$lock" +%s 2>/dev/null || printf 0) ))
    ((age > 5)) && notify_reclaim_lock
    ((++attempt < 100)) || return 1
    sleep 0.02
  done
  NOTIFY_LOCK_SEQUENCE=$(( ${NOTIFY_LOCK_SEQUENCE:-0} + 1 ))
  token="owner.$$.$NOTIFY_LOCK_SEQUENCE"
  mkdir "$lock/$token" 2>/dev/null || return 1
  NOTIFY_LOCK_TOKEN="$token"
}

notify_reserve() (
  local ledger="$1" key="$2" now="$3" last=0 tmp='' lock_token=''
  cleanup() {
    [[ -z "$tmp" ]] || rm -f "$tmp"
    [[ -z "$lock_token" ]] || notify_unlock "$lock_token" || true
  }
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM

  notify_lock || { notify_debug 'notification lock unavailable'; return 1; }
  lock_token="$NOTIFY_LOCK_TOKEN"
  [[ -f "$ledger" ]] && last="$(awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$ledger")"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  ((now - last >= AGENT_STATUS_SOUND_COOLDOWN)) || return 1
  tmp="$(mktemp "${ledger}.tmp.XXXXXX")" || return 1
  { printf '%s\t%s\n' "$key" "$now"; [[ -f "$ledger" ]] && awk -F '\t' -v key="$key" '$1 != key' "$ledger"; } >"$tmp"
  mv -f "$tmp" "$ledger"
  tmp=''
)

notify_transition() {
  local state="$1" session="$2" pane="$3" backend="$AGENT_STATUS_SOUND_BACKEND"
  local sound="$AGENT_STATUS_SOUND_FILE" ledger key now
  [[ "$AGENT_STATUS_SOUND_ENABLED" == 1 ]] || return 0
  notify_attention_state "$state" || return 0
  [[ "$state" != done ]] || sound="/System/Library/Sounds/Hero.aiff"
  case "$(notify_sound_status "$sound")" in
    ready) ;;
    unsupported_backend) notify_debug "unsupported backend: $backend"; return 0 ;;
    backend_missing) notify_debug "backend unavailable: $backend"; return 0 ;;
    file_missing) notify_debug "sound file unavailable: $sound"; return 0 ;;
    *) return 0 ;;
  esac

  mkdir -p "$STATUS_DIR" || return 0
  ledger="$STATUS_DIR/notifications.tsv"
  key="${state}|$(printf '%s' "$session" | tr -c '[:alnum:]_.-' '_')|$(printf '%s' "$pane" | tr -c '[:alnum:]_.-' '_')"
  now="$(notify_now)"
  notify_reserve "$ledger" "$key" "$now" || return 0
  if ! "$backend" "$sound"; then
    notify_debug "backend failed: $backend"
    return 0
  fi
}
