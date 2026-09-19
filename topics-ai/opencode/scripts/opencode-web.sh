#!/usr/bin/env bash
for brew_bin in /opt/homebrew/bin /usr/local/bin; do
  [ -d "$brew_bin" ] && PATH="$brew_bin:$PATH"
done
export PATH
set -a
if [ ! -r "$HOME/.env" ]; then
  printf '%s\n' "opencode-web: $HOME/.env is missing" >&2
  exit 1
fi
source "$HOME/.env"
set +a
if ! command -v opencode >/dev/null 2>&1; then
  printf '%s\n' "opencode-web: opencode is not on PATH" >&2
  exit 1
fi
exec opencode serve --port 4096
