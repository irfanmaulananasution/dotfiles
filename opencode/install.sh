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

# Warn if OPENCODE_SERVER_PASSWORD is not set
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  echo "  [WARN] OPENCODE_SERVER_PASSWORD is not set."
  echo "         The web interface will be unsecured. Add it to $LOCAL_ENV:"
  echo "         OPENCODE_SERVER_PASSWORD=\"your-secret-password\""
fi

mkdir -p "$DOTFILES_DIR/.local" "$CONFIG_DIR"

# Pattern 1: template → .local/ copy (writable) → symlink to target
# Always refresh from template so config changes propagate on reinstall
LOCAL_OPENCODE="$DOTFILES_DIR/.local/opencode.jsonc"
cp "$DOTFILES_DIR/opencode/opencode.jsonc" "$LOCAL_OPENCODE"

# Backup existing config if it's not a symlink
if [ -f "$CONFIG_DIR/opencode.jsonc" ] && [ ! -L "$CONFIG_DIR/opencode.jsonc" ]; then
  mv "$CONFIG_DIR/opencode.jsonc" "$CONFIG_DIR/opencode.jsonc.backup"
fi

ln -sf "$LOCAL_OPENCODE" "$CONFIG_DIR/opencode.jsonc"
echo "  [ OK ] opencode config symlinked via .local/opencode.jsonc"

# Install AI SDK package for LiteLLM provider support
cd "$CONFIG_DIR"
npm install @ai-sdk/openai-compatible 2>/dev/null || true
echo "  [ OK ] AI SDK package installed"

# ---- Launchd agent for opencode web (auto-start on login) ----
LOCAL_BIN="$DOTFILES_DIR/.local/bin"
mkdir -p "$LOCAL_BIN"

WRAPPER_SRC="$DOTFILES_DIR/opencode/scripts/opencode-web.sh"
WRAPPER_DST="$LOCAL_BIN/opencode-web.sh"
ln -sf "$WRAPPER_SRC" "$WRAPPER_DST"
echo "  [ OK ] opencode web wrapper linked to $WRAPPER_DST"

mkdir -p "$HOME/Library/LaunchAgents"
PLIST_PATH="$HOME/Library/LaunchAgents/ai.opencode.web.plist"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.opencode.web</string>
    <key>ProgramArguments</key>
    <array>
        <string>$WRAPPER_DST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/opencode-web.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/opencode-web.log</string>
</dict>
</plist>
EOF

launchctl load -w "$PLIST_PATH" 2>/dev/null || true
echo "  [ OK ] launchd agent installed — opencode web starts automatically on login"

# ---- Chat workspace ----
CHAT_DIR="$HOME/Code/opencode-chat"
mkdir -p "$CHAT_DIR"
if [ ! -f "$CHAT_DIR/README.md" ]; then
  cat > "$CHAT_DIR/README.md" << 'EOF'
# opencode-chat

Placeholder folder for opencode web chat sessions.
Use this as the default workspace when you just want to chat without opening a specific project.
EOF
fi
echo "  [ OK ] Chat workspace at $CHAT_DIR"

