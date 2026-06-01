<h1 align="center">
  .dotfiles creados con <a href="https://github.com/CodelyTV/dotly">🌚 dotly</a>
</h1>

## 🚀 Restauración en máquina nueva

```bash
# 1. Clonar el repo
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles

# 2. Un comando para todo
cd ~/.dotfiles && ./restore.sh
```

Esto instala automáticamente:
- 🔗 Symlinks de todas las configuraciones (shell, nvim, tmux, ghostty, git, starship)
- 🔌 TPM + plugins de tmux
- 🍺 Paquetes de Homebrew (Brewfile)

Después reiniciá tu terminal y listo.

### Requisitos previos
- Git + SSH key configurada en GitHub
- Homebrew (si estás en macOS, instalalo desde [brew.sh](https://brew.sh))

### Manual (paso a paso)
Si preferís hacerlo manual:
```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
git submodule update --init --recursive modules/dotly
DOTFILES_PATH="$HOME/.dotfiles" DOTLY_PATH="$DOTFILES_PATH/modules/dotly" "$DOTLY_PATH/bin/dot" self install
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
brew bundle --file="$HOME/.dotfiles/os/mac/brew/Brewfile"
```
