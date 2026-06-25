#!/usr/bin/env bash
set -uo pipefail

# Post-install verification for Rafael's dotfiles.
# Runs automatically after `dot self install`. Never fails the install.

DOTFILES_PATH="${DOTFILES_PATH:-$HOME/.dotfiles}"

echo "🔍 Verifying dotfiles setup..."
echo ""

check_symlink() {
    local target="$1"
    if [ -L "$target" ]; then
        echo "  ✅ $(basename "$target")"
        return 0
    elif [ -e "$target" ]; then
        echo "  ⚠️  exists but is not a symlink: $target"
        return 1
    else
        echo "  ⚠️  missing: $target"
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
        return 1
    fi
}

echo "Symlinks:"
check_symlink "$HOME/.config/nvim"
check_symlink "$HOME/.config/tmux"
check_symlink "$HOME/.config/lazygit/config.yml"
check_symlink "$HOME/.config/starship.toml"
check_symlink "$HOME/Library/Application Support/com.mitchellh.ghostty/config"

echo ""
echo "Core tools:"
check_command nvim
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
echo "Manual steps after first install:"
echo "  1. Open Raycast and grant Accessibility permissions."
echo "  2. Configure or import Raycast Window Management settings and hotkeys."
echo "  3. Optionally export Raycast settings to an encrypted .rayconfig backup."
echo "  4. In Ghostty, set the font to 'JetBrainsMono Nerd Font' or 'IosevkaTerm Nerd Font'."
echo ""

exit 0
