#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/agent-status.sh"
ORDER="$ROOT/scripts/agent-status/order.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/cache" AGENT_STATUS_CONFIG="$TMP/missing.conf"
mkdir -p "$HOME"

fail=0
check() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$label" "$expected" "$actual" >&2
    fail=1
  fi
}

check_contains() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != *"$expected"* ]]; then
    printf 'FAIL: %s (expected output containing %s, got %s)\n' "$label" "$expected" "$actual" >&2
    fail=1
  fi
}

# Missing config and state paths must use defaults and create state safely.
check running "$("$SCRIPT" set running alpha %1 adapter 1 && "$SCRIPT" get alpha)" 'missing config fallback'

# Unsupported producer states are a safe blocked condition.
"$SCRIPT" set mystery beta %2 adapter 1
check blocked "$("$SCRIPT" get beta)" 'unsupported state normalization'

# Active records expire; terminal records remain visible for their longer TTL.
AGENT_STATUS_NOW=100 "$SCRIPT" set running stale %3 adapter 1
check idle "$(AGENT_STATUS_NOW=1000 "$SCRIPT" get stale)" 'stale running recovery'
AGENT_STATUS_NOW=100 "$SCRIPT" set done complete %4 adapter 1
check done "$(AGENT_STATUS_NOW=1000 "$SCRIPT" get complete)" 'terminal done preservation'

# Inspect exposes stable protocol diagnostics for a fresh v1 record.
AGENT_STATUS_NOW=100 "$SCRIPT" set running inspect %6 adapter 1
check $'effective_state\trunning\nstored_state\trunning\nage\t0\nstale_reason\tfresh' "$(AGENT_STATUS_NOW=100 "$SCRIPT" inspect inspect %6)" 'inspect diagnostics'

# Legacy one-line records remain readable during the compatibility window.
mkdir -p "$XDG_CACHE_HOME/agent-status/sessions"
printf 'permission\n' >"$XDG_CACHE_HOME/agent-status/sessions/legacy"
check permission "$("$SCRIPT" get legacy)" 'legacy state compatibility'

# Malformed timestamp metadata must recover safely without arithmetic evaluation.
printf '1\trunning\tinvalid\tadapter\t1\n' >"$XDG_CACHE_HOME/agent-status/sessions/malformed"
check idle "$("$SCRIPT" get malformed)" 'malformed record recovery'

# A newer event wins when writers race on the same pane.
"$SCRIPT" set running race %5 adapter 1 &
"$SCRIPT" set done race %5 adapter 2 &
wait
check done "$("$SCRIPT" get race)" 'last accepted event'

# Configured sessions must remain first and unknown sessions must use lexical order.
cat >"$TMP/order.conf" <<'EOF'
AGENT_STATUS_CONFIG_VERSION=1
AGENT_STATUS_SESSION_ORDER=(work main)
EOF
ordered_sessions() {
  AGENT_STATUS_CONFIG="$TMP/order.conf" bash -c '
    source "$1/scripts/agent-status/config.sh"
    source "$2"
    agent_status_load_config
    printf "%s\n" zebra main alpha work beta | agent_status_order_sessions
  ' _ "$ROOT" "$ORDER"
}
check $'work\nmain\nalpha\nbeta\nzebra' "$(ordered_sessions)" 'configured lexical session order'
check "$(ordered_sessions)" "$(ordered_sessions)" 'restart-stable session order'

# Aggregate summaries retain lower-priority state counts while exposing urgency.
"$SCRIPT" set blocked mixed %7 adapter 1
"$SCRIPT" set done mixed %8 adapter 1
check $'state=blocked\tblocked=1\tdone=1' "$("$SCRIPT" summary mixed)" 'aggregate state counts'

# Symbols and labels remain semantically distinct without color.
check '? permission' "$(AGENT_STATUS_CONFIG="$TMP/order.conf" bash -c 'source "$1"; printf "%s %s" "$(agent_status_state_symbol permission)" "$(agent_status_state_label permission)"' _ "$ORDER")" 'permission no-color marker'
check '… input' "$(AGENT_STATUS_CONFIG="$TMP/order.conf" bash -c 'source "$1"; printf "%s %s" "$(agent_status_state_symbol waiting_for_input)" "$(agent_status_state_label waiting_for_input)"' _ "$ORDER")" 'input no-color marker'

# The active tab describes tracked records after the session name without
# repeating its dominant state or showing a singular count.
FAKE_BIN="$TMP/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) printf '1 rafaba\n' ;;
  list-panes) printf '%%7\n%%8\n' ;;
esac
EOF
chmod +x "$FAKE_BIN/tmux"
render_tab() {
  PATH="$FAKE_BIN:$PATH" "$ROOT/scripts/status-sessions.sh" rafaba
}

"$SCRIPT" clear rafaba
"$SCRIPT" set done rafaba %7 adapter 1
single_tab="$(render_tab)"
check_contains 'rafaba · done' "$single_tab" 'singular tracked record suppresses count'
[[ "$single_tab" != *'done:rafaba'* && "$single_tab" != *'+ done'* ]] || fail=1

"$SCRIPT" clear rafaba
"$SCRIPT" set done rafaba %7 adapter 1
"$SCRIPT" set done rafaba %8 adapter 1
check_contains 'rafaba · 2 done' "$(render_tab)" 'plural tracked records render count'

"$SCRIPT" clear rafaba
"$SCRIPT" set done rafaba %7 adapter 1
"$SCRIPT" set running rafaba %8 adapter 1
mixed_tab="$(render_tab)"
check_contains 'rafaba · 1 done · 1 running' "$mixed_tab" 'mixed record counts use ordered separators'
check_contains '[● rafaba · 1 done · 1 running]' "$(NO_COLOR=1 render_tab)" 'no-color active tab remains readable'

# Sound is opt-in, synchronous for deterministic tests, and deduplicated by
# attention state plus session/pane identity.
SOUND_BIN="$TMP/sound-bin"
SOUND_LOG="$TMP/sound.log"
SOUND_FILE="$TMP/sound file.aiff"
mkdir -p "$SOUND_BIN"
printf 'sound' >"$SOUND_FILE"
cat >"$SOUND_BIN/afplay" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$#:$1" >>"$SOUND_LOG"
EOF
cp "$SOUND_BIN/afplay" "$SOUND_BIN/paplay"
chmod +x "$SOUND_BIN/afplay" "$SOUND_BIN/paplay"
cat >"$TMP/sound.conf" <<EOF
AGENT_STATUS_CONFIG_VERSION=1
AGENT_STATUS_SOUND_ENABLED=1
AGENT_STATUS_SOUND_STATES=(permission error)
AGENT_STATUS_SOUND_COOLDOWN=30
AGENT_STATUS_SOUND_BACKEND=afplay
AGENT_STATUS_SOUND_FILE="$SOUND_FILE"
EOF
sound_set() {
  AGENT_STATUS_CONFIG="$TMP/sound.conf" AGENT_STATUS_NOW="$1" SOUND_LOG="$SOUND_LOG" PATH="$SOUND_BIN:$PATH" "$SCRIPT" set "$2" sound %9 adapter "$3"
}
sound_set 100 permission 1
sound_set 110 permission 2
sound_set 140 permission 3
check 2 "$(wc -l <"$SOUND_LOG" | tr -d ' ')" 'sound cooldown and expiry'
check "1:$SOUND_FILE" "$(sed -n '1p' "$SOUND_LOG")" 'sound path remains one argv'
sound_set 141 error 4
check 3 "$(wc -l <"$SOUND_LOG" | tr -d ' ')" 'distinct attention event has separate ledger identity'
sed 's/AGENT_STATUS_SOUND_BACKEND=afplay/AGENT_STATUS_SOUND_BACKEND=paplay/' "$TMP/sound.conf" >"$TMP/paplay.conf"
AGENT_STATUS_CONFIG="$TMP/paplay.conf" AGENT_STATUS_NOW=142 SOUND_LOG="$SOUND_LOG" PATH="$SOUND_BIN:$PATH" "$SCRIPT" set error sound %10 adapter 5
check 4 "$(wc -l <"$SOUND_LOG" | tr -d ' ')" 'allowlisted paplay backend'

# An allowlist rejection or unavailable backend is quiet unless debug is opted in;
# both cases leave the visual protocol state intact.
sed 's/AGENT_STATUS_SOUND_BACKEND=afplay/AGENT_STATUS_SOUND_BACKEND=not-a-player/' "$TMP/sound.conf" >"$TMP/unsafe.conf"
unsafe_output="$(AGENT_STATUS_CONFIG="$TMP/unsafe.conf" AGENT_STATUS_DEBUG=1 "$SCRIPT" set permission visual %10 adapter 1 2>&1)"
check permission "$(AGENT_STATUS_CONFIG="$TMP/unsafe.conf" "$SCRIPT" get visual)" 'unsafe backend preserves visual state'
check_contains 'unsupported backend: not-a-player' "$unsafe_output" 'allowlist diagnostic'
sed 's/AGENT_STATUS_SOUND_BACKEND=afplay/AGENT_STATUS_SOUND_BACKEND=paplay/' "$TMP/sound.conf" >"$TMP/missing.conf"
missing_output="$(AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_DEBUG=1 PATH="/usr/bin:/bin" "$SCRIPT" set permission missing %11 adapter 1 2>&1)"
check permission "$(AGENT_STATUS_CONFIG="$TMP/missing.conf" "$SCRIPT" get missing)" 'missing backend preserves visual state'
check_contains 'backend unavailable: paplay' "$missing_output" 'missing backend diagnostic'
sed 's|AGENT_STATUS_SOUND_FILE=.*|AGENT_STATUS_SOUND_FILE="/missing sound.aiff"|' "$TMP/sound.conf" >"$TMP/missing-sound.conf"
missing_sound_output="$(AGENT_STATUS_CONFIG="$TMP/missing-sound.conf" AGENT_STATUS_DEBUG=1 "$SCRIPT" set permission silent %12 adapter 1 2>&1)"
check permission "$(AGENT_STATUS_CONFIG="$TMP/missing-sound.conf" "$SCRIPT" get silent)" 'missing sound preserves visual state'
check_contains 'sound file unavailable: /missing sound.aiff' "$missing_sound_output" 'missing sound diagnostic'

if ((fail)); then
  exit 1
fi
printf 'agent-status protocol checks passed\n'
