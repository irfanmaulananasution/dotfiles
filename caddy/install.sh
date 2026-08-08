#!/usr/bin/env bash
#
# Symlink Caddyfile, add hosts entry, and start Caddy as a boot service
# Makes https://opencode.localhost → localhost:4096 (auto-HTTPS via self-signed cert)

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

# Detect homebrew prefix
if [ -d "/opt/homebrew" ]; then
  PREFIX="/opt/homebrew"
elif [ -d "/usr/local" ]; then
  PREFIX="/usr/local"
else
  echo "  [FAIL] Homebrew prefix not found"
  exit 1
fi

# Symlink Caddyfile into homebrew's config directory
CADDY_SRC="$DOTFILES_DIR/caddy/Caddyfile"
CADDY_DST="$PREFIX/etc/Caddyfile"

if [ -f "$CADDY_DST" ] && [ ! -L "$CADDY_DST" ]; then
  sudo mv "$CADDY_DST" "$CADDY_DST.backup"
fi
sudo ln -sf "$CADDY_SRC" "$CADDY_DST"
echo "  [ OK ] Caddyfile symlinked to $CADDY_DST"

# Remove old .lan hosts entries (no longer needed — .localhost resolves natively)
for domain in opencode.lan litellm.lan phoenix.lan; do
  sudo sed -i '' "/127.0.0.1 $domain/d" /etc/hosts 2>/dev/null || true
done

# Kill any manually-running Caddy so brew services can take over cleanly
sudo pkill -x caddy 2>/dev/null || true

# Stop existing brew service then re-register
sudo brew services stop caddy 2>/dev/null || true
if ! sudo brew services start caddy 2>&1; then
  echo "  [FAIL] Could not start Caddy via brew services."
  echo "         Try manually: sudo brew services start caddy"
  exit 1
fi
echo "  [ OK ] Caddy registered — https://opencode.localhost → :4096, https://litellm.localhost → :4000, https://phoenix.localhost → :6006"
