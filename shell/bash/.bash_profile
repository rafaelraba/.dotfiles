source ~/.bashrc

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
export ANTHROPIC_MODEL="claude-sonnet-4-6[1m]"

# Internal Python Registry
export PIP_INDEX_URL='https://pypi.artifacts.furycloud.io/simple'
export UV_INDEX_URL='https://pypi.artifacts.furycloud.io/simple'
