#!/usr/bin/env bash
#
# install.sh - One-command setup for a new Mac
# Usage: cd ~/.dotfiles && ./install.sh

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "[FAIL] This installer supports macOS only."
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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
  curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${BREW_COMMIT}/install.sh" -o "$tmp_dir/homebrew-install.sh"
  /bin/bash "$tmp_dir/homebrew-install.sh"
  brew_path="$(command -v brew || true)"
  if [ -z "$brew_path" ]; then
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$candidate" ]; then brew_path="$candidate"; break; fi
    done
  fi
  if [ -z "$brew_path" ]; then
    echo "[FAIL] Homebrew installation completed but brew was not found."
    exit 1
  fi
  brew_prefix="$(dirname "$(dirname "$brew_path")")"
  brew_shellenv_line="eval \"\$($brew_path shellenv)\""
  grep -Fqx "$brew_shellenv_line" "$HOME/.zprofile" 2>/dev/null || \
    printf '%s\n' "$brew_shellenv_line" >> "$HOME/.zprofile"
  eval "$($brew_path shellenv)"
fi

# ---------- Oh My Zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "==> Installing Oh My Zsh..."
  OMZ_COMMIT="b37dd49ca5bfe0d99b35607637152cb8cc8b29d7"
  curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${OMZ_COMMIT}/tools/install.sh" -o "$tmp_dir/omz-install.sh"
  sh "$tmp_dir/omz-install.sh" "" --unattended
fi

# (Bootstrap handles .zshrc symlink via .local/ pattern)

# ---------- Homebrew Bundle ----------
echo "==> Installing Homebrew packages..."
brew update
brew bundle --file "$DOTFILES_DIR/Brewfile"

# ---------- Symlink dotfiles ----------
echo "==> Symlinking dotfiles..."
bash "$DOTFILES_DIR/script/bootstrap"

# ---------- Create directories ----------
mkdir -p "$HOME/Code"

# ---------- Validate .env.local ----------
if [ -f "$HOME/.env" ]; then
  chmod 600 "$DOTFILES_DIR/.local/.env.local"
  set -a
  source "$HOME/.env"
  set +a

  if [ "${GIT_AUTHOR_NAME:-}" = "Your Name" ] || [ "${GIT_AUTHOR_EMAIL:-}" = "your@email.com" ] || [ -z "${GIT_AUTHOR_NAME:-}" ] || [ -z "${GIT_AUTHOR_EMAIL:-}" ]; then
    echo "[FAIL] GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL still have placeholder or empty values."
    echo "       Edit $DOTFILES_DIR/.local/.env.local and set your real name and email."
    exit 1
  fi

  if [ -z "${PERSONAL_OPENCODE_API_KEY:-}" ] || [ "${PERSONAL_OPENCODE_API_KEY#sk-}" = "" ]; then
    echo "[FAIL] PERSONAL_OPENCODE_API_KEY is empty or still a placeholder."
    echo "       Edit $DOTFILES_DIR/.local/.env.local and set your real API key."
    exit 1
  fi

  echo "  [ OK ] .env.local validated"
fi

# ---------- Topic installers ----------
# Run in two phases: topics that DON'T need Docker first, then topics that
# explicitly declare `NEEDS_DOCKER=1` (run only after rancher/install.sh has
# brought the Docker engine up). Each installer is allowed to fail without
# aborting the whole bootstrap.
run_phase() {
  local needs_docker="$1"
  local installer topic has_docker
  while IFS= read -r -d '' installer; do
    if grep -q '^NEEDS_DOCKER=1' "$installer" 2>/dev/null; then
      has_docker=1
    else
      has_docker=0
    fi
    [ "$has_docker" != "$needs_docker" ] && continue
    topic=$(basename "$(dirname "$installer")")
    echo "==> Running $topic topic installer..."
    if [ -r /dev/tty ]; then
      bash "$installer" </dev/tty || echo "  [WARN] $topic installer failed — continuing"
    else
      bash "$installer" || echo "  [WARN] $topic installer failed — continuing"
    fi
  done < <(find -H "$DOTFILES_DIR" -mindepth 2 -maxdepth 3 -name 'install.sh' -not -path '*/script/*' -not -path '*/node_modules/*' -not -path '*/rancher/*' -print0)
}

run_phase 0
echo "==> Ensuring Docker engine (Rancher Desktop) is ready..."
bash "$DOTFILES_DIR/rancher/install.sh"
# The gate starts Rancher in a subprocess; expose its CLI dir so Docker-dependent
# topic installers (phase 1) can find `docker` in their own fresh shells.
if [ -d "$HOME/.rd/bin" ]; then
  export PATH="$HOME/.rd/bin:$PATH"
fi
run_phase 1

# iTerm2 restore
if [ -f "$DOTFILES_DIR/iterm2/restore.sh" ]; then
  echo "==> Restoring iTerm2 preferences..."
  bash "$DOTFILES_DIR/iterm2/restore.sh"
fi

# ---------- Verify GitHub connection ----------
echo ""
echo "==> Verification"
if command -v gh &>/dev/null && gh auth status 2>/dev/null; then
  echo "  GitHub CLI: OK"
fi

echo ""
echo "  All done! Restart your terminal or run: source ~/.zshrc"
