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

attach_session() {
  # Bypass tmux's nesting guard while reconnecting through the same server socket.
  socket=${TMUX%%,*}
  unset TMUX
  exec tmux -S "$socket" attach-session -t "$1"
}

toggle_float() {
  session=$1
  start_directory=$2
  target_pane=$3
  window_width=$4
  window_height=$5

  current_float=$(tmux list-panes -t "$target_pane" -F '#{pane_id}' \
    -f "#{&&:#{pane_floating_flag},#{==:#{@internal_session},$session}}")
  if [ -n "$current_float" ]; then
    tmux kill-pane -t "$current_float"
    exit 0
  fi

  for pane in $(tmux list-panes -a -F '#{pane_id}' \
    -f "#{&&:#{pane_floating_flag},#{==:#{@internal_session},$session}}"); do
    tmux kill-pane -t "$pane"
  done

  tmux has-session -t "$session" 2>/dev/null ||
    tmux new-session -d -s "$session" -c "$start_directory"
  configure_session "$session"

  width=$((window_width * 80 / 100))
  height=$((window_height * 80 / 100))
  x=$(((window_width - width) / 2))
  y=$(((window_height - height) / 2))

  float=$(tmux new-pane -P -F '#{pane_id}' -f \
    -c "$start_directory" -x "$width" -y "$height" -X "$x" -Y "$y" \
    -S 'fg=#7aa2f7' -R 'fg=#3b4261' -t "$target_pane" \
    "$0" --attach "$session")
  tmux set-option -p -t "$float" @internal_session "$session"
  tmux select-pane -t "$float"
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

if [ "${1:-}" = "--attach" ]; then
  attach_session "${2:-}"
fi

if [ "${1:-}" = "--toggle" ]; then
  toggle_float "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"
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
