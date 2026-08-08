#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
set -a
source "$HOME/.env"
set +a
exec opencode serve --port 4096
