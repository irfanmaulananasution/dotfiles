#!/usr/bin/env bash
#
# Symlink opencode config to ~/.config/opencode/

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
CONFIG_DIR="$HOME/.config/opencode"

# Locate env file (accept ~/.env or ~/.env.local)
ENV_SRC=""
if [ -f "$HOME/.env.local" ]; then
  ENV_SRC="$HOME/.env.local"
elif [ -f "$HOME/.env" ]; then
  ENV_SRC="$HOME/.env"
fi

if [ -z "$ENV_SRC" ]; then
  echo "  [FAIL] Neither ~/.env nor ~/.env.local found."
  echo "         Create one with PERSONAL_OPENCODE_API_KEY from .env.example."
  exit 1
fi

# Ensure ~/.env is symlinked to .local/.env.local
LOCAL_ENV="$DOTFILES_DIR/.local/.env.local"
mkdir -p "$DOTFILES_DIR/.local"
if [ ! -f "$LOCAL_ENV" ]; then
  cp "$ENV_SRC" "$LOCAL_ENV"
fi
if [ ! -L "$HOME/.env" ] || [ "$(readlink "$HOME/.env")" != "$LOCAL_ENV" ]; then
  ln -sf "$LOCAL_ENV" "$HOME/.env"
fi

# Source it
set -a; source "$HOME/.env"; set +a

# Verify PERSONAL_OPENCODE_API_KEY is set
if [ -z "${PERSONAL_OPENCODE_API_KEY:-}" ]; then
  echo "  [FAIL] PERSONAL_OPENCODE_API_KEY is not set."
  echo "         Edit $LOCAL_ENV and set your API key."
  exit 1
fi

mkdir -p "$CONFIG_DIR"

# Backup existing config if it's not a symlink
if [ -f "$CONFIG_DIR/opencode.jsonc" ] && [ ! -L "$CONFIG_DIR/opencode.jsonc" ]; then
  mv "$CONFIG_DIR/opencode.jsonc" "$CONFIG_DIR/opencode.jsonc.backup"
fi

ln -sf "$DOTFILES_DIR/opencode/opencode.jsonc" "$CONFIG_DIR/opencode.jsonc"
echo "  [ OK ] opencode config symlinked to $CONFIG_DIR/opencode.jsonc"

