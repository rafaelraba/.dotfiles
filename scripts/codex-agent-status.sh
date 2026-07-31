#!/usr/bin/env bash
set -euo pipefail

# Codex legacy notify adapter. Codex only emits agent-turn-complete here, so
# this adapter deliberately records completion without inferring lifecycle.
readonly AGENT_STATUS_SCRIPT="$HOME/.dotfiles/scripts/agent-status.sh"

if (($# < 2)); then
  exit 0
fi

notifier="$1"
shift
payload="${!#}"

event_type="$(/usr/bin/python3 - "$payload" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
except (IndexError, json.JSONDecodeError):
    payload = {}

print(payload.get("type", ""))
PY
)"

if [[ "$event_type" == "agent-turn-complete" ]]; then
  if [[ -n "${TMUX:-}" && -x "$AGENT_STATUS_SCRIPT" ]]; then
    "$AGENT_STATUS_SCRIPT" set done "" "" codex "$(date +%s)" >/dev/null 2>&1 || true
  fi
fi

if [[ -x "$notifier" ]]; then
  "$notifier" "$@" >/dev/null 2>&1 || true
fi
