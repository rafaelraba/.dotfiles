#!/usr/bin/env bash
set -euo pipefail

pane_path="${TMUX_NEW_SESSION_PANE_PATH:-${1:-$HOME}}"
base_name="$(basename "$pane_path")"
base_name="${base_name#.}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

session_exists() {
  tmux has-session -t "=$1" 2>/dev/null || tmux has-session -t "=_$1" 2>/dev/null
}

default_name() {
  local suffix=2 candidate
  candidate="$base_name-$suffix"
  while session_exists "$candidate"; do
    suffix=$((suffix + 1))
    candidate="$base_name-$suffix"
  done
  printf '%s' "$candidate"
}

validate_name() {
  local name="$1"
  [[ -n "$name" ]] || { printf 'Name cannot be empty.'; return 1; }
  [[ "$name" =~ ^[[:alnum:]_-]+$ ]] || {
    printf 'Use letters, numbers, underscores, or hyphens.'
    return 1
  }
  ! session_exists "$name" || { printf 'Session "%s" already exists.' "$name"; return 1; }
}

name="$(default_name)"
error=''
while true; do
  header='Enter create and switch · Esc cancel'
  [[ -z "$error" ]] || header="$error · $header"
  selection="$(printf '\n' | fzf --height=100% --layout=reverse --no-border --no-info \
    --print-query --query="$name" --prompt='  session › ' --header="$header" \
    --color='bg:#1d2021,fg:#d4be98,header:#ea6962,prompt:#d79921,pointer:#d79921,query:#d4be98' \
    --bind='enter:accept,esc:abort' 2>/dev/null)" || exit 0
  name="${selection%%$'\n'*}"
  if error="$(validate_name "$name")"; then
    tmux new-session -d -s "$name" -c "$pane_path"
    tmux switch-client -t "=$name"
    exit 0
  fi
done
