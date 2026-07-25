#!/usr/bin/env bash
#
# Apply macOS system defaults
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ -f "$DOTFILES_DIR/mac/defaults.symlink" ]; then
  echo "==> Applying macOS defaults..."
  source "$DOTFILES_DIR/mac/defaults.symlink"
  echo "  [ OK ] macOS defaults applied"
fi
