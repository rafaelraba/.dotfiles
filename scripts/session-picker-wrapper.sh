#!/usr/bin/env bash
# Wrapper que captura el estado de sesiones ANTES de abrir el popup.
# Esto evita inconsistencias de tmux dentro del contexto de display-popup (tmux ≥3.6).
#
# Llamado desde el binding de tmux:
#   bind s ... { run-shell -t = "~/.dotfiles/scripts/session-picker-wrapper.sh '#S' '#{pane_current_path}'" }
set -euo pipefail

CURRENT="${1:-}"
PANEDIR="${2:-$HOME}"

# Archivo temporal donde guardamos la lista de sesiones pre-capturada.
# NO se borra aquí: lo limpia session-picker.sh al terminar.
SPFILE=$(mktemp /tmp/tmux-sp-XXXXXX)

# Capturar sesiones desde el contexto real del cliente (fuera de cualquier popup)
tmux list-sessions \
    -f '#{?#{m:_*,#{session_name}},0,1}' \
    -F $'#{session_name}\t#{session_windows}\t#{session_attached}\t#{pane_current_path}\t#{window_name}\t#{pane_current_command}\t#{pane_title}' \
    2>/dev/null > "$SPFILE"

# Si el archivo quedó vacío, algo falló — mostrar error mínimo y salir
if [[ ! -s "$SPFILE" ]]; then
    tmux display-message "No sessions found"
    rm -f "$SPFILE"
    exit 1
fi

SESSION_COUNT=$(wc -l < "$SPFILE" | tr -d ' ')

# Abrir el popup con los datos pre-capturados.
# session-picker.sh lee de $SPFILE y lo borra al terminar.
exec tmux display-popup \
    -d "$PANEDIR" \
    -w 104 -h 13 -b rounded \
    -s "bg=#1d2021,fg=#d4be98" \
    -S "fg=#a9b665" \
    -T "  sessions · $SESSION_COUNT " \
    -E "~/.dotfiles/scripts/session-picker.sh '$CURRENT' '$SPFILE' ; rm -f '$SPFILE'"
