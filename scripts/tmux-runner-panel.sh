#!/usr/bin/env bash
set -euo pipefail

# Panel inferior persistente para procesos de desarrollo.
# Uso: ~/.dotfiles/scripts/tmux-runner-panel.sh [working_directory]
#
# - Si el panel runner ya existe en la ventana actual, lo desacopla a una
#   ventana oculta (__runner).
# - Si existe en otra ventana, lo une al pie de la ventana actual.
# - Si no existe, lo crea y guarda su pane_id en la opción @runner_pane.

readonly RUNNER_PANE_OPTION="@runner_pane"
readonly RUNNER_WINDOW_NAME="__runner"
readonly PANEL_HEIGHT_PERCENT="25%"

cwd="${1:-$HOME}"
current_window="$(tmux display-message -p '#{window_id}')"
runner_pane="$(tmux show-option -qv "$RUNNER_PANE_OPTION" 2>/dev/null || true)"

pane_exists() {
  local pane_id="$1"
  [[ -n "$pane_id" ]] || return 1
  [[ -n "$(tmux list-panes -a -F '#{pane_id}' -f "#{==:#{pane_id},${pane_id}}" 2>/dev/null || true)" ]]
}

if pane_exists "$runner_pane"; then
  runner_window="$(tmux display-message -p -t "$runner_pane" '#{window_id}')"

  if [[ "$runner_window" == "$current_window" ]]; then
    tmux break-pane -d -n "$RUNNER_WINDOW_NAME" -s "$runner_pane"
    exit 0
  fi

  tmux join-pane -v -f -l "$PANEL_HEIGHT_PERCENT" -s "$runner_pane" -t "$current_window"
  tmux select-pane -t "$runner_pane"
  exit 0
fi

# No tracked runner pane: clear any stale option and create one.
tmux set-option -qu "$RUNNER_PANE_OPTION"
tmux split-window -v -f -l "$PANEL_HEIGHT_PERCENT" -c "$cwd"
tmux set-option -q "$RUNNER_PANE_OPTION" "$(tmux display-message -p '#{pane_id}')"
