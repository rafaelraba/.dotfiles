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

check_no_active_aerospace_runtime_usage() {
  local dir="$1"
  local matches
  matches="$(grep -R -v -E '^[[:space:]]*(#|--)' "$dir" 2>/dev/null | grep -Ei 'aerospace|aerospaceCli|AEROSPACE_' || true)"
  if [[ -z "$matches" ]]; then
    return
  fi

  echo "$matches" >&2
  error "Runtime files must not reference or call AeroSpace"
}

check_hammerspoon_sketchybar_toggle_binding() {
  local file="$1"
  local line binding_block="" in_binding=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ hs\.hotkey\.bind\(shiftHyper,[[:space:]]*[\"\']b[\"\'] ]]; then
      in_binding=1
    fi

    if [[ "$in_binding" -eq 1 ]]; then
      binding_block+="$line"$'\n'
      if [[ "$line" =~ ^[[:space:]]*end\) ]]; then
        break
      fi
    fi
  done < "$file"

  if [[ -z "$binding_block" ]]; then
    error "Hammerspoon must bind Cmd+Alt+Shift+B"
    return
  fi

  if ! printf '%s\n' "$binding_block" | grep -Eq 'runScript\(.*scripts/wm/toggle-sketchybar\.sh'; then
    error "Cmd+Alt+Shift+B must run scripts/wm/toggle-sketchybar.sh from Hammerspoon"
  fi
}

check_hammerspoon_layout_binding() {
  local file="$1" modifiers="$2" key="$3" callback_name="$4" label="$5"
  local line binding_block="" in_binding=0 modifier_pattern

  if [[ "$modifiers" == "hyper" ]]; then
    modifier_pattern='hyper'
  else
    modifier_pattern='shiftHyper'
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ hs\.hotkey\.bind\($modifier_pattern,[[:space:]]*[\"\']$key[\"\'] ]]; then
      in_binding=1
    fi

    if [[ "$in_binding" -eq 1 ]]; then
      binding_block+="$line"$'\n'
      if [[ "$line" =~ ^[[:space:]]*end\) ]]; then
        break
      fi
    fi
  done < "$file"

  if [[ -z "$binding_block" ]]; then
    error "Hammerspoon must bind $label"
    return
  fi

  if ! printf '%s\n' "$binding_block" | grep -Eq "$callback_name"; then
    error "$label binding must call $callback_name"
  fi

  if printf '%s\n' "$binding_block" | grep -Eq 'saveCurrentWorkspaceLayout|workspaceLayoutRestore'; then
    error "$label binding must not save per-workspace restore state"
  fi
}

check_hammerspoon_native_desktop_bindings() {
  local file="$1"

  if ! grep -Eq 'desktopKeys[[:space:]]*=[[:space:]]*\{[[:space:]]*"1".*"9".*"0"[[:space:]]*\}' "$file"; then
    error "Hammerspoon must define native desktop keys 1..9 and 0"
  fi

  if ! grep -Eq 'hs\.hotkey\.bind\(hyper,[[:space:]]*key' "$file"; then
    error "Hammerspoon must bind Cmd+Alt desktop keys from desktopKeys"
  fi

  if ! grep -Eq 'hs\.eventtap\.keyStroke\(\{[[:space:]]*"ctrl"[[:space:]]*\},[[:space:]]*key' "$file"; then
    error "Hammerspoon desktop bindings must proxy to native macOS Ctrl+key shortcuts"
  fi
}

check_sketchybar_gap_script_resolution() {
  local file="$1" matches

  if ! grep -Eq '^export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"$' "$file"; then
    error "toggle-sketchybar.sh must set a controlled PATH for GUI launches"
  fi

  if ! grep -Eq 'SKETCHYBAR_BIN=.*resolve_bin sketchybar .*(/opt/homebrew/bin/sketchybar).*(/usr/local/bin/sketchybar)' "$file"; then
    error "toggle-sketchybar.sh must resolve SketchyBar from explicit common paths"
  fi

  if ! grep -Eq '"\$SKETCHYBAR_BIN"[[:space:]]+--' "$file"; then
    error "toggle-sketchybar.sh must invoke SketchyBar through SKETCHYBAR_BIN"
  fi

  matches="$(grep_file_noncomment '(^|[[:space:]])sketchybar[[:space:]]+--|(^|[[:space:]])aerospace([[:space:]]|$)' "$file")"
  if [[ -n "$matches" ]]; then
    echo "$matches" >&2
    error "toggle-sketchybar.sh must not rely on bare sketchybar or call AeroSpace"
  fi
}

run_active_bridge_regex_self_tests

echo "Checking window-management ownership invariants under $ROOT ..."

# 1. No AeroSpace install/config wiring remains active in the repo.
if [[ -e "$ROOT/wm/aerospace" ]]; then
  error "AeroSpace config directory must not exist: $ROOT/wm/aerospace"
fi

for file in "$ROOT/os/mac/brew/Brewfile" "$ROOT/symlinks/conf.macos.yaml" "$ROOT/restoration_scripts/01-verify-install.sh"; do
  if [[ -f "$file" ]]; then
    check_file_noncomment "$file" 'aerospace|nikitabobko/tap' \
      "AeroSpace install/config reference found in $file"
  fi
done

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

# 5. Hammerspoon is standalone and runtime scripts must not call or reference AeroSpace.
if [[ -d "$ROOT/editors/hammerspoon" ]]; then
  check_no_active_aerospace_runtime_usage "$ROOT/editors/hammerspoon"
fi

for scope in "$ROOT/scripts" "$ROOT/wm"; do
  if [[ -d "$scope" ]]; then
    check_no_active_aerospace_runtime_usage "$scope"
  fi
done

# 6. Hammerspoon owns centering the focused window through Cmd+Alt+M.
if [[ -f "$hotkeys" ]]; then
  if ! grep -Eq 'hs\.hotkey\.bind\(hyper,[[:space:]]*["'"'"']m["'"'"']' "$hotkeys"; then
    error "Hammerspoon must bind Cmd+Alt+M to center the focused window"
  fi

  if ! grep -Eq 'centerFocusedWindow' "$hotkeys"; then
    error "Cmd+Alt+M binding must call centerFocusedWindow"
  fi

  if ! grep -Eq 'hs\.hotkey\.bind\(hyper,[[:space:]]*["'"'"']f["'"'"']' "$hotkeys"; then
    error "Hammerspoon must bind Cmd+Alt+F to maximize the focused window"
  fi

  if ! grep -Eq 'maximizeFocusedWindow' "$hotkeys"; then
    error "Cmd+Alt+F binding must call maximizeFocusedWindow"
  fi

  check_hammerspoon_layout_binding "$hotkeys" hyper s StackRightLayout "Cmd+Alt+S"
  check_hammerspoon_layout_binding "$hotkeys" shiftHyper s ColumnsLayout "Cmd+Alt+Shift+S"
  check_hammerspoon_layout_binding "$hotkeys" shiftHyper m CenterMainLayout "Cmd+Alt+Shift+M"
  check_hammerspoon_native_desktop_bindings "$hotkeys"

  if grep -Eq 'saveCurrentWorkspaceLayout|workspaceLayoutRestore' "$hotkeys"; then
    error "Hammerspoon layout hotkeys must not save per-workspace restore state"
  fi

  check_hammerspoon_sketchybar_toggle_binding "$hotkeys"
fi

sketchybar_gap_script="$ROOT/scripts/wm/toggle-sketchybar.sh"
if [[ -f "$sketchybar_gap_script" ]]; then
  check_sketchybar_gap_script_resolution "$sketchybar_gap_script"
else
  error "SketchyBar toggle script missing: $sketchybar_gap_script"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "All window-management invariants passed."
  exit 0
else
  echo "Window-management invariant checks failed." >&2
  exit 1
fi
