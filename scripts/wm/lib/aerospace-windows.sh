#!/usr/bin/env bash

# DEPRECATED: This AeroSpace -> Hammerspoon bridge helper is no longer used.
# The active config applies layouts directly in Hammerspoon via hs.window.
# Kept for reference only. It defines no active helpers and does not call /opt/homebrew/bin/hs.

# Safe to source: this block only runs when the file is executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  echo "aerospace-windows.sh is deprecated and no longer provides active bridge helpers." >&2
fi
