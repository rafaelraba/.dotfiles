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

# The OpenCode adapter supplies its source and a monotonic process-local event ID,
# and keeps only active states fresh without retaining the process after terminal state.
ADAPTER_BIN="$TMP/adapter-bin"
mkdir -p "$ADAPTER_BIN"
cat >"$ADAPTER_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'#S'*) printf 'adapter-session\n' ;;
  *'#{pane_id}'*) printf '%%42\n' ;;
esac
EOF
chmod +x "$ADAPTER_BIN/tmux"
"$SCRIPT" set idle adapter-session %42 previous 999
HOME=/Users/rafaba TMUX=/tmp/tmux-test TMUX_PANE= PATH="$ADAPTER_BIN:$PATH" bun -e '
  Date.now = () => 1000
  let callback
  let intervalCount = 0
  let intervalMs = 0
  let timerCleared = false
  let timerUnrefed = false
  const timer = { unref: () => { timerUnrefed = true } }
  globalThis.setInterval = (next, ms) => {
    callback = next
    intervalCount += 1
    intervalMs = ms
    return timer
  }
  globalThis.clearInterval = (candidate) => {
    if (candidate === timer) timerCleared = true
  }
  const plugin = (await import(process.argv[1])).TmuxAgentStatusPlugin
  const hooks = await plugin({})
  await hooks["chat.message"]({ sessionID: "root" })
  await hooks.event({
    event: { type: "session.status", properties: { sessionID: "child", status: { type: "busy" } } },
  })
  if (intervalCount !== 1 || intervalMs !== 240000 || !timerUnrefed) {
    throw new Error("OpenCode heartbeat must be single, bounded, and unrefed")
  }
  callback()
  const heartbeatRecord = await Bun.file(process.argv[2]).text()
  if (!heartbeatRecord.endsWith("\topencode\t1002\n")) {
    throw new Error("active OpenCode state was not refreshed")
  }
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "root" } } })
  if (timerCleared) throw new Error("idle root stopped heartbeat while child session was busy")
  const delegatedRecord = await Bun.file(process.argv[2]).text()
  if (!delegatedRecord.includes("\trunning\t") || !delegatedRecord.endsWith("\topencode\t1003\n")) {
    throw new Error("idle root overrode delegated child activity")
  }
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "child" } } })
  if (!timerCleared) throw new Error("terminal OpenCode state did not stop heartbeat")
  const terminalRecord = await Bun.file(process.argv[2]).text()
  if (!terminalRecord.includes("\tdone\t") || !terminalRecord.endsWith("\topencode\t1004\n")) {
    throw new Error("terminal OpenCode state was not recorded")
  }
  await hooks.event({
    event: { type: "session.status", properties: { sessionID: "child", status: { type: "idle" } } },
  })
  if (await Bun.file(process.argv[2]).text() !== terminalRecord) {
    throw new Error("duplicate terminal OpenCode event erased done or advanced its event ID")
  }
  callback()
  if (await Bun.file(process.argv[2]).text() !== terminalRecord) {
    throw new Error("terminal OpenCode state kept heartbeating")
  }
 ' "$ROOT/editors/opencode/plugins/tmux-agent-status.ts" "$XDG_CACHE_HOME/agent-status/panes/adapter-session__42"
IFS=$'\t' read -r _ adapter_state _ adapter_source adapter_event <"$XDG_CACHE_HOME/agent-status/panes/adapter-session__42"
check done "$adapter_state" 'OpenCode terminal event supersedes older record'
check opencode "$adapter_source" 'OpenCode protocol source'
check 1004 "$adapter_event" 'OpenCode heartbeat keeps monotonic event IDs'
if [[ "${AGENT_STATUS_PROTOCOL_FOCUS:-}" == "opencode-heartbeat" ]]; then
  ((fail)) && exit 1
  printf 'OpenCode heartbeat protocol checks passed\n'
  exit 0
fi

# Claude preserves its producer identity so presentation can identify the agent
# even when tmux displays a transient command or title.
mkdir -p "$HOME/.dotfiles/scripts"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$SCRIPT" >"$HOME/.dotfiles/scripts/agent-status.sh"
chmod +x "$HOME/.dotfiles/scripts/agent-status.sh"
printf '{"hook_event_name":"UserPromptSubmit"}\n' | TMUX=/tmp/tmux-test TMUX_PANE=%43 PATH="$ADAPTER_BIN:$PATH" "$ROOT/scripts/claude-agent-status.sh"
IFS=$'\t' read -r _ claude_state _ claude_source _ <"$XDG_CACHE_HOME/agent-status/panes/adapter-session__43"
check running "$claude_state" 'Claude adapter records running state'
check claude "$claude_source" 'Claude adapter records protocol source'

# Configured sessions remain first and unknown sessions preserve source order.
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
check $'work\nmain\nzebra\nalpha\nbeta' "$(ordered_sessions)" 'configured stable session order'
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
  list-sessions) printf '20\t$3\tnewest\n10\t$2\tmiddle\n10\t$1\toldest\n' ;;
  list-panes) printf 'oldest\t0\tmain\t%%7\tbash\tmain\t/tmp\tbash\noldest\t1\tcode\t%%8\tclaude\tcode\t/tmp\tclaude\nmiddle\t0\twork\t%%13\tvim\twork\t/tmp\tvim\n' ;;
esac
EOF
chmod +x "$FAKE_BIN/tmux"
render_tab() {
  TMUX_LOG="$TMUX_LOG" PATH="$FAKE_BIN:$PATH" "$ROOT/scripts/status-sessions.sh" "$1"
}

"$SCRIPT" clear oldest
"$SCRIPT" set done oldest %7 adapter 1
single_tab="$(render_tab oldest)"
check_contains 'oldest' "$single_tab" 'tab includes session name'
[[ "$single_tab" != *'done'* && "$single_tab" != *'running'* && "$single_tab" != *'1 '* ]] || fail=1
check 1 "$(grep -c '^list-panes -a' "$TMUX_LOG" || true)" 'one bulk pane snapshot per status render'
other_tab="$(render_tab middle)"
[[ "$single_tab" == *'oldest'*'middle'*'newest'* && "$other_tab" == *'oldest'*'middle'*'newest'* ]] || fail=1
check_contains '#[fg=#a6da95]●#[fg=#ffffff] oldest' "$single_tab" 'active point resets to white label'
check_contains '#[fg=#3b4261]●#[fg=#ffffff] middle' "$single_tab" 'inactive point resets to white label'
[[ "$single_tab" != *'#[fg=#a6da95]● oldest'* && "$single_tab" != *'#[fg=#3b4261]● middle'* ]] || fail=1
check_contains '[✓ oldest]' "$(NO_COLOR=1 render_tab oldest)" 'no-color tab keeps distinct marker'

# Timing instrumentation records every render for deterministic budget coverage.
TIMING_FILE="$TMP/render-ms"
for _ in $(seq 1 10); do AGENT_STATUS_TIMING_FILE="$TIMING_FILE" render_tab oldest >/dev/null; done
timing_count=0; [[ -f "$TIMING_FILE" ]] && timing_count="$(wc -l <"$TIMING_FILE" | tr -d ' ')"
check 10 "$timing_count" 'ten render timing samples'

# Picker consumes one bulk snapshot, keeps hierarchy searchable, and switches panes.
PICKER_BIN="$TMP/picker-bin" PICKER_LOG="$TMP/picker.log" PICKER_ROWS="$TMP/picker.rows" snapshot="$TMP/panes.tsv"
mkdir -p "$PICKER_BIN"
cat >"$PICKER_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PICKER_ARGS"
input="$(cat)"; printf '%s\n' "$input" >>"$PICKER_LOG"; printf '%s\n' "$input" >"$PICKER_ROWS"; printf '%s\n' "$input" | grep "^${PICKER_SELECTION}" || true
EOF
cat >"$PICKER_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PICKER_LOG"
case "$1" in list-panes) printf 'alpha\t0\tmain\t%%8\tcmd;$(touch nope)\ttitle\t/tmp/a b\n' ;; display-popup) : ;; esac
EOF
chmod +x "$PICKER_BIN/fzf" "$PICKER_BIN/tmux"
{ for n in $(seq 1 14); do printf 'alpha\t%s\twindow %s\t%%%s\tcmd-%s;$(touch nope)\ttitle\t/tmp/a b\tcmd-%s\n' "$n" "$n" "$n" "$n" "$n"; done; } >"$snapshot"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'p\037%8' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$snapshot" >/dev/null 2>&1 || true
check_contains '◆ ▾ alpha' "$(cat "$PICKER_LOG")" 'picker marks the active session hierarchy'
check_contains 'cmd-14;$(touch nope)' "$(cat "$PICKER_LOG")" 'picker keeps special command inert'
check_contains 'switch-client -t %8' "$(cat "$PICKER_LOG")" 'picker switches selected pane'
visible_rows="$(cut -f2- "$PICKER_ROWS")"
[[ "$visible_rows" != *'%8'* && "$visible_rows" != *'idle'* ]] || fail=1
check_contains $'└─ \033[38;2;146;131;116m●\033[0m cmd-14' "$visible_rows" 'picker renders idle pane state dot'
[[ "$visible_rows" != *'window '* ]] || fail=1
visible_rows_without_dots="$visible_rows"
for state_dot_color in '125;174;163' '238;212;159' '216;166;87' '169;182;101' '234;105;98' '146;131;116'; do
	visible_rows_without_dots="${visible_rows_without_dots//$'\033[38;2;'"$state_dot_color"$'m●\033[0m'/●}"
done
[[ "$visible_rows_without_dots" != *$'\033['* ]] || fail=1
check 1 "$(test -e nope; printf '%s' "$?")" 'picker does not execute command data'
check_contains 'ctrl-j:down,ctrl-k:up,j:down,k:up,/:change-prompt(  filter › )+unbind(j,k,/)' "$(cat "$TMP/picker.args")" 'hierarchy picker starts in navigation mode and slash enables input'
check_contains '  navigate › ' "$(cat "$TMP/picker.args")" 'hierarchy picker starts with navigation prompt'
check_contains 'Enter switch · j/k or ↑/↓ move · Ctrl-j/k navigate · / search · Esc close' "$(cat "$TMP/picker.args")" 'picker navigation-first help'
check_contains '--ansi' "$(cat "$TMP/picker.args")" 'hierarchy picker renders ANSI state dots'
check_contains '--highlight-line' "$(cat "$TMP/picker.args")" 'hierarchy picker highlights the full focused row'
check_contains 'bg+:#d79921' "$(cat "$TMP/picker.args")" 'hierarchy picker uses Herdr amber selection background'
check_contains 'fg+:#282828' "$(cat "$TMP/picker.args")" 'hierarchy picker uses dark selected foreground without ANSI overrides'
check_contains 'printf "  %s\\n" {3}' "$(cat "$TMP/picker.args")" 'picker preview uses full path field'
check '/tmp/a b' "$(cut -f3 "$PICKER_ROWS" | tail -n 1)" 'picker preview path is field three'
: >"$PICKER_LOG"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'s\037alpha' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$snapshot" >/dev/null 2>&1 || true
check_contains 'switch-client -t =alpha' "$(cat "$PICKER_LOG")" 'picker switches selected session'
claude_snapshot="$TMP/claude-pane.tsv"
"$SCRIPT" set running alpha %15 claude 1
printf 'alpha\t1\t1\t%%15\t1\t1\t/tmp/claude-project\tbash\n' >"$claude_snapshot"
: >"$PICKER_LOG"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'p\037%15' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$claude_snapshot" >/dev/null 2>&1 || true
check_contains '└─' "$(cut -f2- "$PICKER_ROWS")" 'Claude pane keeps hierarchy connector'
check_contains $'\033[38;2;125;174;163m●\033[0m claude' "$(cut -f2- "$PICKER_ROWS")" 'picker renders running pane state dot'
[[ "$(cut -f2 "$PICKER_ROWS")" != *'claude-project'* ]] || fail=1
claude_title_snapshot="$TMP/claude-title-pane.tsv"
printf 'alpha\t1\tmain\t%%18\t2.1.220\t✳ Claude Code\t/tmp/claude-title-project\tbash\n' >"$claude_title_snapshot"
: >"$PICKER_LOG"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'p\037%18' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$claude_title_snapshot" >/dev/null 2>&1 || true
claude_title_rows="$(cut -f2- "$PICKER_ROWS")"
check_contains $'\033[38;2;146;131;116m●\033[0m claude' "$claude_title_rows" 'picker identifies Claude Code title without cache source'
[[ "$claude_title_rows" != *'2.1.220'* ]] || fail=1
opencode_title_snapshot="$TMP/opencode-title-pane.tsv"
"$SCRIPT" set running alpha %19 opencode 1
printf 'alpha\t1\topencode\t%%19\t2.1.220\t✳ Claude Code\t/tmp/opencode-title-project\tbash\n' >"$opencode_title_snapshot"
: >"$PICKER_LOG"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'p\037%19' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$opencode_title_snapshot" >/dev/null 2>&1 || true
opencode_title_rows="$(cut -f2- "$PICKER_ROWS")"
check_contains $'\033[38;2;125;174;163m●\033[0m opencode' "$opencode_title_rows" 'picker prioritizes OpenCode cache source over Claude Code title'
[[ "$opencode_title_rows" != *'claude'* && "$opencode_title_rows" != *'2.1.220'* ]] || fail=1
tool_snapshot="$TMP/tool-panes.tsv"
printf 'alpha\t0\topencode\t%%16\topencode\topencode\t/tmp/opencode-project\topencode\nalpha\t0\topencode\t%%17\tzsh\tzsh\t/tmp/zsh-project\tzsh\n' >"$tool_snapshot"
: >"$PICKER_LOG"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=$'p\037%17' PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$tool_snapshot" >/dev/null 2>&1 || true
tool_rows="$(cut -f2- "$PICKER_ROWS")"
check_contains $'\033[38;2;146;131;116m●\033[0m opencode' "$tool_rows" 'picker identifies genuine OpenCode pane'
check_contains $'\033[38;2;146;131;116m●\033[0m zsh' "$tool_rows" 'picker keeps zsh pane distinct from opencode window'
legacy_snapshot="$TMP/sessions.tsv"
printf 'alpha\t1\t1\t/tmp/a b\topencode\tbash\ttitle\nbeta\t1\t0\t/tmp/b\tnvim\tnvim\ttitle\n' >"$legacy_snapshot"
: >"$PICKER_LOG"
PICKER_ARGS="$TMP/picker.args" PICKER_LOG="$PICKER_LOG" PICKER_ROWS="$PICKER_ROWS" PICKER_SELECTION=beta PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker.sh" alpha "$legacy_snapshot" >/dev/null 2>&1 || true
check_contains 'start:pos(2)' "$(cat "$TMP/picker.args")" 'session picker keeps initial position binding'
check_contains 'ctrl-j:down,ctrl-k:up,j:down,k:up,/:change-prompt(  filter › )+unbind(j,k,/)' "$(cat "$TMP/picker.args")" 'session picker starts in navigation mode and slash enables input'
check_contains '  navigate › ' "$(cat "$TMP/picker.args")" 'session picker starts with navigation prompt'
check_contains '--highlight-line' "$(cat "$TMP/picker.args")" 'session picker highlights the full focused row'
check_contains 'switch-client -t beta' "$(cat "$PICKER_LOG")" 'session picker Enter behavior'
: >"$PICKER_LOG"
PICKER_LOG="$PICKER_LOG" PATH="$PICKER_BIN:$PATH" "$ROOT/scripts/session-picker-wrapper.sh" alpha /tmp >/dev/null || true
popup_command="$(cat "$PICKER_LOG")"
check_contains 'display-popup -d /tmp -w 90% -h 80% -b rounded' "$popup_command" 'picker popup percentage sizing with rounded border'
check_contains '-S fg=#d79921' "$popup_command" 'picker popup border uses Herdr amber'
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
AGENT_STATUS_SOUND_STATES=(permission done error)
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
sound_set 142 done 5
sound_set 150 done 6
check 4 "$(wc -l <"$SOUND_LOG" | tr -d ' ')" 'done sound cooldown'
check '1:/System/Library/Sounds/Hero.aiff' "$(sed -n '4p' "$SOUND_LOG")" 'done uses the macOS Hero sound'
sed 's/AGENT_STATUS_SOUND_BACKEND=afplay/AGENT_STATUS_SOUND_BACKEND=paplay/' "$TMP/sound.conf" >"$TMP/paplay.conf"
AGENT_STATUS_CONFIG="$TMP/paplay.conf" AGENT_STATUS_NOW=152 SOUND_LOG="$SOUND_LOG" PATH="$SOUND_BIN:$PATH" "$SCRIPT" set error sound %10 adapter 5
check 5 "$(wc -l <"$SOUND_LOG" | tr -d ' ')" 'allowlisted paplay backend'

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
check "1:/System/Library/Sounds/Glass.aiff" "$(sed -n '6p' "$SOUND_LOG")" 'macOS default sound remains one argv'
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
