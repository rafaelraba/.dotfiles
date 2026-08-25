#!/usr/bin/env bash
set -euo pipefail

target_session="${1:-}"
original_name="${2:-}"
target_client="${3:-}"

[[ -n "$target_session" && -n "$original_name" ]] || exit 1

session_exists() {
  tmux has-session -t "=$1" 2>/dev/null || tmux has-session -t "=_$1" 2>/dev/null
}

validate_name() {
  local name="$1"
  [[ "$name" == "$original_name" ]] && return 0
  [[ -n "$name" ]] || { printf 'Name cannot be empty.'; return 1; }
  [[ "$name" =~ ^[[:alnum:]_-]+$ ]] || {
    printf 'Use letters, numbers, underscores, or hyphens.'
    return 1
  }
  [[ "$name" != _* ]] || { printf 'Names starting with an underscore are reserved for popups.'; return 1; }
  ! session_exists "$name" || { printf 'Session "%s" already exists.' "$name"; return 1; }
}

render_input() {
  printf '\r\033[2K\033[38;5;179mWorkspace name:\033[0m \033[38;5;223m%s\033[0m' "$name"
}

name="$original_name"
error=''
while true; do
  if [[ -n "$error" ]]; then
    tmux resize-pane -y 2
    printf '\033[H\033[2J'
    render_input
    printf '\n\033[38;5;203m%s\033[0m' "$error"
    printf '\033[H'
    error=''
  fi

  render_input
  while true; do
    if ! IFS= read -r -s -n 1 key; then
      exit 0
    fi
    case "$key" in
      $'\033') exit 0 ;;
      '') break ;;
      $'\177' | $'\010') name="${name%?}" ;;
      $'\025') name='' ;;
      [[:print:]]) name+="$key" ;;
    esac
    render_input
  done

  if error="$(validate_name "$name")"; then
    [[ "$name" == "$original_name" ]] && exit 0
    if tmux rename-session -t "$target_session" "$name" 2>/dev/null; then
      if [[ -n "$target_client" ]]; then
        tmux refresh-client -S -t "$target_client" 2>/dev/null || true
      fi
      exit 0
    fi
    error='Rename failed. The session changed or the name is now in use.'
  fi
done
