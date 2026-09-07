export DOTFILES=$HOME/.dotfiles

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set ZSH_CUSTOM to dotfiles so Oh My Zsh loads all *.zsh from topic dirs
export ZSH_CUSTOM=$DOTFILES

ZSH_THEME="robbyrussell"

# Uncomment to change auto-update behavior
# zstyle ':omz:update' mode disabled
# zstyle ':omz:update' mode auto

# Uncomment if pasting URLs is messed up
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment to enable command auto-correction
# ENABLE_CORRECTION="true"

HIST_STAMPS="dd/mm/yyyy"

# Plugins
plugins=(git docker npm)

source $ZSH/oh-my-zsh.sh

# User configuration
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Hermes CLI: force dark mode. Terminal bg is black, but COLORFGBG=0;15 makes
# Hermes misdetect "light" and remap text to near-black (#1A1A1A) — unreadable.
# HERMES_LIGHT=0 short-circuits the detection ladder and keeps text bright.
export HERMES_LIGHT=0

# Load environment variables from ~/.env (git-ignored, for secrets)
# Uses `source` so shell quoting and var expansion work correctly:
#   KEY="value"       -> value (quotes stripped)
#   ALIAS=$KEY        -> <value of KEY> (reference expanded)
# `set -a` exports every var defined while it's on; `set +a` turns it back off.
# A hand-rolled while/read loop cannot replicate this without `eval`, which is
# riskier than `source`ing a 0600 owner-only file.
if [[ -f "$HOME/.env" ]]; then
  set -a
  source "$HOME/.env"
  set +a
fi

# Local bin
export PATH="$HOME/.local/bin:$PATH"