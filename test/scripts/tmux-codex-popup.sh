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
  display-message)
    if [[ "$*" == *"-t ${TMUX_PANE:-} #S"* ]]; then
      printf '%s\n' "${CURRENT_SESSION:-alpha}"
    else
      printf 'alpha\n'
    fi
    ;;
  capture-pane) printf '%s\n' "${SCREEN:-}" ;;
esac
EOF
cat >"$BIN/ps" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${PS_SNAPSHOT:-}"
EOF
cat >"$BIN/fzf" <<'EOF'
#!/usr/bin/env bash
count=0; [[ -f "$FZF_COUNT" ]] && read -r count <"$FZF_COUNT"
count=$((count + 1)); printf '%s\n' "$count" >"$FZF_COUNT"
eval "response=\${FZF_RESPONSE_$count-}"; eval "status=\${FZF_STATUS_$count-0}"
printf '%s\n' "$*" >>"$FZF_LOG"
printf 'stdin-bytes=%s\n' "$(wc -c </dev/stdin | tr -d ' ')" >>"$FZF_LOG"
[[ "$status" == 0 ]] || exit "$status"
printf '%s\n' "$response"
EOF
chmod +x "$BIN/tmux" "$BIN/ps" "$BIN/fzf"

run_refresh() {
  local screen="$1" process="$2" snapshot="$3"
  SCREEN="$screen" PS_SNAPSHOT="$process" TMUX_LOG="$TMP/tmux.log" PATH="$BIN:$PATH" HOME="$TMP/home" \
    XDG_CACHE_HOME="$TMP/cache" AGENT_STATUS_CONFIG="$TMP/missing" AGENT_STATUS_NOW="${AGENT_STATUS_NOW:-100}" \
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
run_refresh 'Ready' '' "$snapshot"
check 1 "$(test -e "$record"; printf '%s' "$?")" 'Codex cache clears when process leaves pane'

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
TMUX_PANE='%2' CURRENT_SESSION=beta TMUX_LOG="$TMP/new.log" PATH="$BIN:$PATH" "$ROOT/scripts/tmux-switch-session.sh" prev
check_contains 'display-message -p -t %2 #S' "$(cat "$TMP/new.log")" 'previous navigation resolves the invoking pane session'
check_contains 'switch-client -t alpha' "$(cat "$TMP/new.log")" 'previous navigation returns from beta to alpha'
check_contains '#{?#{m:_*,#{session_name}},0,1}' "$(cat "$TMP/new.log")" 'navigation excludes internal sessions at the tmux query'

: >"$TMP/new.log"
TMUX_PANE='%1' CURRENT_SESSION=alpha TMUX_LOG="$TMP/new.log" PATH="$BIN:$PATH" "$ROOT/scripts/tmux-switch-session.sh" next
check_contains 'switch-client -t beta' "$(cat "$TMP/new.log")" 'next navigation advances from alpha to beta'

: >"$TMP/new.log"; : >"$TMP/fzf.count"
(cd "$popup_path" && FZF_COUNT="$TMP/fzf.count" FZF_LOG="$TMP/fzf.log" \
  FZF_RESPONSE_1='project-3' TMUX_LOG="$TMP/new.log" COLLISIONS='project project-2' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh")
check_contains '--query=project-3' "$(cat "$TMP/fzf.log")" 'collision popup pre-fills first free suffix'
check_contains 'stdin-bytes=1' "$(cat "$TMP/fzf.log")" 'popup feeds fzf exactly one empty candidate'
check_contains '--disabled' "$(cat "$TMP/fzf.log")" 'popup keeps its inert candidate selectable while typing'
check_contains "new-session -d -s project-3 -c $popup_path" "$(cat "$TMP/new.log")" 'popup creates validated session'
check_contains 'switch-client -t =project-3' "$(cat "$TMP/new.log")" 'popup switches invoking client'

: >"$TMP/new.log"
TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" "$ROOT/scripts/tmux-new-session.sh" /tmp/project /dev/ttys001
check_contains 'display-popup -t /dev/ttys001 -d /tmp/project -w 54 -h 4 -b rounded' "$(cat "$TMP/new.log")" 'collision fast path opens a compact rounded workspace popup for the invoking client'
check_contains '-S fg=#504945' "$(cat "$TMP/new.log")" 'workspace popup uses a subtle gray border'
[[ "$(cat "$TMP/new.log")" != *' -T '* ]] || fail=1
[[ "$(cat "$TMP/new.log")" != *'new-session -d'* ]] || fail=1

: >"$TMP/fzf.count"; : >"$TMP/new.log"
special_path="$TMP/path with \"double quotes\" and 'single quotes';\$(touch TMUX_POPUP_INJECTED)"
mkdir -p "$special_path"
(cd "$special_path" && FZF_COUNT="$TMP/fzf.count" FZF_LOG="$TMP/fzf.log" \
  FZF_RESPONSE_1='safe-name' TMUX_LOG="$TMP/new.log" COLLISIONS='' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh")
check_contains "new-session -d -s safe-name -c $special_path" "$(cat "$TMP/new.log")" 'popup derives arbitrary cwd characters from its working directory'
check 1 "$(test -e "$TMP/TMUX_POPUP_INJECTED"; printf '%s' "$?")" 'popup cwd does not execute shell syntax'

: >"$TMP/fzf.count"; : >"$TMP/fzf.log"; : >"$TMP/new.log"
(cd "$popup_path" && FZF_COUNT="$TMP/fzf.count" FZF_LOG="$TMP/fzf.log" \
  FZF_RESPONSE_1='bad.name' FZF_RESPONSE_2='valid-name' TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh")
check 2 "$(cat "$TMP/fzf.count")" 'invalid name keeps popup loop open'
check_contains 'Use letters, numbers, underscores, or hyphens.' "$(cat "$TMP/fzf.log")" 'validation error remains inline'

: >"$TMP/fzf.count"; : >"$TMP/fzf.log"; : >"$TMP/new.log"
(cd "$popup_path" && FZF_COUNT="$TMP/fzf.count" FZF_LOG="$TMP/fzf.log" \
  FZF_RESPONSE_1='_hidden' FZF_RESPONSE_2='visible-name' TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh")
check 2 "$(cat "$TMP/fzf.count")" 'reserved popup name keeps the workspace dialog open'
check_contains 'reserved for popups' "$(cat "$TMP/fzf.log")" 'workspace popup rejects hidden session names'
check_contains "new-session -d -s visible-name -c $popup_path" "$(cat "$TMP/new.log")" 'workspace creates a visible normal session'
check_contains 'switch-client -t =visible-name' "$(cat "$TMP/new.log")" 'workspace switches to the created normal session'

: >"$TMP/fzf.count"; : >"$TMP/new.log"
(cd "$popup_path" && FZF_COUNT="$TMP/fzf.count" FZF_LOG="$TMP/fzf.log" \
  FZF_STATUS_1=130 TMUX_LOG="$TMP/new.log" COLLISIONS='project' PATH="$BIN:$PATH" \
  "$ROOT/scripts/tmux-new-session-popup.sh")
[[ "$(cat "$TMP/new.log")" != *'new-session'* ]] || fail=1
check_contains "#{m:_*,#{session_name}}" "$(grep 'bind S' "$ROOT/editors/tmux/tmux.conf")" 'underscore sessions keep detach behavior'
check_contains 'tmux-internal-session.sh --configure #{q:session_name}' "$(grep -A 4 '^set-hook -g session-created' "$ROOT/editors/tmux/tmux.conf")" 'floating session creation hook applies internal options'
check_contains 'set-hook -g client-attached' "$(cat "$ROOT/editors/tmux/tmux.conf")" 'attaching to an existing floating session reapplies internal options'
check_contains 'set-hook -g client-session-changed' "$(cat "$ROOT/editors/tmux/tmux.conf")" 'switching into an existing floating session reapplies internal options'
check_contains "tmux-internal-session.sh --configure-existing" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'config reload repairs existing floating sessions'
check_contains "bind w choose-tree -Zw -f '#{?#{m:_*,#{session_name}},0,1}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native session tree excludes floating sessions'
check_contains "bind D choose-client -Z -f '#{?#{m:_*,#{session_name}},0,1}'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native client picker excludes clients in floating sessions'
check_contains "bind '(' run-shell '~/.dotfiles/scripts/tmux-switch-session.sh prev'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native previous-session key uses filtered navigation'
check_contains "bind ')' run-shell '~/.dotfiles/scripts/tmux-switch-session.sh next'" "$(cat "$ROOT/editors/tmux/tmux.conf")" 'native next-session key uses filtered navigation'
popup_binding="$(grep -A 6 '^bind S' "$ROOT/editors/tmux/tmux.conf")"
check_contains "run-shell '~/.dotfiles/scripts/tmux-new-session.sh #{q:pane_current_path} #{q:client_tty}'" "$popup_binding" 'fast path expands shell-quoted path and client formats'
[[ "$popup_binding" != *"if-shell '~/.dotfiles/scripts/tmux-new-session.sh"* ]] || { printf 'FAIL: if-shell passes tmux formats literally to the fast path\n' >&2; fail=1; }

((fail == 0)) || exit 1
printf 'tmux Codex and session popup checks passed\n'
