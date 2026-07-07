# OPENSPEC:START
# OpenSpec shell completions configuration
fpath=("$HOME/.zsh/completions" $fpath)
# OPENSPEC:END

#!/usr/bin/env zsh
# Uncomment for debuf with `zprof`
# zmodload zsh/zprof

# Auto-start tmux (excluye terminales de JetBrains)
if command -v tmux &> /dev/null && [ -z "$TMUX" ] && [[ "$TERMINAL_EMULATOR" != "JetBrains-JediTerm" ]] && [[ "$TERM" != "dumb" ]] && [[ -z "$VSCODE_RESOLVING_ENVIRONMENT" ]]; then
  exec tmux new-session -A -s "$(basename "$PWD")"
fi

# ZSH Ops
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FCNTL_LOCK
setopt +o nomatch
# setopt autopushd

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

# Start Zim
source "$ZIM_HOME/init.zsh"

# Async mode for autocompletion
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_HIGHLIGHT_MAXLENGTH=300

source "$DOTFILES_PATH/shell/init.sh"

# Private secrets (never commit this file)
[ -f "$HOME/.secrets/exports" ] && source "$HOME/.secrets/exports"

fpath=("$DOTFILES_PATH/shell/zsh/themes" "$DOTFILES_PATH/shell/zsh/completions" "$DOTLY_PATH/shell/zsh/themes" "$DOTLY_PATH/shell/zsh/completions" $fpath)

autoload -Uz promptinit && promptinit
# prompt ${DOTLY_THEME:-codely}  # Desactivado para usar Starship
eval "$(starship init zsh)"

# Zoxide (cd inteligente) - usa 'z' en lugar de 'cd'
eval "$(zoxide init zsh)"

# Aliases para herramientas mejoradas
alias ls="eza --icons"
alias ll="eza -la --icons --git"
alias tree="eza --tree --icons"
alias cat="bat"

source "$DOTLY_PATH/shell/zsh/bindings/dot.zsh"
source "$DOTLY_PATH/shell/zsh/bindings/reverse_search.zsh"
source "$DOTFILES_PATH/shell/zsh/key-bindings.zsh"

# NVM y SDKMAN usan lazy loading (ver shell/functions.sh)
export NVM_DIR="$HOME/.nvm"
export SDKMAN_DIR="$HOME/.sdkman"
export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
export PATH="$JAVA_HOME/bin:$PATH"
export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=$HOME/.opencode/bin:$PATH

# Added by Antigravity
export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# Added by git-ai installer on Thu Jun 25 16:03:08 -05 2026
export PATH="/Users/rrabamoreno/.git-ai/bin:$PATH"
export ANTHROPIC_MODEL="claude-sonnet-4-6[1m]"

# Internal Python Registry
export PIP_INDEX_URL='https://pypi.artifacts.furycloud.io/simple'
export UV_INDEX_URL='https://pypi.artifacts.furycloud.io/simple'
