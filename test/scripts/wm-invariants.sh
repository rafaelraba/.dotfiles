#!/usr/bin/env bash
set -euo pipefail

# Lightweight first-party regression check for window-management ownership.
# Validates static invariants without requiring lua/luac.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${DOTFILES_PATH:-$REPO_ROOT}"

fail=0

# Active Hammerspoon bridge patterns:
# - hardcoded /opt/homebrew/bin/hs or any absolute path ending in /hs
# - PATH-based `hs -c ...` (with optional `command` prefix)
# - variable forms $HS / ${HS}, quoted or unquoted
ACTIVE_HS_BRIDGE='(^|[[:space:]:])(command[[:space:]]+)?("(/[^"[:space:]]*/hs|\$[Hh][Ss]|\$\{[Hh][Ss]\}|hs)"|/[^[:space:]]*/hs|\$[Hh][Ss]|\$\{[Hh][Ss]\}|hs)[[:space:]]+-c([[:space:]]|$)'

error() {
  echo "FAIL: $*" >&2
  fail=1
}

grep_file() {
  grep -E "$1" "$2" 2>/dev/null || true
}

grep_dir() {
  grep -R -E "$1" "$2" 2>/dev/null || true
}

# Strip lines that are shell (#) or Lua (--) comments before matching.
grep_file_noncomment() {
  grep -v -E '^[[:space:]]*(#|--)' "$2" 2>/dev/null | grep -E "$1" || true
}

grep_dir_noncomment() {
  grep -R -v -E '^[[:space:]]*(#|--)' "$2" 2>/dev/null | grep -E "$1" || true
}

# Strip full-line comments before matching active bridge calls.
# Suppress harmless deprecation-only echo/printf message lines that happen to
# contain bridge-shaped text, but keep real active commands even if they include
# an inline comment or the word "deprecated".
grep_file_active_bridge() {
  grep -v -Ei '^[[:space:]]*(#|--)' "$2" 2>/dev/null | grep -E "$1" | grep -v -Ei '^[[:space:]]*(echo|printf)\b.*deprecated' || true
}

grep_dir_active_bridge() {
  grep -R -v -Ei '^[[:space:]]*(#|--)' "$2" 2>/dev/null | grep -E "$1" | grep -v -Ei '^[[:space:]]*(echo|printf)\b.*deprecated' || true
}

check_file_active_bridge() {
  local file="$1" pattern="$2" msg="$3"
  local matches
  matches="$(grep_file_active_bridge "$pattern" "$file")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "$msg"
  fi
}

check_dir_active_bridge() {
  local dir="$1" pattern="$2" msg="$3"
  local matches
  matches="$(grep_dir_active_bridge "$pattern" "$dir")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "$msg"
  fi
}

check_file() {
  local file="$1" pattern="$2" msg="$3"
  local matches
  matches="$(grep_file "$pattern" "$file")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "$msg"
  fi
}

check_dir() {
  local dir="$1" pattern="$2" msg="$3"
  local matches
  matches="$(grep_dir "$pattern" "$dir")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "$msg"
  fi
}

check_file_noncomment() {
  local file="$1" pattern="$2" msg="$3"
  local matches
  matches="$(grep_file_noncomment "$pattern" "$file")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "$msg"
  fi
}

check_dir_noncomment() {
  local dir="$1" pattern="$2" msg="$3"
  local matches
  matches="$(grep_dir_noncomment "$pattern" "$dir")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "$msg"
  fi
}

active_bridge_fixture_matches() {
  printf '%s\n' "$1" \
    | grep -v -Ei '^[[:space:]]*(#|--)' \
    | grep -E "$ACTIVE_HS_BRIDGE" \
    | grep -v -Ei '^[[:space:]]*(echo|printf)\b.*deprecated' >/dev/null 2>&1
}

assert_active_bridge_fixture() {
  local fixture="$1" expected="$2" description="$3" actual

  if active_bridge_fixture_matches "$fixture"; then
    actual="match"
  else
    actual="no-match"
  fi

  if [[ "$actual" != "$expected" ]]; then
    error "Active hs -c bridge regex self-test failed for $description: expected $expected, got $actual"
  fi
}

run_active_bridge_regex_self_tests() {
  assert_active_bridge_fixture '"/opt/homebrew/bin/hs" -c foo' match "quoted absolute hs path"
  assert_active_bridge_fixture '"$HS" -c foo' match 'quoted $HS'
  assert_active_bridge_fixture '"${HS}" -c foo' match 'quoted ${HS}'
  assert_active_bridge_fixture '# "$HS" -c foo' no-match "shell comment"
  assert_active_bridge_fixture '-- "$HS" -c foo' no-match "Lua comment"
  assert_active_bridge_fixture 'echo deprecated "$HS" -c foo' no-match "deprecation-only message"
}

# Allowed AeroSpace binding commands: workspace switching, move-node-to-workspace, reload.
check_aerospace_bindings() {
  local file="$1"
  local allowed='^(workspace|move-node-to-workspace|reload-config)$'
  local line action first_token
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    action=$(printf '%s\n' "$line" | sed -E "s/^[^=]+=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/")
    first_token="${action%% *}"
    if [[ ! "$first_token" =~ $allowed ]]; then
      echo "DISALLOWED BINDING: $line" >&2
      error "AeroSpace binding uses disallowed command '$first_token' (allowed: workspace, move-node-to-workspace, reload-config)"
    fi
  done < <(awk '/^\[mode\..*\.binding\]/{s=1; next} /^\[/{s=0} s && !/^[[:space:]]*#/ && !/^[[:space:]]*$/' "$file")
}

check_hammerspoon_aerospace_usage() {
  local dir="$1"
  local matches disallowed
  matches="$(grep -R --include='*.lua' -v -E '^[[:space:]]*(#|--)' "$dir" 2>/dev/null | grep -E 'aerospace|aerospaceCli' || true)"
  if [[ -z "$matches" ]]; then
    return
  fi

  disallowed="$(printf '%s\n' "$matches" | grep -v -E 'list-workspaces --focused|layout --window-id .* floating|aerospaceCli|aerospace CLI|AEROSPACE_BIN|/aerospace|["'"'"']aerospace["'"'"']' || true)"
  if [[ -n "$disallowed" ]]; then
    echo "$disallowed" >&2
    error "Hammerspoon may only query the focused AeroSpace workspace or float target windows before applying layouts"
  fi
}

run_active_bridge_regex_self_tests

echo "Checking window-management ownership invariants under $ROOT ..."

# 1. AeroSpace config owns only workspace switching, move-node-to-workspace, reload.
aerospace_config="$ROOT/wm/aerospace/aerospace.toml"
if [[ -f "$aerospace_config" ]]; then
  check_file "$aerospace_config" 'hammerspoon|/opt/homebrew/bin/hs|\bhs\s' \
    "AeroSpace config must not call Hammerspoon"
  check_file "$aerospace_config" 'exec-on-workspace-change|workspace-change|on-workspace-change|sync' \
    "AeroSpace config must not use workspace-change sync hooks"
  check_file "$aerospace_config" 'cmd[-_]?alt[-_]?d|cmd[-_]?option[-_]?d' \
    "AeroSpace config must not bind Cmd+Option+D"
  check_file_noncomment "$aerospace_config" 'exec-and-forget' \
    "AeroSpace config must not use exec-and-forget bridge calls"
  check_aerospace_bindings "$aerospace_config"
fi

# 2. No active Hammerspoon bridge calls in scripts.
if [[ -d "$ROOT/scripts" ]]; then
  check_dir_active_bridge "$ROOT/scripts" "$ACTIVE_HS_BRIDGE" \
    "Scripts must not contain active Hammerspoon bridge calls"
fi

# 3. No Cmd+Option+D / cmd-alt-d binding for window management anywhere.
for scope in "$ROOT/wm" "$ROOT/scripts" "$ROOT/editors/hammerspoon"; do
  if [[ -d "$scope" ]]; then
    check_dir_noncomment "$scope" 'cmd[-_]?alt[-_]?d|cmd[-_]?option[-_]?d' \
      "Cmd+Option+D binding found in $scope"
  fi
done

# 4. Hammerspoon hotkeys do not use invalid key names minus/equals/slash.
hotkeys="$ROOT/editors/hammerspoon/modules/hotkeys.lua"
if [[ -f "$hotkeys" ]]; then
  check_file "$hotkeys" '["'\''"](minus|equals|slash)["'\''"]' \
    "Hammerspoon hotkeys must not use invalid key names minus/equals/slash"
fi

# 5. Hammerspoon may query AeroSpace from its own polling loop and may float
# target windows before frame-based manual layouts. It must not become an
# AeroSpace callback bridge or general-purpose AeroSpace scripting layer.
if [[ -d "$ROOT/editors/hammerspoon" ]]; then
  check_hammerspoon_aerospace_usage "$ROOT/editors/hammerspoon"
fi

# 6. Hammerspoon owns centering the focused window through Cmd+Alt+M.
if [[ -f "$hotkeys" ]]; then
  if ! grep -Eq 'hs\.hotkey\.bind\(hyper,[[:space:]]*["'"'"']m["'"'"']' "$hotkeys"; then
    error "Hammerspoon must bind Cmd+Alt+M to center the focused window"
  fi

  if ! grep -Eq 'centerFocusedWindow' "$hotkeys"; then
    error "Cmd+Alt+M binding must call centerFocusedWindow"
  fi

  if ! grep -Eq "hs\.hotkey\.bind\(shiftHyper,[[:space:]]*['\"]m['\"]" "$hotkeys"; then
    error "Hammerspoon must bind Cmd+Alt+Shift+M to center-main layout"
  fi

  if ! grep -Eq 'saveCurrentWorkspaceLayout\("center-main"' "$hotkeys"; then
    error "Cmd+Alt+Shift+M binding must save center-main for workspace restore"
  fi
fi

# 7. Deprecated bridge scripts are non-operative (marked deprecated, no active calls).
deprecated_scripts=(
  "$ROOT/scripts/wm/lib/aerospace-windows.sh"
  "$ROOT/scripts/aerospace-columns-layout.sh"
  "$ROOT/scripts/aerospace-stack-right-layout.sh"
  "$ROOT/scripts/wm/layout-columns.sh"
  "$ROOT/scripts/wm/layout-stack-right.sh"
  "$ROOT/scripts/legacy/aerospace-dev-layout.sh"
)

for script in "${deprecated_scripts[@]}"; do
  if [[ -f "$script" ]]; then
    if ! grep -Eiq 'DEPRECATED|deprecated' "$script"; then
      error "$script is not marked deprecated"
    fi

    script_matches="$(grep_file_active_bridge "$ACTIVE_HS_BRIDGE|aerospace[[:space:]]+(layout|stack|columns)|(^|[[:space:]])hs\." "$script")"
    if [[ -n "$script_matches" ]]; then
      echo "$script_matches" >&2
      error "$script appears to contain active bridge code"
    fi
  else
    error "Deprecated script missing: $script"
  fi
done

if [[ "$fail" -eq 0 ]]; then
  echo "All window-management invariants passed."
  exit 0
else
  echo "Window-management invariant checks failed." >&2
  exit 1
fi
