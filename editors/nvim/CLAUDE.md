# Neovim Configuration

## Overview

Configuracion basada en **LazyVim** con **lazy.nvim** como plugin manager. Tema principal: **Catppuccin Mocha** con fondo transparente. Enfocada en desarrollo TypeScript/Go/Java.

## Estructura

```
~/.config/nvim/
├── init.lua                     # Entry point
├── lazy-lock.json               # Lock de versiones de plugins
├── lazyvim.json                 # Extras de LazyVim habilitados
├── stylua.toml                  # Config de formatter Lua
├── lua/
│   ├── config/
│   │   ├── lazy.lua             # Bootstrap y setup de lazy.nvim
│   │   ├── options.lua          # Opciones vim (diff patience, fillchars)
│   │   ├── keymaps.lua          # Keymaps custom (<leader>gd, <leader>tc)
│   │   ├── autocmds.lua         # Autoread (fs_event watchers), oil autosave, JSON watcher
│   │   └── gentleman/utils.lua  # Utilidades de conversion de color (hex/rgb/hsl)
│   └── plugins/
│       ├── colorscheme.lua      # Catppuccin Mocha (transparente)
│       ├── tokyonight.lua       # Tema alternativo (inactivo)
│       ├── editor.lua           # goto-preview, mini.hipatterns, git.nvim
│       ├── ui.lua               # which-key, lualine, zen-mode, toggleterm, snacks.nvim, incline
│       ├── bufferline.lua       # DESHABILITADO
│       ├── neo-tree.lua         # Arbol de archivos (ancho: 50)
│       ├── oil.lua              # File manager estilo buffer
│       ├── diffview.lua         # Git diff viewer
│       ├── rest.lua             # REST client (kulala.nvim)
│       ├── render-markdown.lua  # Render + preview de markdown
│       ├── json.lua             # Folding (nvim-ufo), tree/graph viewers, keymaps JSON
│       └── lsp/
│           ├── mason.lua        # Mason: gestiona LSPs, formatters, linters
│           ├── typescript.lua   # tsserver + prettier + inlay hints
│           ├── go.lua           # gopls + gofumpt + staticcheck
│           ├── java.lua         # JDTLS (4GB heap, JUnit/Mockito/AssertJ)
│           └── tailwind.lua     # tailwindcss-language-server (CVA/cx patterns)
├── ftplugin/
│   └── java.lua                 # Java: tabs 4 espacios
├── md-preview/
│   └── server.js                # Servidor custom para preview markdown
└── static/json-viewer/          # HTML viewers para JSON (tree + JSON Crack via Docker)
```

## Plugins principales (~60+)

| Categoria | Plugins | Notas |
|---|---|---|
| Framework | LazyVim, lazy.nvim | Base de la config |
| Tema | catppuccin (activo), tokyonight (alt) | Ambos con transparencia |
| File explorer | neo-tree, oil.nvim | oil: edita filesystem como buffer |
| Git | diffview.nvim, git.nvim, gitsigns | Diff, blame, browse |
| LSP | nvim-lspconfig, mason.nvim | Auto-install habilitado |
| Completion | blink.cmp, friendly-snippets | Motor de completado moderno |
| Treesitter | nvim-treesitter, textobjects, autotag | Parsers: bash, html, js, json, lua, md, py, tsx, ts, vim, yaml |
| UI | which-key, lualine, incline, snacks.nvim | Dashboard custom (COBE ASCII art) |
| Terminal | toggleterm.nvim | Float, horizontal, vertical |
| REST | kulala.nvim | Formato IntelliJ HTTP client |
| Markdown | render-markdown, markdown-preview | Soporte mermaid |
| JSON | nvim-ufo, custom tree/graph viewers | JSON Crack via Docker |
| Debug | nvim-dap, dap-ui, dap-go | DAP protocol |
| Zen | zen-mode.nvim | Integracion tmux + gitsigns |
| Formato | conform.nvim (prettier) | JS/TS/React/JSON/HTML/CSS |
| Linting | nvim-lint (eslint_d, golangci-lint) | |

## Keymaps importantes

**Leader key: `<space>`**

### Git
- `<leader>gd` - Diffview Open
- `<leader>gh` - File History
- `<leader>gH` - All History
- `<leader>gc` - Diffview Close
- `<leader>gb` - Git Blame
- `<leader>go` - Git Browse

### Goto Preview
- `gpd` / `gpD` / `gpi` / `gpy` / `gpr` - Preview definition/declaration/implementation/type/references
- `gP` - Cerrar previews

### Archivos
- `-` - Oil (directorio padre)
- `<leader>E` - Oil (flotante)
- `<leader>-` - Oil en directorio del archivo actual
- `<leader>fb` - Find Buffers (snacks picker)

### REST Client (`<leader>r`)
- `s` send | `a` send all | `r` replay last | `b` scratchpad | `o` open UI | `q` close | `i` inspect | `c` copy cURL | `C` paste from cURL | `e` env | `j` cookies jar | `g` GraphQL schema | `u` auth config
- En archivo `.http`: `<CR>` también envía la request bajo el cursor
- Dentro de la ventana de respuesta: `H` headers | `B` body | `A` ambos | `V` verbose | `S` stats | `R` report | `F` filter | `]` / `[` next/prev response | `X` clear history | `?` help

### JSON (buffer-local, `<leader>j`)
- `d` delete node | `f` fold toggle | `F` fold all | `U` unfold all | `y` yank value | `t` tree viewer | `c` graph viewer | `x` stop viewer

### UI/Terminal
- `<leader>z` - Zen Mode
- `<leader>tt` - Terminal float
- `<leader>th` - Terminal horizontal
- `<leader>tv` - Terminal vertical
- `<leader>ua` - Toggle Autoread

### Folding
- `zR` / `zM` - Abrir/cerrar todo
- `zr` / `zm` - Abrir/cerrar por nivel
- `zp` - Preview fold

### Markdown
- `<leader>mp` - Preview en navegador

### Tests
- `<leader>tc` - Limpiar marcas de test (junit/testng)

## LSP por lenguaje

| Lenguaje | Server | Formatter | Linter | Notas |
|---|---|---|---|---|
| TypeScript/JS/React | tsserver | prettier | eslint_d | Inlay hints completos |
| Go | gopls | gofumpt | golangci-lint | staticcheck, shadow analysis |
| Java | JDTLS | - | - | 4GB heap, JUnit5/Mockito/AssertJ/Hamcrest |
| Tailwind CSS | tailwindcss | - | - | Patterns CVA + cx |
| HTML | html-lsp | prettier | - | |
| CSS | css-lsp | prettier | - | |

## Opciones relevantes

- **Diff**: algoritmo `patience`, indent-heuristic, linematch:60
- **Java ftplugin**: tabstop=4, shiftwidth=4
- **Autoread**: sistema completo con fs_event watchers por buffer + fallback FocusGained/BufEnter/CursorHold. Muestra notificacion al recargar. Toggle con `<leader>ua`.
- **Oil**: muestra archivos ocultos, natural sort, oculta `..` y `.git`, float 100x30 con borde redondeado
- **Neo-tree**: ancho 50 columnas

## LazyVim extras habilitados

Revisar `lazyvim.json` para la lista completa. Incluye: java, dap-core, go, typescript, tailwind, eslint, rest.

## Notas para edicion

- Los plugins estan organizados un archivo por grupo/plugin en `lua/plugins/`
- LSP configs separados en `lua/plugins/lsp/`
- Para agregar un nuevo lenguaje: crear archivo en `lua/plugins/lsp/`, agregar server en mason.lua
- El autoread en `autocmds.lua` es clave para la integracion con herramientas externas (Claude Code, git, etc.)
- Los JSON viewers usan servidor Python HTTP + Docker para JSON Crack
- bufferline esta explicitamente deshabilitado (`enabled = false`)
