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

# Rendering uses one bulk pane snapshot and tabs deliberately carry no detail.
FAKE_BIN="$TMP/bin"
TMUX_LOG="$TMP/tmux.log"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_LOG"
case "$1" in
  list-sessions) printf '1 rafaba\n2 other\n' ;;
  list-panes) printf 'rafaba\t0\tmain\t%%7\tbash\tmain\t/tmp\nrafaba\t1\tcode\t%%8\tclaude\tcode\t/tmp\nother\t0\twork\t%%13\tvim\twork\t/tmp\n' ;;
esac
EOF
chmod +x "$FAKE_BIN/tmux"
render_tab() {
  TMUX_LOG="$TMUX_LOG" PATH="$FAKE_BIN:$PATH" "$ROOT/scripts/status-sessions.sh" "$1"
}

"$SCRIPT" clear rafaba
"$SCRIPT" set done rafaba %7 adapter 1
single_tab="$(render_tab rafaba)"
check_contains 'rafaba' "$single_tab" 'tab includes session name'
[[ "$single_tab" != *'done'* && "$single_tab" != *'running'* && "$single_tab" != *'1 '* ]] || fail=1
check 1 "$(grep -c '^list-panes -a' "$TMUX_LOG" || true)" 'one bulk pane snapshot per status render'
other_tab="$(render_tab other)"
[[ "$single_tab" == *'other'*'rafaba'* && "$other_tab" == *'other'*'rafaba'* ]] || fail=1
check_contains '#[fg=#a6da95]●#[fg=#ffffff] rafaba' "$single_tab" 'active point resets to white label'
check_contains '#[fg=#3b4261]●#[fg=#ffffff] other' "$single_tab" 'inactive point resets to white label'
[[ "$single_tab" != *'#[fg=#a6da95]● rafaba'* && "$single_tab" != *'#[fg=#3b4261]● other'* ]] || fail=1
check_contains '[✓ rafaba]' "$(NO_COLOR=1 render_tab rafaba)" 'no-color tab keeps distinct marker'

# Timing instrumentation records every render for deterministic budget coverage.
TIMING_FILE="$TMP/render-ms"
for _ in $(seq 1 10); do AGENT_STATUS_TIMING_FILE="$TIMING_FILE" render_tab rafaba >/dev/null; done
timing_count=0; [[ -f "$TIMING_FILE" ]] && timing_count="$(wc -l <"$TIMING_FILE" | tr -d ' ')"
check 10 "$timing_count" 'ten render timing samples'

# Picker consumes one bulk snapshot, keeps hierarchy searchable, and switches panes.
PICKER_BIN="$TMP/picker-bin" PICKER_LOG="$TMP/picker.log" PICKER_ROWS="$TMP/picker.rows" snapshot="$TMP/panes.tsv"
mkdir -p "$PICKER_BIN"
cat >"$PICKER_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
input="$(cat)"; printf '%s\n' "$input" >>"$PICKER_LOG"; printf '%s\n' "$input" >"$PICKER_ROWS"; printf '%s\n' "$input" | grep "^${PICKER_SELECTION}" || true
EOF
cat >"$PICKER_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PICKER_LOG"
case "$1" in list-panes) printf 'alpha\t0\tmain\t%%8\tcmd;$(touch nope)\ttitle\t/tmp/a b\n' ;; display-popup) : ;; esac
EOF
chmod +x "$PICKER_BIN/fzf" "$PICKER_BIN/tmux"
{ for n in $(seq 1 14); do printf 'alpha\t%s\twindow %s\t%%%s\tcmd-%s;$(touch nope)\ttitle\t/tmp/a b\n' "$n" "$n" "$n" "$n"; done; } >"$snapshot"
PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'p\037%8' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$snapshot" >/dev/null 2>&1 || true
check_contains '▾ alpha' "$(cat "$PICKER_LOG")" 'picker hierarchy session row'
check_contains 'cmd-14;$(touch nope)' "$(cat "$PICKER_LOG")" 'picker keeps special command inert'
check_contains 'switch-client -t %8' "$(cat "$PICKER_LOG")" 'picker switches selected pane'
visible_rows="$(cut -f2- "$PICKER_ROWS")"
[[ "$visible_rows" != *'%8'* && "$visible_rows" != *'idle'* ]] || fail=1
check_contains $'\033[38;2;146;131;116m●\033[0m cmd-14' "$visible_rows" 'picker state dot is color-scoped'
check 1 "$(test -e nope; printf '%s' "$?")" 'picker does not execute command data'
: >"$PICKER_LOG"
PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'s\037alpha' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$snapshot" >/dev/null 2>&1 || true
check_contains 'switch-client -t =alpha' "$(cat "$PICKER_LOG")" 'picker switches selected session'
: >"$PICKER_LOG"
PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'w\037alpha\0378' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$snapshot" >/dev/null 2>&1 || true
check_contains 'switch-client -t =alpha' "$(cat "$PICKER_LOG")" 'picker switches selected window session'
check_contains 'select-window -t :8' "$(cat "$PICKER_LOG")" 'picker switches selected window'
PICKER_LOG="$PICKER_LOG" PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker-wrapper.sh" alpha /tmp >/dev/null || true
check_contains 'display-popup -d /tmp -w 90% -h 80%' "$(cat "$PICKER_LOG")" 'picker popup percentage sizing'
check 1 "$(grep -c '^list-panes -a' "$PICKER_LOG" || true)" 'picker opens with one bulk snapshot'

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

# On macOS, an enabled configuration without a custom file resolves to the
# readable system sound. The configured path remains a single argv value.
cat >"$TMP/macos-default.conf" <<'EOF'
AGENT_STATUS_CONFIG_VERSION=1
AGENT_STATUS_SOUND_ENABLED=1
AGENT_STATUS_SOUND_STATES=(permission)
AGENT_STATUS_SOUND_BACKEND=afplay
AGENT_STATUS_SOUND_FILE=""
EOF
cat >"$TMP/disabled.conf" <<'EOF'
AGENT_STATUS_CONFIG_VERSION=1
AGENT_STATUS_SOUND_ENABLED=0
EOF
macos_default_output="$(AGENT_STATUS_CONFIG="$TMP/macos-default.conf" AGENT_STATUS_PLATFORM=Darwin AGENT_STATUS_NOW=200 SOUND_LOG="$SOUND_LOG" PATH="$FAKE_BIN:$SOUND_BIN:$PATH" "$SCRIPT" set permission macos %13 adapter 1 2>&1)"
check "1:/System/Library/Sounds/Glass.aiff" "$(sed -n '5p' "$SOUND_LOG")" 'macOS default sound remains one argv'
check permission "$(AGENT_STATUS_CONFIG="$TMP/macos-default.conf" AGENT_STATUS_PLATFORM=Darwin AGENT_STATUS_NOW=200 PATH="$PATH" "$SCRIPT" get macos)" 'macOS default preserves visual state'

# Doctor reports disabled, unsafe, missing backend/file, and ready setups
# without invoking a configured backend.
check_contains $'sound_enabled\t0\nsound_backend\tafplay\nsound_file\t\nsound_status\tdisabled' "$(AGENT_STATUS_CONFIG="$TMP/disabled.conf" "$SCRIPT" doctor)" 'doctor disabled sound'
check_contains $'sound_status\tunsupported_backend' "$(AGENT_STATUS_CONFIG="$TMP/unsafe.conf" "$SCRIPT" doctor)" 'doctor unsafe backend'
check_contains $'sound_status\tbackend_missing' "$(AGENT_STATUS_CONFIG="$TMP/missing.conf" PATH="/usr/bin:/bin" "$SCRIPT" doctor)" 'doctor missing backend'
check_contains $'sound_status\tfile_missing' "$(AGENT_STATUS_CONFIG="$TMP/missing-sound.conf" PATH="$SOUND_BIN:$PATH" "$SCRIPT" doctor)" 'doctor missing file'
check_contains $'sound_status\tready' "$(AGENT_STATUS_CONFIG="$TMP/sound.conf" PATH="$SOUND_BIN:$PATH" "$SCRIPT" doctor)" 'doctor ready setup'

# A macOS-only default must not turn a disabled Linux configuration into an
# unavailable sound failure.
check_contains $'sound_file\t\nsound_status\tdisabled' "$(AGENT_STATUS_CONFIG="$TMP/disabled.conf" AGENT_STATUS_PLATFORM=Linux "$SCRIPT" doctor)" 'disabled Linux portability'

if ((fail)); then
  exit 1
fi
printf 'agent-status protocol checks passed\n'
