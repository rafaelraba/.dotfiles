#!/usr/bin/env bash
set -euo pipefail

# Navega entre sesiones "normales" de tmux (ignora las flotantes _*).
# Uso: ~/.dotfiles/scripts/tmux-switch-session.sh [prev|next]

readonly DIRECTION="${1:-next}"

if [[ "$DIRECTION" != "prev" && "$DIRECTION" != "next" ]]; then
  printf 'Usage: %s [prev|next]\n' "${0##*/}" >&2
  exit 1
fi

sessions=()
while IFS= read -r session; do
  [[ -n "$session" ]] && sessions+=("$session")
done < <(
  tmux list-sessions -F '#{session_created} #{session_name}' -f '#{?#{m:_*,#{session_name}},0,1}' 2>/dev/null \
    | sort -n \
    | cut -d ' ' -f 2- \
    || true
)

if ((${#sessions[@]} <= 1)); then
  exit 0
fi

current="$(tmux display-message -p '#S')"
current_idx=-1
for i in "${!sessions[@]}"; do
  if [[ "${sessions[$i]}" == "$current" ]]; then
    current_idx=$i
    break
  fi
done

# Si la sesión actual no está en la lista (p. ej. es una flotante), ir a la primera disponible.
if ((current_idx == -1)); then
  tmux switch-client -t "${sessions[0]}"
  exit 0
fi

case "$DIRECTION" in
  prev) target_idx=$(((current_idx - 1 + ${#sessions[@]}) % ${#sessions[@]})) ;;
  next) target_idx=$(((current_idx + 1) % ${#sessions[@]})) ;;
esac

target="${sessions[$target_idx]}"
if [[ "$target" != "$current" ]]; then
  tmux switch-client -t "$target"
fi
