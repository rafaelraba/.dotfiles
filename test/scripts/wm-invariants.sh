#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="${DOTFILES_PATH:-$REPO_ROOT}"
fail=0

error() {
  echo "FAIL: $*" >&2
  fail=1
}

grep_noncomment() {
  local pattern="$1" path="$2"
  grep -R -v -E '^[[:space:]]*(#|--)' "$path" 2>/dev/null | grep -E "$pattern" || true
}

aerospace_config="$ROOT/editors/aerospace/aerospace.toml"
hammerspoon_dir="$ROOT/editors/hammerspoon"
hammerspoon_init="$hammerspoon_dir/init.lua"
hammerspoon_input="$hammerspoon_dir/modules/input.lua"
toggle_sketchybar="$ROOT/scripts/wm/toggle-sketchybar.sh"

echo "Checking clean window-management invariants under $ROOT ..."

if [[ ! -f "$aerospace_config" ]]; then
  error "AeroSpace config missing: $aerospace_config"
else
  matches="$(grep_noncomment 'raycast://' "$aerospace_config")"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    error "AeroSpace config must not call Raycast or external geometry tools"
  fi

  if ! grep -Eq "alt-b[[:space:]]*=[[:space:]]*'exec-and-forget.*toggle-sketchybar\.sh" "$aerospace_config"; then
    error "AeroSpace must expose Alt+B to toggle the workspace bar"
  fi

  if ! grep -Eq "alt-shift-semicolon[[:space:]]*=[[:space:]]*'mode service'" "$aerospace_config"; then
    error "AeroSpace must keep the default service-mode shortcut"
  fi

  if ! grep -Eq "f[[:space:]]*=[[:space:]]*\['layout floating tiling',[[:space:]]*'mode main'\]" "$aerospace_config"; then
    error "AeroSpace service mode must keep native floating/tiling toggle"
  fi
fi

if [[ ! -f "$hammerspoon_init" ]]; then
  error "Hammerspoon init missing: $hammerspoon_init"
elif ! grep -Eq 'require\("modules\.input"\)' "$hammerspoon_init"; then
  error "Hammerspoon init must load only the global input helper module"
fi

if [[ ! -f "$hammerspoon_input" ]]; then
  error "Hammerspoon global input helper missing: $hammerspoon_input"
else
  matches="$(grep_noncomment 'hs\.window|hs\.layout|hs\.spaces|hs\.application|scripts/wm|aerospace|sketchybar|setFrame' "$hammerspoon_input")"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    error "Hammerspoon must stay limited to global input helpers"
  fi
fi

if [[ -d "$hammerspoon_dir/modules" ]]; then
  hammerspoon_module_count="$(find "$hammerspoon_dir/modules" -type f -name '*.lua' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$hammerspoon_module_count" != "1" ]]; then
    find "$hammerspoon_dir/modules" -type f -name '*.lua' 2>/dev/null >&2 || true
    error "Hammerspoon modules should contain only input.lua"
  fi
fi

if [[ -f "$toggle_sketchybar" ]]; then
  if ! grep -Eq 'VISIBLE_TOP_GAP=60' "$toggle_sketchybar"; then
    error "SketchyBar toggle must reserve the visible top gap"
  fi

  if ! grep -Eq 'HIDDEN_TOP_GAP=24' "$toggle_sketchybar"; then
    error "SketchyBar toggle must reclaim the hidden top gap"
  fi
else
  error "SketchyBar toggle script missing: $toggle_sketchybar"
fi

wm_script_count="$(find "$ROOT/scripts/wm" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$wm_script_count" != "1" ]]; then
  find "$ROOT/scripts/wm" -type f 2>/dev/null >&2 || true
  error "scripts/wm should contain only toggle-sketchybar.sh"
fi

if [[ "$fail" -eq 0 ]]; then
  echo "All clean window-management invariants passed."
  exit 0
fi

echo "Window-management invariant checks failed." >&2
exit 1
