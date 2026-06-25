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
legacy_automation_dir="$ROOT/editors/hammer""spoon"
toggle_sketchybar="$ROOT/scripts/wm/toggle-sketchybar.sh"

echo "Checking clean window-management invariants under $ROOT ..."

if [[ ! -f "$aerospace_config" ]]; then
  error "AeroSpace config missing: $aerospace_config"
else
  matches="$(grep_noncomment 'scripts/wm|raycast://' "$aerospace_config")"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    error "AeroSpace config must stay native and must not call helper scripts or external geometry tools"
  fi

  if ! grep -Eq "alt-shift-semicolon[[:space:]]*=[[:space:]]*'mode service'" "$aerospace_config"; then
    error "AeroSpace must keep the default service-mode shortcut"
  fi

  if ! grep -Eq "f[[:space:]]*=[[:space:]]*\['layout floating tiling',[[:space:]]*'mode main'\]" "$aerospace_config"; then
    error "AeroSpace service mode must keep native floating/tiling toggle"
  fi
fi

if [[ -d "$legacy_automation_dir" ]] && find "$legacy_automation_dir" -type f 2>/dev/null | grep -q .; then
  error "Legacy automation config files should not exist in the AeroSpace + Raycast window-management setup"
fi

if [[ -f "$toggle_sketchybar" ]]; then
  matches="$(grep_noncomment 'aerospace|AEROSPACE_|ensure-visible-windows-top-gap' "$toggle_sketchybar")"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    error "SketchyBar toggle must not mutate AeroSpace config or window geometry"
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
