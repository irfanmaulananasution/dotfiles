#!/usr/bin/env bash
#
# Setup git identity and SSH key

set -euo pipefail

# ---------- Load git credentials from .env ----------
name=""
email=""

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ -f "$HOME/.env" ]; then
  set -a
  source "$HOME/.env"
  set +a
  name="${GIT_AUTHOR_NAME:-}"
  email="${GIT_AUTHOR_EMAIL:-}"
fi

LOCAL_DIR="$DOTFILES_DIR/.local"
mkdir -p "$LOCAL_DIR"

# Symlink ~/.gitconfig → .local/gitconfig (copy template + inject identity)
if [ -n "$name" ] && [ -n "$email" ]; then
  {
    cat "$DOTFILES_DIR/git/gitconfig.symlink"
    printf "\n[user]\n\tname = %s\n\temail = %s\n" "$name" "$email"
  } > "$LOCAL_DIR/gitconfig"
  echo "  [ OK ] Git user: $name <$email>"
else
  echo "  [ .. ] Git user not set — .local/gitconfig will keep the template."
fi

if [ ! -L "$HOME/.gitconfig" ] || [ "$(readlink "$HOME/.gitconfig")" != "$LOCAL_DIR/gitconfig" ]; then
  ln -sf "$LOCAL_DIR/gitconfig" "$HOME/.gitconfig"
fi

# ---------- SSH key ----------
SSH_KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
  echo "==> Generating SSH key..."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$email" -f "$SSH_KEY"
  echo "  [ OK ] SSH key generated: $SSH_KEY.pub"
else
  echo "  [ OK ] SSH key already exists: $SSH_KEY.pub"
fi

# Ensure ssh-agent is running and key is loaded (idempotent)
eval "$(ssh-agent -s)" &>/dev/null
if [ "$(uname -s)" = "Darwin" ]; then
  ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || ssh-add "$SSH_KEY" 2>/dev/null || true
else
  ssh-add "$SSH_KEY" 2>/dev/null || true
fi

# ---------- GitHub CLI auth ----------
if command -v gh &>/dev/null; then
  if gh auth status 2>/dev/null; then
    echo "  [ OK ] Already authenticated with GitHub CLI"
  else
    echo ""
    echo "  Opening browser for GitHub CLI authentication..."
    gh auth login --web
    echo "  [ OK ] GitHub CLI authenticated"
  fi
fi

# ---------- Upload SSH key to GitHub ----------
if [ -f "$SSH_KEY.pub" ] && command -v gh &>/dev/null && gh auth status 2>/dev/null; then
  # Check if key is already registered with GitHub
  KEY_FP=$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')
  if gh ssh-key list 2>/dev/null | grep -q "$KEY_FP"; then
    echo "  [ OK ] SSH key already registered with GitHub"
  else
    echo ""
    echo "  Opening https://github.com/settings/keys ..."
    echo "  Click 'New SSH Key', paste the key below, then come back."
    echo "  (Or copy it yourself: cat $SSH_KEY.pub | pbcopy)"
    echo ""
    cat "$SSH_KEY.pub"
    echo ""
    open "https://github.com/settings/keys"
    read -rp "  Press y when done: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "  [ .. ] Skipped. Upload later from https://github.com/settings/keys"
    else
      echo "  [ OK ] SSH key uploaded to GitHub"
    fi
  fi
  echo "  GitHub user: $(gh api user --jq '.login' 2>/dev/null || echo 'unknown')"
fi

# ---------- Verify ----------
if command -v gh &>/dev/null && gh auth status 2>/dev/null; then
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "  SSH to GitHub: OK"
  else
    echo "  [ .. ] Add your public key at: https://github.com/settings/keys"
    echo "  [ .. ] Key: $(cat "$SSH_KEY.pub")"
  fi
fi