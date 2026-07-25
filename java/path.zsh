# SDKMAN — must be sourced AFTER shell init, the init script patches $PATH.
# Documentation: https://sdkman.io/install
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"