#!/usr/bin/env bash
set -euo pipefail

# Claude Code adapter for the generic tmux agent status protocol.
# Claude sends hook payload JSON through stdin; this script intentionally keeps
# parsing minimal and treats unknown events as non-fatal.

readonly AGENT_STATUS_SCRIPT="$HOME/.dotfiles/scripts/agent-status.sh"

if [[ -z "${TMUX:-}" || ! -x "$AGENT_STATUS_SCRIPT" ]]; then
  exit 0
fi

payload="$(cat)"

hook_event_name="$(PAYLOAD="$payload" /usr/bin/python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("PAYLOAD", "{}"))
except Exception:
    payload = {}

print(payload.get("hook_event_name", ""))
PY
)"

set_status() {
  "$AGENT_STATUS_SCRIPT" set "$1" "" "" claude "$(date +%s)" >/dev/null 2>&1 || true
}

case "$hook_event_name" in
  UserPromptSubmit | PreToolUse | PostToolUse)
    set_status running
    ;;
  PermissionRequest | Notification)
    set_status blocked
    ;;
  PostToolUseFailure)
    set_status error
    ;;
  Stop | SubagentStop)
    set_status done
    ;;
  SessionEnd)
    "$AGENT_STATUS_SCRIPT" clear >/dev/null 2>&1 || true
    ;;
esac
