#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
SOCKET="workspace-status-$$"
client_a_pid=''
client_b_pid=''

cleanup() {
  [[ -n "$client_a_pid" ]] && kill "$client_a_pid" 2>/dev/null || true
  [[ -n "$client_b_pid" ]] && kill "$client_b_pid" 2>/dev/null || true
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

contains() {
  [[ "$1" == *"$2"* ]] || fail "$3"
}

tmux -L "$SOCKET" -f /dev/null new-session -d -s alpha 'sleep 30'
tmux -L "$SOCKET" new-session -d -s beta 'sleep 30'
socket_path="$(tmux -L "$SOCKET" display-message -p '#{socket_path}')"
server_pid="$(tmux -L "$SOCKET" display-message -p '#{pid}')"
mkdir -p "$TMP/home" "$TMP/cache"

run_refresh() {
  TMUX="$socket_path,$server_pid,0" HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" \
    AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_RUNTIME_ENABLED=0 \
    TMUX_WORKSPACE_STATUS_RENDERER="${1:-$ROOT/scripts/status-sessions.sh}" \
    "$ROOT/scripts/status-sessions-refresh.sh"
}

run_refresh
alpha_status="$(tmux -L "$SOCKET" show-options -qv -t alpha @workspace-status)"
beta_status="$(tmux -L "$SOCKET" show-options -qv -t beta @workspace-status)"
contains "$alpha_status" '#[bg=#494d64,fg=#ffffff,bold] alpha ' 'alpha does not own its selected rendering'
contains "$beta_status" '#[bg=#494d64,fg=#ffffff,bold] beta ' 'beta does not own its selected rendering'
contains "$alpha_status" ' beta ' 'precomputed alpha rendering lost the full tab list'
contains "$beta_status" ' alpha ' 'precomputed beta rendering lost the full tab list'

cat >"$TMP/failing-renderer" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP/failing-renderer"
tmux -L "$SOCKET" set-option -q -t alpha @workspace-status-updated-at 0
run_refresh "$TMP/failing-renderer"
fallback="$(tmux -L "$SOCKET" display-message -p -t alpha '#{E:@workspace-status}')"
contains "$fallback" '#[bg=#494d64,fg=#ffffff,bold] alpha ' 'expired precomputation did not fail safely to the selected session'
[[ "$fallback" != *' beta '* ]] || fail 'expired precomputation retained a stale tab list'

run_refresh
mkfifo "$TMP/client-a.in" "$TMP/client-b.in"
exec 7<>"$TMP/client-a.in"
exec 8<>"$TMP/client-b.in"
tmux -L "$SOCKET" -C attach-session -t alpha <&7 >"$TMP/client-a.out" 2>&1 &
client_a_pid=$!
for _ in {1..50}; do
  client_a="$(tmux -L "$SOCKET" list-clients -F '#{client_name}' 2>/dev/null || true)"
  [[ -n "$client_a" ]] && break
  sleep 0.01
done
[[ -n "${client_a:-}" ]] || fail 'first control client did not attach'

tmux -L "$SOCKET" -C attach-session -t alpha <&8 >"$TMP/client-b.out" 2>&1 &
client_b_pid=$!
for _ in {1..50}; do
  client_b="$(tmux -L "$SOCKET" list-clients -F '#{client_name}' | grep -v -F "$client_a" || true)"
  [[ -n "$client_b" ]] && break
  sleep 0.01
done
[[ -n "${client_b:-}" ]] || fail 'second control client did not attach'

tmux -L "$SOCKET" set-hook -g client-session-changed "run-shell 'tmux refresh-client -S -t #{q:hook_client}'"
tmux -L "$SOCKET" switch-client -c "$client_a" -t beta
client_sessions="$(tmux -L "$SOCKET" list-clients -F $'#{client_name}\t#{session_name}')"
contains "$client_sessions" "$client_a"$'\t'beta 'switch targeted the wrong client'
contains "$client_sessions" "$client_b"$'\t'alpha 'switch changed the unrelated client'
client_a_status="$(tmux -L "$SOCKET" display-message -p -c "$client_a" -t beta '#{E:@workspace-status}')"
client_b_status="$(tmux -L "$SOCKET" display-message -p -c "$client_b" -t alpha '#{E:@workspace-status}')"
contains "$client_a_status" '#[bg=#494d64,fg=#ffffff,bold] beta ' 'switched client did not immediately select beta'
contains "$client_b_status" '#[bg=#494d64,fg=#ffffff,bold] alpha ' 'other client lost its independent alpha selection'

printf 'tmux workspace status checks passed\n'
