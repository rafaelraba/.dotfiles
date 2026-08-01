#!/usr/bin/env bash
# Wrapper que captura el estado de sesiones ANTES de abrir el panel flotante.
# Esto mantiene una vista coherente mientras se crea el panel nativo de tmux.
#
# Llamado desde el binding de tmux:
#   bind s ... { run-shell -t = '~/.dotfiles/scripts/session-picker-wrapper.sh ...' }
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--run-picker" ]]; then
    CURRENT="${2:-}"
    SPFILE="${3:-}"
    SESSION_COUNT="${4:-0}"
    TARGET_CLIENT="${5:-}"

    trap 'rm -f -- "$SPFILE"' EXIT
    trap 'exit 0' HUP INT TERM

    "$ROOT/session-picker.sh" "$CURRENT" "$SPFILE" "$SESSION_COUNT" "$TARGET_CLIENT"
    exit 0
fi

CURRENT="${1:-}"
PANEDIR="${2:-$HOME}"
CLIENT_WIDTH="${3:-$(tmux display-message -p '#{client_width}' 2>/dev/null || printf '108')}"
CLIENT_HEIGHT="${4:-$(tmux display-message -p '#{client_height}' 2>/dev/null || printf '30')}"
TARGET_PANE="${5:-$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)}"
TARGET_CLIENT="${6:-}"

if ! [[ "$CLIENT_WIDTH" =~ ^[0-9]+$ ]]; then
    CLIENT_WIDTH=108
fi
if ! [[ "$CLIENT_HEIGHT" =~ ^[0-9]+$ ]]; then
    CLIENT_HEIGHT=30
fi
if [[ -z "$TARGET_PANE" ]]; then
    tmux display-message "Unable to locate the source pane"
    exit 1
fi

active_tool() {
    local window_name="$1"
    local command="$2"
    local pane_title="$3"

    case "$pane_title" in
    π*) printf 'pi' ;;
    *)
        case "$window_name" in
        opencode | nvim | claude | codex | pi) printf '%s' "$window_name" ;;
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
# El proceso hijo del panel lo elimina al terminar.
SPFILE=$(mktemp /tmp/tmux-sp-XXXXXX)
trap 'rm -f -- "$SPFILE"' EXIT

# Capture exactly one render-local pane snapshot before opening the popup.
"$(dirname "${BASH_SOURCE[0]}")/agent-status.sh" snapshot |
    awk -F '\t' '$1 !~ /^_/' > "$SPFILE"

# Si el archivo quedó vacío, algo falló — mostrar error mínimo y salir
if [[ ! -s "$SPFILE" ]]; then
    tmux display-message "No sessions found"
    rm -f "$SPFILE"
    exit 1
fi

SESSION_COUNT=$(cut -f1 "$SPFILE" | sort -u | wc -l | tr -d ' ')
FLOAT_WIDTH="$(calculate_popup_width)"
FLOAT_HEIGHT=$((CLIENT_HEIGHT * 80 / 100))
((FLOAT_HEIGHT >= 4)) || FLOAT_HEIGHT=4
FLOAT_X=$(((CLIENT_WIDTH - FLOAT_WIDTH) / 2))
FLOAT_Y=$(((CLIENT_HEIGHT - FLOAT_HEIGHT) / 2))

# The picker child owns the snapshot after new-pane succeeds. Exiting the child
# removes the one-shot floating pane on selection, cancellation, or a signal.
FLOAT_PANE=$(tmux new-pane -P -F '#{pane_id}' -f \
    -c "$PANEDIR" -x "$FLOAT_WIDTH" -y "$FLOAT_HEIGHT" -X "$FLOAT_X" -Y "$FLOAT_Y" \
    -s "bg=#1d2021,fg=#d4be98" -S "fg=#7aa2f7" -R "fg=#7aa2f7" \
    -t "$TARGET_PANE" \
    "$0" --run-picker "$CURRENT" "$SPFILE" "$SESSION_COUNT" "$TARGET_CLIENT")
trap - EXIT
tmux set-option -p -t "$FLOAT_PANE" @session_picker 1
tmux select-pane -t "$FLOAT_PANE"
