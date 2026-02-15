# CLAUDE.md - Guía para Claude Code

## Proyecto

Dotfiles personales de Rafael Raba, gestionados con [dotly](https://github.com/CodelyTV/dotly) (framework de CodelyTV). El repositorio vive en `$HOME/.dotfiles` y usa symlinks para distribuir configuraciones al sistema.

## Estructura del repositorio

```
.dotfiles/
├── shell/              # Configuración de shells (zsh/bash) y utilidades compartidas
├── editors/            # Configuración de editores y herramientas de desarrollo
│   ├── nvim/           # NeoVim (LazyVim) → symlink en ~/.config/nvim
│   ├── tmux/           # Tmux → symlink en ~/.config/tmux
│   ├── lazygit/        # LazyGit → symlink en ~/.config/lazygit
│   ├── ghostty/        # Terminal Ghostty
│   ├── vim/            # Vim legacy
│   ├── code/           # VS Code (placeholder)
│   └── sublime/        # Sublime Text (placeholder)
├── git/                # .gitconfig global (usa delta como pager)
├── langs/              # Configuración por lenguaje (placeholders)
├── modules/
│   └── dotly/          # Submódulo Git de CodelyTV/dotly
├── os/                 # Archivos específicos por SO (mac/linux)
├── scripts/            # Scripts personalizados
├── bin/                # Ejecutables (sdot wrappers)
├── symlinks/           # Archivos YAML que definen los symlinks
├── restoration_scripts/ # Scripts post-instalación
└── doc/                # Documentación
```

## Cómo funciona dotly

- El binario principal es `$DOTLY_PATH/bin/dot`
- Los symlinks se definen en `symlinks/conf*.yaml` y se aplican con `dot self install`
- Archivos YAML por plataforma: `conf.yaml` (general), `conf.macos.yaml`, `conf.linux.yaml`
- Variables clave: `DOTFILES_PATH=$HOME/.dotfiles`, `DOTLY_PATH=$DOTFILES_PATH/modules/dotly`

## Shell (zsh)

- **Framework:** Zim (`shell/zsh/.zimrc`) con zsh-syntax-highlighting y zsh-autosuggestions
- **Prompt:** Starship (`~/.config/starship.toml`) con paleta "gentleman"
- **Archivos compartidos** entre bash/zsh: `shell/init.sh` carga `aliases.sh`, `exports.sh`, `functions.sh`
- **Lazy loading:** NVM y SDKMAN se cargan bajo demanda (ver `functions.sh`)
- **Navegación:** zoxide (`z`), fzf, eza (reemplazo de ls), bat (reemplazo de cat)
- **Tmux:** se auto-inicia en cada terminal nueva

## NeoVim

- **Base:** LazyVim con lazy.nvim como gestor de plugins
- **Punto de entrada:** `init.lua` → `lua/config/lazy.lua`
- **Plugins personalizados:** `lua/plugins/*.lua` (un archivo por plugin/grupo)
- **LSP:** `lua/plugins/lsp/` con mason.lua, typescript.lua, go.lua, java.lua, tailwind.lua
- **Lenguajes configurados:** TypeScript, Go, Java, Tailwind CSS
- **Formateador:** Prettier para JS/TS/CSS/HTML
- **Tema:** Catppuccin Mocha (transparente), Tokyo Night como alternativa
- **Plugins destacados:** oil.nvim (file manager), diffview.nvim, goto-preview, toggleterm, zen-mode, snacks.nvim (dashboard), kulala.nvim (REST client)
- **REST client:** kulala.nvim — archivos `.http` (formato IntelliJ), variables desde `http-client.env.json`, keymaps bajo `<leader>R`
- **Formato Lua:** stylua (2 espacios, 120 columnas)

## Tmux

- **Prefix:** `Ctrl+a` (no Ctrl+b)
- **Modo:** vi
- **Plugins:** TPM, tmux-sensible, tmux-yank, tmux-resurrect, tmux-which-key
- **Tema:** Kanagawa
- **Splits:** `v` (vertical), `d` (horizontal)
- **Navegación:** hjkl entre paneles
- **Popups:** `Ctrl+a p` (popup), `F12` (scratch flotante)
- **Status bar:** oculta por defecto, toggle con `Ctrl+a b`

## Git

- **Pager:** delta con tema Catppuccin Mocha, side-by-side diffs
- **Aliases dotly:** `gc` (commit), `gd` (pretty-diff), `gl` (pretty-log)

## Convenciones

- Los archivos de configuración de editores van en `editors/`
- Nuevas configuraciones deben registrarse en el YAML de symlinks correspondiente
- No commitear secretos (.env, credentials, etc.) — ver `.gitignore`
- Los módulos Zim (`shell/zsh/.zim/modules/`) se ignoran en git y se reinstalan automáticamente
- Scripts de restauración van en `restoration_scripts/` con prefijo numérico
