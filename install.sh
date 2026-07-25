#!/usr/bin/env bash
#
# install.sh - One-command setup for a new Mac
# Usage: cd ~/.dotfiles && ./install.sh

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"

echo "==> Setting up your Mac..."

# ---------- Xcode Command Line Tools ----------
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools (may prompt for sudo)..."
  xcode-select --install
  for _ in $(seq 1 60); do
    if xcode-select -p &>/dev/null; then break; fi
    echo "  waiting..."
    sleep 5
  done
  if ! xcode-select -p &>/dev/null; then
    echo "[FAIL] Xcode CLI Tools timed out. Run 'xcode-select --install' manually."
    exit 1
  fi
fi

# ---------- Homebrew ----------
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  BREW_COMMIT="ca0130bd52235f2fcb2bf23cfdda004bc5d250c1"
  curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${BREW_COMMIT}/install.sh" -o /tmp/homebrew-install.sh
  if [ -f /tmp/homebrew-install.sh ]; then
    /bin/bash /tmp/homebrew-install.sh
    rm -f /tmp/homebrew-install.sh
  else
    echo "[FAIL] Failed to download Homebrew installer"
    exit 1
  fi
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ---------- Oh My Zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "==> Installing Oh My Zsh..."
  OMZ_COMMIT="b37dd49ca5bfe0d99b35607637152cb8cc8b29d7"
  curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OMZ_COMMIT}/tools/install.sh" -o /tmp/omz-install.sh
  if [ -f /tmp/omz-install.sh ]; then
    sh /tmp/omz-install.sh "" --unattended
    rm -f /tmp/omz-install.sh
  else
    echo "[FAIL] Failed to download Oh My Zsh installer"
    exit 1
  fi
fi

# (Bootstrap handles .zshrc symlink via .local/ pattern)

# ---------- Homebrew Bundle ----------
echo "==> Installing Homebrew packages..."
brew update
brew bundle --file "$DOTFILES_DIR/Brewfile" || true

# ---------- Symlink dotfiles ----------
echo "==> Symlinking dotfiles..."
bash "$DOTFILES_DIR/script/bootstrap"

# ---------- Create directories ----------
mkdir -p "$HOME/Code"

# ---------- Topic installers ----------
while IFS= read -r -d '' installer; do
  topic=$(basename "$(dirname "$installer")")
  echo "==> Running $topic topic installer..."
  bash "$installer" </dev/tty || echo "  [WARN] $topic topic installer failed (continuing)"
done < <(find -H "$DOTFILES_DIR" -mindepth 2 -maxdepth 3 -name 'install.sh' -not -path '*/script/*' -not -path '*/node_modules/*' -print0)

# iTerm2 restore
if [ -f "$DOTFILES_DIR/iterm2/restore.sh" ]; then
  echo "==> Restoring iTerm2 preferences..."
  bash "$DOTFILES_DIR/iterm2/restore.sh"
fi

# ---------- Verify GitHub connection ----------
echo ""
echo "==> Verification"
if command -v gh &>/dev/null && gh auth status 2>/dev/null; then
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "  SSH to GitHub: OK"
  else
    echo "  [ .. ] SSH key not configured yet. Run 'ssh -T git@github.com' after uploading."
  fi
fi

echo ""
echo "  All done! Restart your terminal or run: source ~/.zshrc"
