#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE="$ROOT/scripts/agent-status-runtime"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/agent-status-runtime"
fail=0

check() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$label" "$expected" "$actual" >&2
    fail=1
  fi
}

contains() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != *"$expected"* ]]; then
    printf 'FAIL: %s (expected %s in %s)\n' "$label" "$expected" "$actual" >&2
    fail=1
  fi
}

run() {
  set +e
  "$@" >"$TMP/stdout" 2>"$TMP/stderr"
  status=$?
  set -e
}

source_state() {
  find "$1" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
  if [[ "$(uname)" == Darwin ]]; then
    find "$1" -type f -exec stat -f '%p:%m:%z:%N' {} \; | LC_ALL=C sort
  else
    find "$1" -type f -exec stat -c '%a:%Y:%s:%n' {} \; | LC_ALL=C sort
  fi
}

render_runtime_tab() {
  local runtime_path="$1" enabled="${AGENT_STATUS_RUNTIME_ENABLED:-1}"
  export RUNTIME_ARG_LOG
  AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_STATE_DIR="$TMP/render-state" AGENT_STATUS_NOW=100 AGENT_STATUS_NO_COLOR=1 \
    AGENT_STATUS_RUNTIME_ENABLED="$enabled" AGENT_STATUS_RUNTIME_PATH="$runtime_path" PATH="$TMP/render-bin:$PATH" \
    "$ROOT/scripts/status-sessions.sh" oldest
}

write_runtime() {
  local path="$1" body="$2"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$path"
}

mkdir -p "$TMP/state/panes" "$TMP/state/sessions"
printf '1\trunning\t100\topencode\t1\n' >"$TMP/state/panes/work__1"
printf 'done\n' >"$TMP/state/sessions/legacy"

# This must fail before the CLI command exists.
(cd "$MODULE" && go build -o "$BIN" ./cmd/agent-status-runtime)

before="$(source_state "$TMP/state")"
run "$BIN" snapshot --root "$TMP/state" --now 100
check 0 "$status" 'snapshot complete exit'
contains '"state":"running"' "$(<"$TMP/stdout")" 'snapshot emits valid pane'
check "$before" "$(source_state "$TMP/state")" 'snapshot does not write source state'

for n in $(seq 1 21); do
  printf 'corrupt\n' >"$TMP/state/panes/bad-$n"
done
before="$(source_state "$TMP/state")"
run "$BIN" snapshot --root "$TMP/state" --now 100
check 2 "$status" 'snapshot partial exit'
check 20 "$(grep -c '"code":"record_malformed"' "$TMP/stderr" || true)" 'diagnostics are capped at twenty'
while IFS= read -r diagnostic; do
  [[ ${#diagnostic} -le 256 ]] || { printf 'FAIL: diagnostic exceeds 256 bytes\n' >&2; fail=1; }
done <"$TMP/stderr"
check "$before" "$(source_state "$TMP/state")" 'partial snapshot does not write source state'
run "$BIN" validate --root "$TMP/state" --now 100
check 2 "$status" 'validate partial exit'

rm -f "$TMP/state/panes"/bad-*
run "$BIN" validate --root "$TMP/state" --now 100
check 0 "$status" 'validate complete exit'
run "$BIN" snapshot --root "$TMP/state" --schema-version 1
check 1 "$status" 'snapshot invalid configuration exit'
run "$BIN" doctor --root "$TMP/state" --now 100
check 0 "$status" 'doctor passes required checks'
contains $'protocol\trequired\tok' "$(<"$TMP/stdout")" 'doctor reports protocol check'
contains $'adapter\toptional\tunavailable' "$(<"$TMP/stdout")" 'doctor reports optional adapter degradation'

printf 'corrupt\n' >"$TMP/state/panes/bad"
run "$BIN" doctor --root "$TMP/state" --now 100
check 1 "$status" 'doctor malformed input fails required checks'
contains '"code":"record_malformed"' "$(<"$TMP/stderr")" 'doctor uses bounded diagnostic contract'
run "$BIN" doctor --root "$TMP/missing" --now 100
check 1 "$status" 'doctor missing paths fail required checks'

if [[ "${1:-core}" == "integration" ]]; then
  default_runtime_enabled="$(AGENT_STATUS_CONFIG="$TMP/missing.conf" bash -c 'source "$1"; agent_status_load_config; printf %s "$AGENT_STATUS_RUNTIME_ENABLED"' _ "$ROOT/scripts/agent-status/config.sh")"
  check 0 "$default_runtime_enabled" 'runtime is disabled by default'
  rm -f "$TMP/state/panes/bad"
  printf '1\terror\t100\topencode\t2\n' >"$TMP/state/panes/work__9"
  runtime_dir="$(mktemp -d /tmp/as-runtime.XXXXXX)"
  trap 'kill "$serve_pid" 2>/dev/null || true; wait "$serve_pid" 2>/dev/null || true; rm -rf "$TMP" "$runtime_dir"' EXIT
  env XDG_RUNTIME_DIR="$runtime_dir" "$BIN" serve --root "$TMP/state" --now 100 >"$TMP/serve.stdout" 2>"$TMP/serve.stderr" &
  serve_pid=$!
  for _ in $(seq 1 100); do
    [[ -S "$runtime_dir/agent-status/agent-status.sock" ]] && break
    sleep 0.01
  done
  run env XDG_RUNTIME_DIR="$runtime_dir" "$BIN" socket-snapshot --root "$TMP/state"
  check 0 "$status" 'socket snapshot exits successfully'
  contains '"type":"snapshot"' "$(<"$TMP/stdout")" 'socket snapshot returns daemon response'
  run env AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_STATE_DIR="$TMP/state" AGENT_STATUS_NOW=100 \
    AGENT_STATUS_RUNTIME_ENABLED=1 AGENT_STATUS_RUNTIME_PATH="$BIN" XDG_RUNTIME_DIR="$runtime_dir" \
    AGENT_STATUS_PANE_SNAPSHOT=$'work\t0\tmain\t%1\tbash\tmain\t/tmp\tbash\t1' \
    "$ROOT/scripts/agent-status.sh" runtime-snapshot
  check 0 "$status" 'public runtime snapshot exits successfully'
  runtime_snapshot_output="$(<"$TMP/stdout")"
  if [[ "$runtime_snapshot_output" == *'__agent_status_daemon__'* ]]; then
    printf 'FAIL: public runtime snapshot leaked daemon sentinel\n' >&2
    fail=1
  fi
  run python3 - "$runtime_snapshot_output" <<'PY'
import json
import sys

snapshot = json.loads(sys.argv[1])
panes = [pane for pane in snapshot.get("panes", []) if pane.get("session") == "work" and pane.get("pane") == "_1"]
if len(panes) != 1 or len(snapshot.get("panes", [])) != 1:
    raise ValueError("expected one synthetic work pane")
pane = panes[0]
sessions = snapshot.get("sessions", [])
if len(sessions) != 1 or sessions[0].get("name") != "work":
    raise ValueError("expected one synthetic work session")
print(f'{pane.get("state")}\t{sessions[0].get("state")}\t{str(bool(snapshot.get("epoch"))).lower()}\t{str(bool(pane.get("token"))).lower()}')
PY
  check 0 "$status" 'public runtime snapshot emits exactly one valid JSON document'
  check $'running\trunning\ttrue\ttrue' "$(<"$TMP/stdout")" 'public runtime snapshot ignores historical errors and preserves daemon provenance'
  run env XDG_RUNTIME_DIR="$runtime_dir" "$BIN" publish --root "$TMP/state" --session oldest --pane _7 --source harness --state error --producer-revision 2
  check 0 "$status" 'socket publish exits successfully'
  contains '"type":"ack"' "$(<"$TMP/stdout")" 'socket publish returns acknowledgement'
  kill -TERM "$serve_pid" 2>/dev/null || true
  wait "$serve_pid" 2>/dev/null || true

  run env XDG_RUNTIME_DIR="$runtime_dir" "$BIN" doctor --root "$TMP/state" --now 100
  check 0 "$status" 'disabled runtime doctor keeps v1 checks available'
  contains $'runtime\toptional\tunavailable' "$(<"$TMP/stdout")" 'disabled runtime is reported as optional'
  mkdir -p "$runtime_dir/agent-status"
  chmod 755 "$runtime_dir/agent-status"
  run env AGENT_STATUS_RUNTIME_ENABLED=1 XDG_RUNTIME_DIR="$runtime_dir" "$BIN" doctor --root "$TMP/state" --now 100
  check 1 "$status" 'doctor rejects unsafe runtime socket directory'
  contains $'runtime\trequired\tfail' "$(<"$TMP/stdout")" 'unsafe runtime endpoint fails required doctor check'

  mkdir -p "$TMP/render-state/panes" "$TMP/render-state/sessions" "$TMP/render-bin"
  printf '1\tdone\t100\tadapter\t1\n' >"$TMP/render-state/panes/oldest__7"
  cat >"$TMP/render-bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) printf 'oldest\t0\tmain\t%%7\tbash\tmain\t/tmp\tbash\t1\n' ;;
  list-sessions) printf '10\t$1\toldest\n' ;;
esac
EOF
  chmod +x "$TMP/render-bin/tmux"
  baseline="$(AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_STATE_DIR="$TMP/render-state" AGENT_STATUS_NOW=100 AGENT_STATUS_NO_COLOR=1 PATH="$TMP/render-bin:$PATH" "$ROOT/scripts/status-sessions.sh" oldest)"
  check ' [· oldest 1]  ' "$baseline" 'v1 reports idle before runtime preference'

  runtime_path="$TMP/runtime dir/runtime;\$(touch $TMP/pwn)"
  write_runtime "$runtime_path" 'if [[ "$1" == publish ]]; then printf '\''{"type":"ack"}\n'\''; exit 0; fi; printf "%s\n" "$#:$1" >>"$RUNTIME_ARG_LOG"; printf '\''{"schema_version":2,"epoch":"v1","revision":0,"panes":[{"session":"oldest","pane":"_7","state":"idle"}],"sessions":[{"name":"oldest","state":"idle"}]}\n'\'''
  runtime_output="$(RUNTIME_ARG_LOG="$TMP/runtime-args" render_runtime_tab "$runtime_path")"
  check "$baseline" "$runtime_output" 'compatible runtime preserves v1 tab output'
  check $'5:socket-snapshot\n5:snapshot' "$(<"$TMP/runtime-args")" 'daemon probe falls back to CLI as one argv without evaluation'
  if test -e "$TMP/pwn"; then
    pwn_status=0
  else
    pwn_status=1
  fi
  check 1 "$pwn_status" 'runtime path metacharacters remain inert'

  differing_runtime="$TMP/differing-runtime"
  write_runtime "$differing_runtime" 'sleep 0.3; printf '\''{"schema_version":2,"epoch":"v1","revision":0,"panes":[{"session":"oldest","pane":"_7","state":"error"}],"sessions":[{"name":"oldest","state":"error"}]}\n'\'''
  differing_output="$(render_runtime_tab "$differing_runtime")"
  check ' [! oldest 1]  ' "$differing_output" 'compatible runtime error overrides idle v1 state'

  disabled_output="$(AGENT_STATUS_RUNTIME_ENABLED=0 RUNTIME_ARG_LOG="$TMP/disabled-args" render_runtime_tab "$runtime_path")"
  check "$baseline" "$disabled_output" 'disabled runtime preserves v1 output parity'
  if test -e "$TMP/disabled-args"; then
    disabled_status=0
  else
    disabled_status=1
  fi
  check 1 "$disabled_status" 'disabled runtime skips the probe'

  dirty_render_runtime="$TMP/dirty-render-runtime"
  write_runtime "$dirty_render_runtime" 'printf "%s\n" "$1" >>"$RUNTIME_ARG_LOG"; [[ "$1" == socket-snapshot ]] && exit 7; printf '\''{"schema_version":2,"epoch":"v1","revision":0,"panes":[{"session":"oldest","pane":"_7","state":"idle"}],"sessions":[{"name":"oldest","state":"idle"}]}\n'\'''
  mkdir -p "$TMP/render-state/.runtime-dirty"
  printf '1\n' >"$TMP/render-state/.runtime-dirty/oldest__7"
  dirty_output="$(RUNTIME_ARG_LOG="$TMP/dirty-render-args" render_runtime_tab "$dirty_render_runtime")"
  check "$baseline" "$dirty_output" 'dirty marker preserves CLI then v1 render fallback'
  check $'publish\nsnapshot' "$(<"$TMP/dirty-render-args")" 'dirty marker skips daemon probe and invokes CLI snapshot'
  rm -rf "$TMP/render-state/.runtime-dirty"

  malformed_historical_runtime="$TMP/malformed-historical-runtime"
  write_runtime "$malformed_historical_runtime" 'if [[ "$1" == publish ]]; then printf '\''{"type":"ack"}\n'\''; exit 0; fi; printf "%s\n" "$1" >>"$RUNTIME_ARG_LOG"; if [[ "$1" == socket-snapshot ]]; then printf '\''{"type":"snapshot","snapshot":{"schema_version":2,"epoch":"v1","revision":0,"panes":[{"session":"missing","pane":"_99","state":"invalid"}],"sessions":[]}}\n'\''; else printf '\''{"schema_version":2,"epoch":"v1","revision":0,"panes":[{"session":"oldest","pane":"_7","state":"idle"}],"sessions":[{"name":"oldest","state":"idle"}]}\n'\''; fi'
  malformed_historical_output="$(RUNTIME_ARG_LOG="$TMP/malformed-historical-args" render_runtime_tab "$malformed_historical_runtime")"
  check "$baseline" "$malformed_historical_output" 'malformed historical daemon pane falls through to CLI then v1'
  check $'socket-snapshot\nsnapshot' "$(<"$TMP/malformed-historical-args")" 'malformed historical daemon pane invokes CLI after daemon rejection'

  dirty_runtime="$TMP/dirty-runtime"
  write_runtime "$dirty_runtime" '[[ "$1" == publish ]] && exit 1; exit 1'
  AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_STATE_DIR="$TMP/dirty-state" AGENT_STATUS_RUNTIME_ENABLED=1 AGENT_STATUS_RUNTIME_PATH="$dirty_runtime" \
    "$ROOT/scripts/agent-status.sh" set error work _1 harness 9
  check 1 "$(find "$TMP/dirty-state/.runtime-dirty" -type f -print -quit | wc -l | tr -d ' ')" 'failed publish retains dirty marker'
  write_runtime "$dirty_runtime" '[[ "$1" == publish ]] && printf "{\"type\":\"ack\"}\n"'
  AGENT_STATUS_CONFIG="$TMP/missing.conf" AGENT_STATUS_STATE_DIR="$TMP/dirty-state" AGENT_STATUS_RUNTIME_ENABLED=1 AGENT_STATUS_RUNTIME_PATH="$dirty_runtime" \
    "$ROOT/scripts/agent-status.sh" set done work _1 harness 10
  check 0 "$(find "$TMP/dirty-state/.runtime-dirty" -type f -print -quit | wc -l | tr -d ' ')" 'matching publish acknowledgement clears dirty marker'

  for failure in relative timeout crash oversized malformed schema inventory; do
    case "$failure" in
      relative) failure_path='relative-runtime' ;;
      timeout) failure_path="$TMP/$failure-runtime"; write_runtime "$failure_path" 'sleep 2' ;;
      crash) failure_path="$TMP/$failure-runtime"; write_runtime "$failure_path" 'exit 7' ;;
      oversized) failure_path="$TMP/$failure-runtime"; write_runtime "$failure_path" 'head -c 70000 /dev/zero | tr "\\0" x' ;;
      malformed) failure_path="$TMP/$failure-runtime"; write_runtime "$failure_path" 'printf "not-json\n"' ;;
      schema) failure_path="$TMP/$failure-runtime"; write_runtime "$failure_path" 'printf '\''{"schema_version":1}\n'\''' ;;
      inventory) failure_path="$TMP/$failure-runtime"; write_runtime "$failure_path" 'printf '\''{"schema_version":2,"epoch":"v1","revision":0,"panes":[{"session":"missing","pane":"_99","state":"done"}],"sessions":[]}\n'\''' ;;
    esac
    fallback_output="$(render_runtime_tab "$failure_path")"
    check "$baseline" "$fallback_output" "$failure runtime failure preserves v1 parity"
  done

  mkdir -p "$TMP/build-bin"
  cat >"$TMP/build-bin/go" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GO_BUILD_LOG"
[[ "${GO_BUILD_FAIL:-0}" != 1 ]] || exit 1
while [[ "$1" != "-o" ]]; do shift; done
touch "$2"
chmod +x "$2"
EOF
  chmod +x "$TMP/build-bin/go"
  runtime_build="$TMP/restored runtime"
  GO_BUILD_LOG="$TMP/go-build.log" AGENT_STATUS_RUNTIME_BUILD_PATH="$runtime_build" PATH="$TMP/build-bin:$PATH" "$ROOT/restoration_scripts/01-verify-install.sh" >/dev/null
  if test -x "$runtime_build"; then
    build_status=0
  else
    build_status=1
  fi
  check 0 "$build_status" 'restoration builds runtime when Go exists'
  contains "build -o $runtime_build ./cmd/agent-status-runtime" "$(cat "$TMP/go-build.log")" 'restoration source build uses the runtime command package'
  rm -f "$runtime_build"
  GO_BUILD_FAIL=1 GO_BUILD_LOG="$TMP/go-build-failed.log" AGENT_STATUS_RUNTIME_BUILD_PATH="$runtime_build" PATH="$TMP/build-bin:$PATH" "$ROOT/restoration_scripts/01-verify-install.sh" >/dev/null
  check 1 "$(test -e "$runtime_build"; printf '%s' "$?")" 'restoration source build failure remains non-fatal'
fi

if ((fail)); then
  exit 1
fi
printf 'agent-status runtime %s checks passed\n' "${1:-core}"
