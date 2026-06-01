#!/usr/bin/env bash
set -euo pipefail

DOTFILES_PATH="${DOTFILES_PATH:-$HOME/.dotfiles}"
DOTLY_PATH="$DOTFILES_PATH/modules/dotly"

echo "🔧 Restaurando dotfiles..."
echo ""

# ── 1. Init dotly submodule ──
echo "📦 Inicializando submódulo dotly..."
git -C "$DOTFILES_PATH" submodule update --init --recursive modules/dotly

# ── 2. Instalar symlinks con dotly ──
echo "🔗 Creando symlinks..."
DOTFILES_PATH="$DOTFILES_PATH" DOTLY_PATH="$DOTLY_PATH" "$DOTLY_PATH/bin/dot" self install

# ── 3. Instalar TPM (Tmux Plugin Manager) ──
TPM_PATH="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_PATH" ]; then
    echo "📥 Instalando TPM..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_PATH"
else
    echo "✅ TPM ya instalado"
fi

# ── 4. Instalar plugins de tmux ──
echo "🔌 Instalando plugins de tmux..."
"$TPM_PATH/bin/install_plugins" > /dev/null 2>&1 || true

# ── 5. Homebrew packages (solo macOS) ──
if command -v brew &> /dev/null; then
    BREWFILE="$DOTFILES_PATH/os/mac/brew/Brewfile"
    if [ -f "$BREWFILE" ]; then
        echo "🍺 Instalando paquetes de Homebrew..."
        brew bundle --file="$BREWFILE" --no-lock || echo "⚠️  Algunos paquetes pueden fallar, revisá manualmente"
    fi
else
    echo "⚠️  Homebrew no detectado. Instalalo primero: https://brew.sh"
fi

echo ""
echo "✅ Restauración completa. Reiniciá tu terminal."
