<h1 align="center">
  .dotfiles creados con <a href="https://github.com/CodelyTV/dotly">🌚 dotly</a>
</h1>

Setup personal para macOS: Neovim, tmux, Ghostty, LazyGit, Aerospace, Hammerspoon, SketchyBar, Raycast, zsh/Starship.

## 🚀 Instalación rápida

```bash
# 1. Clonar el repo
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles

# 2. Un comando para todo
cd ~/.dotfiles && ./restore.sh
```

Reiniciá la terminal al terminar.

## 📋 Requisitos previos

- Git + SSH key configurada en GitHub.
- Homebrew instalado (macOS): [brew.sh](https://brew.sh).
- En macOS Intel, corré el mismo `restore.sh`; dotly aplica los symlinks de la plataforma correcta.

## 🧩 Qué instala

`restore.sh` hace lo siguiente de forma idempotente:

1. Inicializa el submódulo `dotly`.
2. Crea los symlinks con `dot self install`.
3. Instala [TPM](https://github.com/tmux-plugins/tpm) y los plugins de tmux.
4. Corre `brew bundle` con `os/mac/brew/Brewfile`.

## 🔧 Instalación manual

Si preferís controlar cada paso:

```bash
git clone git@github.com:rafaelraba/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
git submodule update --init --recursive modules/dotly
DOTFILES_PATH="$HOME/.dotfiles" DOTLY_PATH="$DOTFILES_PATH/modules/dotly" "$DOTLY_PATH/bin/dot" self install
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
brew bundle --file="$HOME/.dotfiles/os/mac/brew/Brewfile"
```

## 🎯 Post-instalación

Después de `restore.sh`:

1. **Aerospace**: `aerospace reload-config`
2. **Hammerspoon**: menú → `Reload Config`
3. **Raycast**: abrilo y configurá el atajo de teclado.
4. **Ghostty**: en Settings, usá `JetBrainsMono Nerd Font` o `IosevkaTerm Nerd Font`.

## 🔐 Permisos de accesibilidad

Aerospace, Hammerspoon y Raycast necesitan permisos de accesibilidad:

```text
System Settings → Privacy & Security → Accessibility
→ Agregar/activar: Aerospace, Hammerspoon, Raycast
```

Sin esto no funcionan los atajos de window management.

## ✅ Checklist de verificación

- [ ] `aerospace reload-config` no tira errores.
- [ ] Hammerspoon muestra el ícono en la barra y no hay errores en la consola.
- [ ] `nvim` abre sin errores de plugins.
- [ ] `tmux` inicia y el prefix es `Ctrl+a`.
- [ ] `lazygit` abre.
- [ ] `ghostty` usa una Nerd Font.
- [ ] Los atajos de Aerospace/Hammerspoon/Raycast responden.

## ⚠️ Notas conocidas

- El Brewfile usa `python@3.13` como fórmula estable de Python.
- Algunos paquetes de `brew bundle` pueden fallar por dependencias manuales; revisar el output y reintentar.
