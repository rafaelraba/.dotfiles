#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/cache/agent-status/panes"
popup_path="$TMP/project"
mkdir -p "$popup_path"
fail=0

check() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$label" "$expected" "$actual" >&2
    fail=1
  fi
}

check_contains() {
  local expected="$1" actual="$2" label="$3"
  [[ "$actual" == *"$expected"* ]] || { printf 'FAIL: %s\n' "$label" >&2; fail=1; }
}

cat >"$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_LOG"
case "$1" in
  has-session)
    [[ " ${COLLISIONS:-} " == *" ${3#=} "* ]]
    ;;
  list-sessions) printf '10 alpha\n20 beta\n' ;;
  list-panes) printf '%s\n' "${PANE_SNAPSHOT:-}" ;;
  display-message)
    if [[ "$*" == *"-t ${TMUX_PANE:-} #S"* ]]; then
      printf '%s\n' "${CURRENT_SESSION:-alpha}"
    else
      printf 'alpha\n'
    fi
    ;;
  capture-pane) printf '%s\n' "${SCREEN:-}" ;;
  new-pane) printf '%%50\n' ;;
esac
EOF
cat >"$BIN/ps" <<'EOF'
#!/usr/bin/env bash
[[ -n "${PS_LOG:-}" ]] && printf 'scan\n' >>"$PS_LOG"
[[ -n "${PS_SLEEP:-}" ]] && sleep "$PS_SLEEP"
printf '%s\n' "${PS_SNAPSHOT:-}"
EOF
chmod +x "$BIN/tmux" "$BIN/ps"

run_refresh() {
  local screen="$1" process="$2" snapshot="$3"
  SCREEN="$screen" PS_SNAPSHOT="$process" TMUX_LOG="$TMP/tmux.log" PATH="$BIN:$PATH" HOME="$TMP/home" \
    XDG_CACHE_HOME="$TMP/cache" AGENT_STATUS_CONFIG="${REFRESH_CONFIG:-$TMP/missing}" AGENT_STATUS_NOW="${AGENT_STATUS_NOW:-100}" \
    AGENT_STATUS_PANE_SNAPSHOT="$snapshot" "$ROOT/scripts/codex-status-refresh.sh"
}

snapshot=$'alpha\t1\tmain\t%7\tnode\tCodex CLI\t/tmp/project\tzsh\t100'
process=$'100 1 /bin/zsh -zsh\n101 100 /opt/homebrew/bin/node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js'
record="$TMP/cache/agent-status/panes/alpha__7"
run_refresh 'Ready' "$process" "$snapshot"
check idle "$(cut -f2 "$record")" 'process presence is idle'
run_refresh 'Working (3s • esc to interrupt)' "$process" "$snapshot"
check running "$(cut -f2 "$record")" 'current working marker is running'
run_refresh $'› Should I continue?\n• Working (8s • esc to interrupt)' "$process" "$snapshot"
check running "$(cut -f2 "$record")" 'live prefixed working marker wins over stale question'
run_refresh $'Allow command?\n1. Approve once' "$process" "$snapshot"
check permission "$(cut -f2 "$record")" 'visible approval is permission'
run_refresh 'Your answer: continue?' "$process" "$snapshot"
check waiting_for_input "$(cut -f2 "$record")" 'visible question UI waits for input'
printf '1\trunning\t100\tcodex\t9\n' >"$record"
run_refresh $'› en que estabamos trabajando ?\n• I finished the requested work.\n\n› ' "$process" "$snapshot"
check done "$(cut -f2 "$record")" 'historical user question and completed response transition running to done'
printf '1\tidle\t100\tcodex\t9\n' >"$record"
run_refresh $'› en que estabamos trabajando ?\n• I finished the requested work.\n\n› ' "$process" "$snapshot"
check idle "$(cut -f2 "$record")" 'historical user question and completed response are idle'
run_refresh $'› en que estabamos trabajando ?\nQuestion: Which option should I use?\nYour answer:' "$process" "$snapshot"
check waiting_for_input "$(cut -f2 "$record")" 'genuine question form remains waiting for input'
run_refresh $'assistant: historical output said Working (old • esc to interrupt)\nReady' "$process" "$snapshot"
check idle "$(cut -f2 "$record")" 'historical prose does not become running'
run_refresh 'assistant: • Working (8s • esc to interrupt)' "$process" "$snapshot"
check idle "$(cut -f2 "$record")" 'prefixed working prose does not become running'
run_refresh 'status • Working (8s • esc to interrupt)' "$process" "$snapshot"
check idle "$(cut -f2 "$record")" 'inline working marker does not become running'
run_refresh 'Working (3s • esc to interrupt)' "$process" "$snapshot"
prose="assistant: The text Working (3s • esc to interrupt) is prose"
run_refresh "$prose" "$process" "$snapshot"
check done "$(cut -f2 "$record")" 'running to idle becomes done and prose does not remain running'
run_refresh 'Ready' "$process" "$snapshot"
check done "$(cut -f2 "$record")" 'done survives idle refresh without duplicate transition'

# Codex polls the same screen every five seconds. Repeated accepted refreshes
# must not replay an attention sound, including after the sound cooldown.
CODEX_SOUND_LOG="$TMP/codex-poll-sound.log"
CODEX_SOUND_FILE="$TMP/codex-poll-sound.aiff"
export CODEX_SOUND_LOG
printf 'sound' >"$CODEX_SOUND_FILE"
cat >"$BIN/afplay" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$CODEX_SOUND_LOG"
EOF
chmod +x "$BIN/afplay"
cat >"$TMP/codex-sound.conf" <<EOF
AGENT_STATUS_CONFIG_VERSION=1
AGENT_STATUS_SOUND_ENABLED=1
AGENT_STATUS_SOUND_STATES=(permission)
AGENT_STATUS_SOUND_COOLDOWN=30
AGENT_STATUS_SOUND_BACKEND=afplay
AGENT_STATUS_SOUND_FILE="$CODEX_SOUND_FILE"
EOF
AGENT_STATUS_NOW=200 run_refresh 'Working (3s • esc to interrupt)' "$process" "$snapshot"
REFRESH_CONFIG="$TMP/codex-sound.conf" AGENT_STATUS_NOW=205 run_refresh $'Allow command?\n1. Approve once' "$process" "$snapshot"
REFRESH_CONFIG="$TMP/codex-sound.conf" AGENT_STATUS_NOW=210 run_refresh $'Allow command?\n1. Approve once' "$process" "$snapshot"
REFRESH_CONFIG="$TMP/codex-sound.conf" AGENT_STATUS_NOW=240 run_refresh $'Allow command?\n1. Approve once' "$process" "$snapshot"
check 1 "$(wc -l <"$CODEX_SOUND_LOG" | tr -d ' ')" 'Codex same-state polling emits one attention sound across cooldown'

for stale_source in opencode claude pi; do
  printf '1\tdone\t1\t%s\t90000\n' "$stale_source" >"$record"
  run_refresh 'Working (3s • esc to interrupt)' "$process" "$snapshot"
  check running "$(cut -f2 "$record")" "stale $stale_source pane reuse publishes current Codex state"
  check codex "$(cut -f4 "$record")" "stale $stale_source pane reuse becomes Codex"
done
competing_process="$process"$'\n102 100 /opt/homebrew/bin/opencode opencode'
printf '1\trunning\t100\topencode\t9\n' >"$record"
run_refresh 'Ready' "$competing_process" "$snapshot"
check opencode "$(cut -f4 "$record")" 'verified live producer source precedence is preserved'
printf '1\tidle\t100\tcodex\t9\n' >"$record"
cat >"$TMP/runtime" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AGENT_STATUS_RUNTIME_LOG"
case "$1" in
  publish|clear) printf '{"type":"ack"}\n' ;;
esac
EOF
chmod +x "$TMP/runtime"
export AGENT_STATUS_RUNTIME_PATH="$TMP/runtime" AGENT_STATUS_RUNTIME_LOG="$TMP/runtime.log"
run_refresh 'Ready' '' "$snapshot"
unset AGENT_STATUS_RUNTIME_PATH AGENT_STATUS_RUNTIME_LOG
check 1 "$(test -e "$record"; printf '%s' "$?")" 'Codex cache clears when process leaves pane'
check_contains "clear --root $TMP/cache/agent-status --session alpha --pane _7" "$(cat "$TMP/runtime.log")" 'Codex cleanup uses canonical runtime-aware clear path'

# The asynchronous refresher owns inventory collection and coalesces concurrent scans.
: >"$TMP/ps.log"
PS_LOG="$TMP/ps.log" PS_SLEEP=0.2 SCREEN='Ready' PS_SNAPSHOT="$process" TMUX_LOG="$TMP/tmux.log" PATH="$BIN:$PATH" HOME="$TMP/home" \
  XDG_CACHE_HOME="$TMP/cache" AGENT_STATUS_CONFIG="$TMP/missing" AGENT_STATUS_NOW=100 \
  AGENT_STATUS_PANE_SNAPSHOT="$snapshot" "$ROOT/scripts/codex-status-refresh.sh" &
refresh_pid=$!
for _ in {1..50}; do [[ -s "$TMP/ps.log" ]] && break; sleep 0.01; done
PS_LOG="$TMP/ps.log" PS_SLEEP=0.2 SCREEN='Ready' PS_SNAPSHOT="$process" TMUX_LOG="$TMP/tmux.log" PATH="$BIN:$PATH" HOME="$TMP/home" \
  XDG_CACHE_HOME="$TMP/cache" AGENT_STATUS_CONFIG="$TMP/missing" AGENT_STATUS_NOW=100 \
  AGENT_STATUS_PANE_SNAPSHOT="$snapshot" "$ROOT/scripts/codex-status-refresh.sh"
wait "$refresh_pid"
check 1 "$(wc -l <"$TMP/ps.log" | tr -d ' ')" 'concurrent Codex refreshes share one process scan'

rm -f "$record"
PANE_SNAPSHOT="$snapshot" SCREEN='Ready' PS_SNAPSHOT="$process" TMUX_LOG="$TMP/tmux.log" PATH="$BIN:$PATH" HOME="$TMP/home" \
  XDG_CACHE_HOME="$TMP/cache" AGENT_STATUS_CONFIG="$TMP/missing" AGENT_STATUS_NOW=100 \
  "$ROOT/scripts/codex-status-refresh.sh"
check idle "$(cut -f2 "$record")" 'asynchronous Codex refresh collects its own tmux inventory'

TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" "$ROOT/scripts/tmux-new-session.sh" /tmp/project
check_contains 'new-session -d -s project -c /tmp/project' "$(cat "$TMP/new.log")" 'free basename fast path creates directly'
check_contains 'switch-client -t =project' "$(cat "$TMP/new.log")" 'free basename switches client'

: >"$TMP/new.log"
(cd "$popup_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" "$ROOT/scripts/tmux-internal-session.sh" _scratch)
check_contains "new-session -d -s _scratch -c $popup_path" "$(cat "$TMP/new.log")" 'new floating session inherits popup cwd'
check_contains 'set-option -t _scratch status off' "$(cat "$TMP/new.log")" 'new floating session disables its complete status bar'
check_contains 'set-option -t _scratch detach-on-destroy on' "$(cat "$TMP/new.log")" 'new floating session detaches cleanly on destroy'
check_contains 'attach-session -t _scratch' "$(cat "$TMP/new.log")" 'new floating session attaches after configuration'

: >"$TMP/new.log"
TMUX_LOG="$TMP/new.log" COLLISIONS='_popup' PATH="$BIN:$PATH" "$ROOT/scripts/tmux-internal-session.sh" _popup
[[ "$(cat "$TMP/new.log")" != *'new-session'* ]] || { printf 'FAIL: existing floating session must not be recreated\n' >&2; fail=1; }
check_contains 'set-option -t _popup status off' "$(cat "$TMP/new.log")" 'existing floating session disables its complete status bar before attach'
check_contains 'attach-session -t _popup' "$(cat "$TMP/new.log")" 'existing floating session attaches after configuration'

: >"$TMP/new.log"
TMUX_LOG="$TMP/new.log" PATH="$BIN:$PATH" "$ROOT/scripts/tmux-switch-session.sh" prev /dev/ttys001 beta
check_contains 'switch-client -c /dev/ttys001 -t alpha' "$(cat "$TMP/new.log")" 'previous navigation targets the invoking client from beta to alpha'
check_contains '#{?#{m:_*,#{session_name}},0,1}' "$(cat "$TMP/new.log")" 'navigation excludes internal sessions at the tmux query'

: >"$TMP/new.log"
TMUX_LOG="$TMP/new.log" PATH="$BIN:$PATH" "$ROOT/scripts/tmux-switch-session.sh" next /dev/ttys001 alpha
check_contains 'switch-client -c /dev/ttys001 -t beta' "$(cat "$TMP/new.log")" 'next navigation targets the invoking client from alpha to beta'

: >"$TMP/creator.log"
TMUX_LOG="$TMP/creator.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session.sh" /tmp/project /dev/ttys001 %7 80 24
creator_float_invocation="$(cat "$TMP/creator.log")"

: >"$TMP/new.log"
TMUX_LOG="$TMP/new.log" PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-rename-session.sh" '$7' alpha /dev/ttys001 /tmp/project %9 80 24
rename_float_invocation="$(cat "$TMP/new.log")"

check_contains 'new-pane -P -F #{pane_id} -f -c /tmp/project -x 56 -y 1 -X 12 -Y 11' "$creator_float_invocation" 'creator opens a centered one-line native float'
check_contains 'new-pane -P -F #{pane_id} -f -c /tmp/project -x 56 -y 1 -X 12 -Y 11' "$rename_float_invocation" 'rename matches creator native-float geometry'
check_contains '-s bg=#1d2021,fg=#d4be98 -S fg=#7aa2f7 -R fg=#7aa2f7 -t %7' "$creator_float_invocation" 'creator uses explicit popup colors and borders'
check_contains '-s bg=#1d2021,fg=#d4be98 -S fg=#7aa2f7 -R fg=#7aa2f7 -t %9' "$rename_float_invocation" 'rename matches creator popup colors and borders'
check_contains "$ROOT/scripts/tmux-rename-session-popup.sh \$7 alpha /dev/ttys001" "$rename_float_invocation" 'rename safely transports the invoking session and client context as command arguments'
check_contains 'set-option -p -t %50 @rename_session_picker 1' "$rename_float_invocation" 'rename marks its native floating pane'
check_contains 'select-pane -t %50' "$rename_float_invocation" 'rename selects its native floating pane like creator'
[[ "$rename_float_invocation" != *'display-popup'* ]] || { printf 'FAIL: rename must use the creator native-float path\n' >&2; fail=1; }

: >"$TMP/new.log"; : >"$TMP/popup.out"
printf '\n' | TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-rename-session-popup.sh" '$7' alpha /dev/ttys001 >"$TMP/popup.out" 2>&1
check_contains 'Workspace name:' "$(cat "$TMP/popup.out")" 'rename popup renders the workspace prompt'
check_contains 'alpha' "$(cat "$TMP/popup.out")" 'rename popup pre-fills the current session name'
[[ "$(cat "$TMP/new.log")" != *'rename-session'* ]] || { printf 'FAIL: unchanged rename input must be a no-op\n' >&2; fail=1; }

: >"$TMP/new.log"
printf '\025beta\n' | TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-rename-session-popup.sh" '$7' alpha /dev/ttys001 >"$TMP/popup.out" 2>&1
check_contains 'rename-session -t $7 beta' "$(cat "$TMP/new.log")" 'rename targets the exact invoking session ID'
check_contains 'refresh-client -S -t /dev/ttys001' "$(cat "$TMP/new.log")" 'successful rename refreshes the invoking client'

: >"$TMP/new.log"; : >"$TMP/popup.out"
printf '\025\n\025beta\n' | TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-rename-session-popup.sh" '$7' alpha /dev/ttys001 >"$TMP/popup.out" 2>&1
check_contains 'Name cannot be empty.' "$(cat "$TMP/popup.out")" 'rename reports empty input and allows retry'
check_contains 'resize-pane -y 2' "$(cat "$TMP/new.log")" 'rename expands to creator error height before rendering an error'
check_contains 'rename-session -t $7 beta' "$(cat "$TMP/new.log")" 'rename succeeds after an empty-input retry'

: >"$TMP/new.log"
printf '\033' | TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-rename-session-popup.sh" '$7' alpha /dev/ttys001 >"$TMP/popup.out" 2>&1 || true
[[ "$(cat "$TMP/new.log")" != *'rename-session'* ]] || { printf 'FAIL: Escape must cancel rename without changes\n' >&2; fail=1; }

: >"$TMP/new.log"; : >"$TMP/popup.out"
printf '\025bad.name\n\025beta\n\025gamma\n' | TMUX_LOG="$TMP/new.log" COLLISIONS='beta' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-rename-session-popup.sh" '$7' alpha /dev/ttys001 >"$TMP/popup.out" 2>&1
check_contains 'Use letters, numbers, underscores, or hyphens.' "$(cat "$TMP/popup.out")" 'rename rejects invalid names and allows retry'
check_contains 'Session "beta" already exists.' "$(cat "$TMP/popup.out")" 'rename reports collisions and allows retry'
check_contains 'resize-pane -y 2' "$(cat "$TMP/new.log")" 'rename keeps validation errors in the creator two-line presentation'
check_contains 'rename-session -t $7 gamma' "$(cat "$TMP/new.log")" 'rename succeeds after invalid and colliding retries'

rename_binding="$(grep "^bind '\$'" "$ROOT/editors/tmux/tmux.conf")"
check_contains 'tmux-rename-session.sh #{q:session_id} #{q:session_name} #{q:client_tty} #{q:pane_current_path} #{q:pane_id} #{window_width} #{window_height}' "$rename_binding" 'rename binding captures creator-equivalent context and geometry'
if [[ "$rename_binding" == *'command-prompt'* ]] || grep -Eq 'command-prompt|display-popup|fzf' "$ROOT/scripts/tmux-rename-session"*.sh; then
  printf 'FAIL: rename popup must not fall back to command-prompt, display-popup, or fzf\n' >&2
  fail=1
fi

: >"$TMP/new.log"; : >"$TMP/popup.out"
printf '\025project-3\n' | (cd "$popup_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='project project-2' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh" /dev/ttys001) >"$TMP/popup.out" 2>&1
check_contains "new-session -d -s project-3 -c $popup_path" "$(cat "$TMP/new.log")" 'popup creates validated session'
check_contains 'switch-client -c /dev/ttys001 -t =project-3' "$(cat "$TMP/new.log")" 'popup switches invoking client'
check_contains "Workspace name:" "$(cat "$ROOT/scripts/tmux-new-session-popup.sh")" 'popup renders the workspace prompt'
check_contains '\033[38;5;179mWorkspace name:' "$(cat "$ROOT/scripts/tmux-new-session-popup.sh")" 'workspace prompt uses an accent color'
if grep -Eq 'fzf|read -r -e|compgen' "$ROOT/scripts/tmux-new-session-popup.sh"; then
  printf 'FAIL: workspace popup must not use a completion or selector UI\n' >&2
  fail=1
fi

: >"$TMP/new.log"
special_path="$TMP/path with \"double quotes\" and 'single quotes';\$(touch TMUX_POPUP_INJECTED)"
mkdir -p "$special_path"
printf '\025safe-name\n' | (cd "$special_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh") >"$TMP/popup.out" 2>&1
check_contains "new-session -d -s safe-name -c $special_path" "$(cat "$TMP/new.log")" 'popup derives arbitrary cwd characters from its working directory'
check 1 "$(test -e "$TMP/TMUX_POPUP_INJECTED"; printf '%s' "$?")" 'popup cwd does not execute shell syntax'

: >"$TMP/popup.out"; : >"$TMP/new.log"
printf '\025bad.name\n\025valid-name\n' | (cd "$popup_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh") >"$TMP/popup.out" 2>&1
check_contains 'Use letters, numbers, underscores, or hyphens.' "$(cat "$TMP/popup.out")" 'validation error remains inline'

: >"$TMP/popup.out"; : >"$TMP/new.log"
printf '\025_hidden\n\025visible-name\n' | (cd "$popup_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh") >"$TMP/popup.out" 2>&1
check_contains 'reserved for popups' "$(cat "$TMP/popup.out")" 'workspace popup rejects hidden session names'
check_contains "new-session -d -s visible-name -c $popup_path" "$(cat "$TMP/new.log")" 'workspace creates a visible normal session'
check_contains 'switch-client -t =visible-name' "$(cat "$TMP/new.log")" 'workspace switches to the created normal session'

: >"$TMP/new.log"
printf '' | (cd "$popup_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh") >"$TMP/popup.out" 2>&1 || true
[[ "$(cat "$TMP/new.log")" != *'new-session'* ]] || fail=1

: >"$TMP/new.log"
printf '\033' | (cd "$popup_path" && TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh" /dev/ttys001) >"$TMP/popup.out" 2>&1 || true
[[ "$(cat "$TMP/new.log")" != *'new-session'* && "$(cat "$TMP/new.log")" != *'switch-client'* ]] || {
  printf 'FAIL: Escape must cancel without workspace or client changes\n' >&2
  fail=1
}
check_contains "#{m:_*,#{session_name}}" "$(grep 'bind S' "$ROOT/editors/tmux/tmux.conf")" 'underscore sessions keep detach behavior'
check_contains 'tmux-internal-session.sh --configure #{q:session_name}' "$(grep -A 4 '^set-hook -g session-created' "$ROOT/editors/tmux/tmux.conf")" 'floating session creation hook applies internal options'
check_contains 'set-hook -g client-attached' "$(cat "$ROOT/editors/tmux/tmux.conf")" 'attaching to an existing floating session reapplies internal options'
check_contains 'set-hook -g client-session-changed' "$(cat "$ROOT/editors/tmux/tmux.conf")" 'switching into an existing floating session reapplies internal options'
check_contains 'tmux refresh-client -S -t #{q:hook_client}' "$(grep -A 5 '^set-hook -g client-session-changed' "$ROOT/editors/tmux/tmux.conf")" 'changing sessions refreshes the invoking client status immediately'
check_contains 'set -g status-left "#{E:@workspace-status} "' "$(cat "$ROOT/editors/tmux/tmux.conf")" 'selection rendering is a native tmux option expansion'
check_contains '#(~/.dotfiles/scripts/status-sessions-refresh.sh)#(~/.dotfiles/scripts/codex-status-refresh.sh)' "$(grep '^set -g status-right ' "$ROOT/editors/tmux/tmux.conf")" 'status refresh jobs remain independent from selection rendering'
check_contains "tmux-internal-session.sh --configure-existing" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'config reload repairs existing floating sessions'
check_contains "bind w choose-tree -Zw -f '#{?#{m:_*,#{session_name}},0,1}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native session tree excludes floating sessions'
check_contains "bind D choose-client -Z -f '#{?#{m:_*,#{session_name}},0,1}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native client picker excludes clients in floating sessions'
check_contains "bind '(' run-shell '~/.dotfiles/scripts/tmux-switch-session.sh prev #{q:client_name} #{q:session_name}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native previous-session key targets the invoking client'
check_contains "bind ')' run-shell '~/.dotfiles/scripts/tmux-switch-session.sh next #{q:client_name} #{q:session_name}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native next-session key targets the invoking client'
check_contains "bind-key -n M-Left run-shell '~/.dotfiles/scripts/tmux-switch-session.sh prev #{q:client_name} #{q:session_name}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'Alt+Left targets the invoking client'
check_contains "bind-key -n M-Right run-shell '~/.dotfiles/scripts/tmux-switch-session.sh next #{q:client_name} #{q:session_name}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'Alt+Right targets the invoking client'
popup_binding="$(grep -A 6 '^bind S' "$ROOT/editors/tmux/tmux.conf")"
check_contains "run-shell '~/.dotfiles/scripts/tmux-new-session.sh #{q:pane_current_path} #{q:client_tty} #{q:pane_id} #{window_width} #{window_height}'" "$popup_binding" 'fast path expands shell-quoted path, client, pane, and geometry formats'
[[ "$popup_binding" != *"if-shell '~/.dotfiles/scripts/tmux-new-session.sh"* ]] || { printf 'FAIL: if-shell passes tmux formats literally to the fast path\n' >&2; fail=1; }

((fail == 0)) || exit 1
printf 'tmux Codex and session popup checks passed\n'
