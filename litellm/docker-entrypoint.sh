#!/usr/bin/env bash
set -e

if [ -n "$OTEL_ENDPOINT" ]; then
  sed -i "s|otel_endpoint:.*|otel_endpoint: \"$OTEL_ENDPOINT\"|" /app/config.yaml
fi

exec python3 -c "
import sys; sys.path.insert(0, '/app')
import monkey_patch; monkey_patch.apply()
from litellm import run_server
args = [a for a in sys.argv[1:] if a != '--']
sys.argv = ['litellm'] + args
run_server()
" -- "$@"
