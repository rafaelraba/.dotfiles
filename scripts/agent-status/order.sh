#!/usr/bin/env bash

# Orders newline-delimited session names using configured names first while
# preserving the source order of all other sessions.
agent_status_order_sessions() {
  local input=() ordered=() session configured

  while IFS= read -r session; do
    [[ -n "$session" ]] && input+=("$session")
  done

  for configured in "${AGENT_STATUS_SESSION_ORDER[@]}"; do
    for session in "${input[@]}"; do
      [[ "$session" == "$configured" ]] && ordered+=("$session")
    done
  done

  for session in "${input[@]}"; do
    for configured in "${AGENT_STATUS_SESSION_ORDER[@]}"; do
      [[ "$session" == "$configured" ]] && continue 2
    done
    ordered+=("$session")
  done

  printf '%s\n' "${ordered[@]}"
}

# Orders tab-delimited tmux rows by their first (session-name) field.
agent_status_order_session_rows() {
  local rows=() row name configured
  while IFS= read -r row; do
    [[ -n "$row" ]] && rows+=("$row")
  done

  for configured in "${AGENT_STATUS_SESSION_ORDER[@]}"; do
    for row in "${rows[@]}"; do
      name="${row%%$'\t'*}"
      [[ "$name" == "$configured" ]] && printf '%s\n' "$row"
    done
  done

  for row in "${rows[@]}"; do
    name="${row%%$'\t'*}"
    for configured in "${AGENT_STATUS_SESSION_ORDER[@]}"; do
      [[ "$name" == "$configured" ]] && continue 2
    done
    printf '%s\n' "$row"
  done
}

agent_status_state_symbol() {
  case "$1" in
    error) printf '!' ;;
    permission) printf '?' ;;
    waiting_for_input) printf '…' ;;
    blocked) printf '#' ;;
    done) printf '+' ;;
    running) printf '>' ;;
    *) printf '-' ;;
  esac
}

agent_status_state_label() {
  case "$1" in
    waiting_for_input) printf 'input' ;;
    *) printf '%s' "$1" ;;
  esac
}
