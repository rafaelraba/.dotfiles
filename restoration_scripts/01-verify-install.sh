#!/usr/bin/env bash
set -uo pipefail

# Post-install verification for Rafael's dotfiles.
# Runs after `dot self install`. Set DOTFILES_VERIFY_STRICT=1 to fail on errors.

DOTFILES_PATH="${DOTFILES_PATH:-$HOME/.dotfiles}"
STRICT="${DOTFILES_VERIFY_STRICT:-0}"
failures=0

echo "🔍 Verifying dotfiles setup..."
echo ""

check_symlink() {
    local target="$1"
    if [ -L "$target" ]; then
        echo "  ✅ $(basename "$target")"
        return 0
    elif [ -e "$target" ]; then
        echo "  ⚠️  exists but is not a symlink: $target"
        failures=$((failures + 1))
        return 1
    else
        echo "  ⚠️  missing: $target"
        failures=$((failures + 1))
        return 1
    fi
}

check_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✅ $cmd"
        return 0
    else
        echo "  ⚠️  not in PATH: $cmd"
        failures=$((failures + 1))
        return 1
    fi
}

echo "Symlinks:"
check_symlink "$HOME/.hammerspoon"
check_symlink "$HOME/.config/nvim"
check_symlink "$HOME/.config/tmux"
check_symlink "$HOME/.config/lazygit/config.yml"
check_symlink "$HOME/.config/starship.toml"
check_symlink "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

echo ""
echo "Core tools:"
check_command nvim
check_command node
check_command npm
check_command tmux
check_command lazygit
check_command starship
check_command fzf
check_command zoxide
check_command eza
check_command bat
check_command rg

echo ""
echo "Window management:"
check_command sketchybar

echo ""
echo "Neovim Markdown:"
if nvim --headless '+lua assert(vim.fn.executable("marksman") == 1, "marksman is not in PATH")' '+qall'; then
    echo "  ✅ marksman"
else
    echo "  ⚠️  marksman is not in PATH"
    failures=$((failures + 1))
fi

echo ""
echo "Manual steps after first install:"
echo "  1. Open Hammerspoon and grant Accessibility permissions."
echo "  2. Reload Hammerspoon config for global input helpers."
echo "  3. Open Raycast and grant Accessibility permissions."
echo "  4. Configure or import Raycast Window Management settings and hotkeys."
echo "  5. Optionally export Raycast settings to an encrypted .rayconfig backup."
echo "  6. In Ghostty, set the font to 'JetBrainsMono Nerd Font' or 'IosevkaTerm Nerd Font'."
echo ""

if [ "$STRICT" = "1" ] && [ "$failures" -gt 0 ]; then
    echo "Verification failed with $failures issue(s)."
    exit 1
fi

exit 0
