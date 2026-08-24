#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=agent-status/config.sh
source "$ROOT/agent-status/config.sh"
agent_status_load_config || exit 0

max_age="${TMUX_WORKSPACE_STATUS_MAX_AGE:-15}"
renderer="${TMUX_WORKSPACE_STATUS_RENDERER:-$ROOT/status-sessions.sh}"
fallback=' #[bg=#0b0f1a,fg=#494d64]#[bg=#494d64,fg=#ffffff,bold] #S #[bg=#0b0f1a,fg=#494d64]'
[[ "$max_age" =~ ^[0-9]+$ && "$renderer" = /* && -x "$renderer" ]] || exit 0

server_pid="$(tmux display-message -p '#{pid}' 2>/dev/null || true)"
[[ "$server_pid" =~ ^[0-9]+$ ]] || exit 0
lock="$STATUS_DIR/.tmux-workspace-refresh.$server_pid.lock"
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

now="$(date +%s)"
sessions="$(tmux list-sessions -f '#{?#{m:_*,#{session_name}},0,1}' -F $'#{session_id}\t#{session_name}' 2>/dev/null || true)"
[[ -n "$sessions" ]] || exit 0

while IFS=$'\t' read -r session_id session_name; do
  [[ "$session_id" =~ ^\$[0-9]+$ && -n "$session_name" ]] || continue
  updated="$(tmux show-options -qv -t "$session_id" @workspace-status-updated-at 2>/dev/null || true)"
  if [[ ! "$updated" =~ ^[0-9]+$ ]] || ((updated > now || now - updated > max_age)); then
    tmux set-option -q -t "$session_id" @workspace-status "$fallback" 2>/dev/null || true
  fi

  output="$("$renderer" "$session_name" 2>/dev/null)" || continue
  [[ -n "$output" && "$output" == *"#[bg=#494d64,fg=#ffffff,bold] $session_name "* ]] || continue
  tmux set-option -q -t "$session_id" @workspace-status "$output" 2>/dev/null || continue
  tmux set-option -q -t "$session_id" @workspace-status-updated-at "$now" 2>/dev/null || true
done <<<"$sessions"
