#!/usr/bin/env bash
set -euo pipefail

pane_path="$PWD"
base_name="$(basename "$pane_path")"
base_name="${base_name#.}"

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
  [[ "$name" != _* ]] || { printf 'Names starting with an underscore are reserved for popups.'; return 1; }
  ! session_exists "$name" || { printf 'Session "%s" already exists.' "$name"; return 1; }
}

name="$(default_name)"
error=''
while true; do
  header='Enter creates and switches  |  Esc cancels'
  [[ -z "$error" ]] || header="$error\n$header"
  selection="$(printf '\n' | fzf --height=100% --layout=reverse --disabled --no-border --no-info --no-separator --no-scrollbar --pointer='' --margin=0,1 \
    --print-query --query="$name" --prompt='Workspace name: ' --header="$header" \
    --color='bg:#1d2021,fg:#d4be98,bg+:#1d2021,fg+:#1d2021,header:#ea6962,prompt:#d79921,pointer:#1d2021,query:#d4be98' \
    --bind='enter:accept,esc:abort' 2>/dev/null)" || exit 0
  name="${selection%%$'\n'*}"
  if error="$(validate_name "$name")"; then
    tmux new-session -d -s "$name" -c "$pane_path"
    tmux switch-client -t "=$name"
    exit 0
  fi
done
