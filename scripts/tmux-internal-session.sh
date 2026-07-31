#!/bin/sh
set -eu

configure_session() {
  case "$1" in
    _*) ;;
    *) return 0 ;;
  esac

  tmux set-option -t "$1" status off
  tmux set-option -t "$1" detach-on-destroy on
}

if [ "${1:-}" = "--configure" ]; then
  configure_session "${2:-}"
  exit 0
fi

if [ "${1:-}" = "--configure-existing" ]; then
  tmux list-sessions -F '#{session_name}' -f '#{m:_*,#{session_name}}' 2>/dev/null |
    while IFS= read -r session; do
      [ -n "$session" ] && configure_session "$session"
    done
  exit 0
fi

session="${1:-}"
case "$session" in
  _*) ;;
  *)
    printf 'Internal tmux session names must start with an underscore.\n' >&2
    exit 1
    ;;
esac

tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session" -c "$PWD"
configure_session "$session"
exec tmux attach-session -t "$session"
