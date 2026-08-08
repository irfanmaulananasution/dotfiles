#!/usr/bin/env bash
#
# Apply macOS system defaults and register startup script
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ -f "$DOTFILES_DIR/mac/defaults.symlink" ]; then
  echo "==> Applying macOS defaults..."
  source "$DOTFILES_DIR/mac/defaults.symlink"
  echo "  [ OK ] macOS defaults applied"
fi

echo "==> Setting up startup script..."
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.dotfiles.startup.plist"
mkdir -p "$(dirname "$LAUNCHD_PLIST")"

cat > "$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.dotfiles.startup</string>
  <key>ProgramArguments</key>
  <array>
    <string>bash</string>
    <string>-c</string>
    <string>$HOME/.startup</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/dotfiles-startup.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/dotfiles-startup.err</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/com.dotfiles.startup" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCHD_PLIST" 2>/dev/null || true
launchctl enable "gui/$(id -u)/com.dotfiles.startup" 2>/dev/null || true
echo "  [ OK ] startup script registered (launchctl)"
