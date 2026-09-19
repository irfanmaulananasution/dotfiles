#!/usr/bin/env bash
#
# topics-ai/skills/install.sh — cross-tool AI skill library
#
# One canonical, tracked directory of skills that EVERY agent tool can read:
#
#   1. symlink  ~/.agents/skills -> <repo>/topics-ai/skills/library
#      ~/.agents/skills is the cross-tool convention path, scanned natively by
#      OpenCode (alongside ~/.config/opencode/skills and ~/.claude/skills).
#   2. point Hermes at the same dir via skills.external_dirs (Hermes' own
#      ~/.hermes/skills stays primary and wins on any name collision).
#   3. validate every library skill against the Agent Skills spec.
#
# Upstream/hub skills are deliberately NOT vendored here. Their provenance is
# recorded in ./manifest and Hermes installs them (see topics-ai/hermes/install.sh).
#
# Auto-discovered and run by ./install.sh. Safe to re-run (idempotent).

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
LIBRARY="$DOTFILES_DIR/topics-ai/skills/library"
VALIDATOR="$DOTFILES_DIR/topics-ai/skills/scripts/validate-skills.py"
AGENTS_DIR="$HOME/.agents"
AGENTS_SKILLS="$AGENTS_DIR/skills"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# ---------------------------------------------------------------------------
# 1. Cross-tool symlink: ~/.agents/skills -> library/
# ---------------------------------------------------------------------------
echo "==> Wiring cross-tool skill dir..."
mkdir -p "$AGENTS_DIR" "$LIBRARY"
if [ -L "$AGENTS_SKILLS" ]; then
  if [ "$(readlink "$AGENTS_SKILLS")" = "$LIBRARY" ]; then
    echo "  [ OK ] $AGENTS_SKILLS -> $LIBRARY"
  else
    ln -sfn "$LIBRARY" "$AGENTS_SKILLS"
    echo "  [ OK ] repointed $AGENTS_SKILLS -> $LIBRARY"
  fi
elif [ -e "$AGENTS_SKILLS" ]; then
  # A real directory here would be someone else's skills — never clobber it.
  echo "  [WARN] $AGENTS_SKILLS exists and is NOT a symlink — left untouched."
  echo "         Move it aside and re-run to link the shared library."
else
  ln -s "$LIBRARY" "$AGENTS_SKILLS"
  echo "  [ OK ] created $AGENTS_SKILLS -> $LIBRARY"
fi

# ---------------------------------------------------------------------------
# 2. Hermes: scan the shared dir in addition to its own skills dir.
#    Absolute path on purpose: config.yaml is machine-local, and `~` expansion
#    is not guaranteed for this key.
# ---------------------------------------------------------------------------
hermes_bin() {
  if [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then
    printf '%s' "$HERMES_HOME/hermes-agent/venv/bin/hermes"
  elif command -v hermes >/dev/null 2>&1; then
    command -v hermes
  fi
}
HERMES_BIN="$(hermes_bin || true)"

if [ -n "$HERMES_BIN" ]; then
  echo "==> Pointing Hermes at the shared dir (skills.external_dirs)..."
  # A list literal — `hermes config set` coerces it via yaml.safe_load, so this
  # stores a real YAML list, not a string.
  if "$HERMES_BIN" config set skills.external_dirs "[\"$AGENTS_SKILLS\"]" --force >/dev/null 2>&1; then
    echo "  [ OK ] skills.external_dirs = [\"$AGENTS_SKILLS\"]"
  else
    echo "  [WARN] could not set skills.external_dirs — set it manually:"
    echo "         $HERMES_BIN config set skills.external_dirs '[\"$AGENTS_SKILLS\"]' --force"
  fi
else
  echo "==> [skip] Hermes not installed yet — skills.external_dirs not set."
  echo "           Re-run this after topics-ai/hermes/install.sh."
fi

# ---------------------------------------------------------------------------
# 3. Validate library skills (a name/dir mismatch silently hides a skill from
#    OpenCode, which is how `adhder-assistant` would have failed).
# ---------------------------------------------------------------------------
echo "==> Validating library skills..."
if command -v python3 >/dev/null 2>&1 && [ -f "$VALIDATOR" ]; then
  python3 "$VALIDATOR" "$LIBRARY" || echo "  [WARN] validation reported problems (above)"
else
  echo "  [skip] python3 or validator unavailable"
fi

echo "  [ OK ] topics-ai/skills done"
