#!/usr/bin/env bash
#
# Point iTerm2 to use preferences from .local/
# Copies the curated template to .local/ if no instance exists yet

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ITERM_INSTANCE_DIR="$DOTFILES_DIR/.local/iterm2"
ITERM_INSTANCE="$ITERM_INSTANCE_DIR/com.googlecode.iterm2.plist"
ITERM_TEMPLATE="$DOTFILES_DIR/iterm2/com.googlecode.iterm2.plist.template"

mkdir -p "$ITERM_INSTANCE_DIR"

if [ ! -f "$ITERM_INSTANCE" ]; then
  if [ -f "$ITERM_TEMPLATE" ]; then
    cp "$ITERM_TEMPLATE" "$ITERM_INSTANCE"
    echo "  [ OK ] iTerm2 preferences created from template in .local/iterm2/"
  else
    echo "  [ .. ] No iTerm2 template found, skipping"
  fi
fi

if defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null | grep -q "true"; then
  echo "  [ OK ] iTerm2 preferences already configured"
else
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$ITERM_INSTANCE_DIR"
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  echo "  [ OK ] iTerm2 preferences pointed to .local/iterm2/"
fi
