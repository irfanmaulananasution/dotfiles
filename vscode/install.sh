#!/usr/bin/env bash
#
# Install VS Code settings and extensions

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"

mkdir -p "$VSCODE_USER_DIR"

# Symlink settings (backup existing real file)
if [ -f "$VSCODE_USER_DIR/settings.json" ] && [ ! -L "$VSCODE_USER_DIR/settings.json" ]; then
  mv "$VSCODE_USER_DIR/settings.json" "$VSCODE_USER_DIR/settings.json.backup"
fi
ln -sf "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_USER_DIR/settings.json"

echo "  [ OK ] VS Code settings symlinked"

# Install recommended extensions
#
# Selection rules:
#   - Universal dev tools only (Prettier, ESLint, EditorConfig, GitLens, Copilot).
#   - Language packs cover their whole ecosystem (vscjava.vscode-java-pack
#     bundles redhat.java, java-debug, maven, gradle — listing those standalone
#     would double-install them).
#   - No project-specific add-ons (Tailwind, Go, Jupyter, LiveServer) — install
#     those per-project as needed.
#   - One icon theme (Material).
extensions=(
  "EditorConfig.EditorConfig"
  "GitHub.copilot"
  "GitHub.copilot-chat"
  "PKief.material-icon-theme"
  "bierner.markdown-preview-github-styles"
  "dbaeumer.vscode-eslint"
  "eamodio.gitlens"
  "esbenp.prettier-vscode"
  "formulahendry.auto-rename-tag"
  "ms-python.python"
  "ms-python.vscode-pylance"
  "ms-vscode-remote.remote-ssh"
  "vscjava.vscode-java-pack"
  "vscodevim.vim"
)

if command -v code &>/dev/null; then
  for ext in "${extensions[@]}"; do
    code --install-extension "$ext" --force 2>/dev/null || true
  done
  echo "  [ OK ] VS Code extensions installed ($(code --list-extensions | wc -l | tr -d ' '))"
else
  echo "  [ .. ] 'code' CLI not in PATH. Open VS Code, run Cmd+Shift+P -> 'Shell Command: Install code command in PATH', then re-run this script."
fi