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

if ((fail)); then
  exit 1
fi
printf 'agent-status runtime core checks passed\n'
