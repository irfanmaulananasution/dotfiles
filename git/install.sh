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
  ssh-keygen -t ed25519 -C "$email" -f "$SSH_KEY" -N ""
  echo "  [ OK ] SSH key generated: $SSH_KEY.pub"
else
  echo "  [ OK ] SSH key already exists: $SSH_KEY.pub"
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

# ---------- SSH key on GitHub ----------
if [ -f "$SSH_KEY.pub" ] && command -v gh &>/dev/null && gh auth status 2>/dev/null; then
  echo "  GitHub user: $(gh api user --jq '.login' 2>/dev/null || echo 'unknown')"

  # Check if SSH key works with GitHub (quiet, no prompting)
  if ssh -T -o BatchMode=yes git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "  [ OK ] SSH key already registered with GitHub"
  else
    # Try loading into agent (may prompt for passphrase if not in keychain)
    eval "$(ssh-agent -s)" &>/dev/null
    ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || true

    if ssh -T -o BatchMode=yes git@github.com 2>&1 | grep -q "successfully authenticated"; then
      echo "  [ OK ] SSH key already registered with GitHub"
    else
      echo "  [..] Uploading SSH key to GitHub..."
      KEY="$(cat "$SSH_KEY.pub")"
      if gh api user/keys --field title="$(hostname -s)" --field key="$KEY" &>/dev/null; then
        echo "  [ OK ] SSH key registered with GitHub"
      else
        echo ""
        echo "  Opening https://github.com/settings/keys ..."
        echo "  Click 'New SSH Key', paste the key below, then come back."
        echo ""
        cat "$SSH_KEY.pub"
        echo ""
        open "https://github.com/settings/keys"
        read -rp "  Press y when done: " confirm
      fi
    fi
  fi
fi