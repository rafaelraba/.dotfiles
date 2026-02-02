#!/usr/bin/env zsh
# Uncomment for debuf with `zprof`
# zmodload zsh/zprof

# Auto-start tmux (nueva sesión por ventana)
if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
  tmux new -s "$(date +%s)"
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
export PATH="$PATH:/Users/rafaba/Library/Application Support/JetBrains/Toolbox/scripts"
export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=/Users/rafaba/.opencode/bin:$PATH
