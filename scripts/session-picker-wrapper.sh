#!/usr/bin/env bash
# Wrapper que captura el estado de sesiones ANTES de abrir el popup.
# Esto evita inconsistencias de tmux dentro del contexto de display-popup (tmux ≥3.6).
#
# Llamado desde el binding de tmux:
#   bind s ... { run-shell -t = "~/.dotfiles/scripts/session-picker-wrapper.sh '#S' '#{pane_current_path}'" }
set -euo pipefail

CURRENT="${1:-}"
PANEDIR="${2:-$HOME}"
CLIENT_WIDTH="${3:-$(tmux display-message -p '#{client_width}' 2>/dev/null || printf '108')}"

if ! [[ "$CLIENT_WIDTH" =~ ^[0-9]+$ ]]; then
    CLIENT_WIDTH=108
fi

active_tool() {
    local window_name="$1"
    local command="$2"
    local pane_title="$3"

    case "$pane_title" in
    π*) printf 'pi' ;;
    *)
        case "$window_name" in
        opencode | nvim | claude | pi) printf '%s' "$window_name" ;;
        *) printf '%s' "$command" ;;
        esac
        ;;
    esac
}

project_name() {
    local path="${1%/}"

    if [[ -z "$path" || "$path" == "/" ]]; then
        printf '/'
        return
    fi

    printf '%s' "${path##*/}"
}

calculate_popup_width() {
    local name window_count attached path window_name command pane_title tool project
    local name_width=18
    local tool_width=8
    local project_width=8
    local content_width minimum_width=96 maximum_width desired_width

    while IFS=$'\t' read -r name window_count attached path window_name command pane_title; do
        tool="$(active_tool "$window_name" "$command" "$pane_title")"
        project="$(project_name "$path")"
        ((${#name} > name_width)) && name_width=${#name}
        ((${#tool} > tool_width)) && tool_width=${#tool}
        ((${#project} > project_width)) && project_width=${#project}
    done < "$SPFILE"

    # Includes selector gutters, the active marker, icons, state badge, and borders.
    content_width=$((name_width + tool_width + project_width + 30))
    maximum_width=$((CLIENT_WIDTH - 4))
    desired_width=$content_width

    if ((maximum_width < minimum_width)); then
        printf '%s' "$maximum_width"
        return
    fi

    if ((desired_width < minimum_width)); then
        desired_width=$minimum_width
    elif ((desired_width > maximum_width)); then
        desired_width=$maximum_width
    fi

    printf '%s' "$desired_width"
}

# Archivo temporal donde guardamos la lista de sesiones pre-capturada.
# NO se borra aquí: lo limpia session-picker.sh al terminar.
SPFILE=$(mktemp /tmp/tmux-sp-XXXXXX)

# Capture exactly one render-local pane snapshot before opening the popup.
"$(dirname "${BASH_SOURCE[0]}")/agent-status.sh" snapshot > "$SPFILE"

# Si el archivo quedó vacío, algo falló — mostrar error mínimo y salir
if [[ ! -s "$SPFILE" ]]; then
    tmux display-message "No sessions found"
    rm -f "$SPFILE"
    exit 1
fi

SESSION_COUNT=$(cut -f1 "$SPFILE" | sort -u | wc -l | tr -d ' ')
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf -v picker_command '%q %q %q; rm -f -- %q' "$ROOT/session-picker.sh" "$CURRENT" "$SPFILE" "$SPFILE"

# Abrir el popup con los datos pre-capturados.
# session-picker.sh lee de $SPFILE y lo borra al terminar.
exec tmux display-popup \
    -d "$PANEDIR" \
    -w 90% -h 80% -b rounded \
    -s "bg=#1d2021,fg=#d4be98" \
    -S "fg=#d79921" \
    -T " workspace · $SESSION_COUNT sessions " \
    -E "$picker_command"
