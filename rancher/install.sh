#!/usr/bin/env bash
#
# Apply Rancher Desktop settings from the repo template.
# Pattern: declarative file in repo → copied to target (no symlink).
# Rationale: Rancher Desktop manages this file — a symlink would break.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RANCHER_APP="/Applications/Rancher Desktop.app"
SETTINGS_DIR="$HOME/Library/Preferences/rancher-desktop"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
TEMPLATE="$DOTFILES_DIR/rancher/settings.json"

if [ ! -d "$RANCHER_APP" ]; then
  exit 0
fi

mkdir -p "$SETTINGS_DIR"
cp "$TEMPLATE" "$SETTINGS_FILE"

echo "  [ OK ] Rancher Desktop configured: K8s disabled, RAM 2GB"
