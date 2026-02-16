function cdd() {
	cd "$(ls -d -- */ | fzf)" || echo "Invalid directory"
}

function j() {
	fname=$(declare -f -F _z)

	[ -n "$fname" ] || source "$DOTLY_PATH/modules/z/z.sh"

	_z "$1"
}

function recent_dirs() {
	# This script depends on pushd. It works better with autopush enabled in ZSH
	escaped_home=$(echo $HOME | sed 's/\//\\\//g')
	selected=$(dirs -p | sort -u | fzf)

	cd "$(echo "$selected" | sed "s/\~/$escaped_home/")" || echo "Invalid directory"
}

# Lazy load NVM (se carga solo al usar node/npm/nvm/npx)
function lazy_load_nvm() {
	unset -f node npm nvm npx
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
	[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
function node() { lazy_load_nvm && node "$@"; }
function npm() { lazy_load_nvm && npm "$@"; }
function nvm() { lazy_load_nvm && nvm "$@"; }
function npx() { lazy_load_nvm && npx "$@"; }

# Lazy load SDKMAN (se carga solo al usar sdk/java/gradle/mvn)
function lazy_load_sdk() {
	unset -f sdk java gradle mvn
	[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
}
function sdk() { lazy_load_sdk && sdk "$@"; }
function java() { lazy_load_sdk && java "$@"; }
function gradle() { lazy_load_sdk && gradle "$@"; }
function mvn() { lazy_load_sdk && mvn "$@"; }

# Renombrar sesión tmux al cambiar de directorio (solo zsh)
if [[ -n "$ZSH_VERSION" ]]; then
  function _tmux_rename_session_on_cd() {
    if [[ -n "$TMUX" ]]; then
      local session=$(tmux display-message -p '#S')
      [[ "$session" == _* ]] && return
      tmux rename-session "$(basename "$PWD")"
    fi
  }
  chpwd_functions+=(_tmux_rename_session_on_cd)
fi
