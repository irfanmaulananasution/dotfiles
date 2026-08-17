#!/usr/bin/env bash
#
# Configure Rancher Desktop and bring the Docker engine up.
# Pattern: declarative file in repo → copied to target (no symlink).
# Rationale: Rancher Desktop manages this file — a symlink would break.
#
# This installer is the Docker readiness gate for the rest of the bootstrap:
# Rancher Desktop hosts the Docker engine, but the `docker` CLI (~/.rd/bin) and
# the engine only exist after the app has been launched. This script launches
# it in the background and polls `docker info` until it is ready.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
RANCHER_APP="/Applications/Rancher Desktop.app"
SETTINGS_DIR="$HOME/Library/Preferences/rancher-desktop"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
TEMPLATE="$DOTFILES_DIR/rancher/settings.json"
RANCHER_BIN="$HOME/.rd/bin"

if [ ! -d "$RANCHER_APP" ]; then
  echo "  [WARN] Rancher Desktop not installed — Docker will not be available."
  exit 0
fi

# Settings must be in place BEFORE first launch so Rancher skips its first-run
# wizard (it only shows when saved settings are empty).
mkdir -p "$SETTINGS_DIR"
cp "$TEMPLATE" "$SETTINGS_FILE"
echo "  [ OK ] Rancher Desktop configured: autoStart, 4GB RAM, K8s disabled"

# Expose Rancher's bundled CLIs (docker/kubectl/helm/...) to this process and
# any child topic installers that run after us.
if [ -d "$RANCHER_BIN" ]; then
  export PATH="$RANCHER_BIN:$PATH"
fi

# Already up? Nothing to do.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "  [ OK ] Docker engine already running"
  exit 0
fi

# Launch in the background (first boot downloads the VM image; may take a while).
echo "  [ .. ] Starting Rancher Desktop in the background..."
open -a "Rancher Desktop"

echo "  [ .. ] Waiting for Docker engine (this may take a few minutes on first boot)..."
for i in $(seq 1 150); do
  if [ -d "$RANCHER_BIN" ]; then
    export PATH="$RANCHER_BIN:$PATH"
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "  [ OK ] Docker engine is ready"
    exit 0
  fi
  if [ $((i % 5)) -eq 0 ]; then
    echo "  [ .. ] still waiting for Docker engine ($((i * 2))s)..."
  fi
  sleep 2
done

echo "  [WARN] Docker engine not ready after ~5 min. Rancher Desktop may need attention."
echo "         Re-run after it finishes booting: ./rancher/install.sh"
exit 0