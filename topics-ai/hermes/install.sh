#!/usr/bin/env bash
#
# topics-ai/hermes/install.sh - Install & configure NousResearch Hermes Agent
#
# Everything the agent needs is wired here, idempotently:
#   1. Hermes Agent core (official installer -> ~/.hermes)      [skip-setup]
#   2. Model routing -> local LiteLLM proxy (localhost:4000/v1) with the
#      LITELLM_KEY master key; DeepSeek V4 Pro default, V4 Flash for
#      text-only auxiliary tasks.
#   3. Phoenix MCP server (same endpoint opencode uses) so Hermes can
#      query its own observability data.
#   4. Plugins: NousResearch hermes-plugin-backsearch.
#   5. Hub skill(s): official/devops/docker-management.
#   6. Utility: NousResearch hermes-agent-self-evolution (clone + venv).
#   7. Desktop app (Electron): built via `hermes desktop --build-only` so
#      `hermes desktop` launches without a first-run build; on macOS a
#      self-signed code-signing identity is anchored so TCC grants survive
#      rebuilds.
#   8. Copies topics-ai/hermes/MANIFEST.md -> ~/.hermes/MANIFEST.md as a runtime record.
#
# Run manually, or automatically via ./install.sh (auto-discovered topic).

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# The repository-local env file is the only supported source of secrets.
ENV_SRC="$DOTFILES_DIR/.local/.env.local"
if [ ! -f "$ENV_SRC" ]; then
  echo "  [FAIL] $ENV_SRC not found. Run script/bootstrap first."
  exit 1
fi
chmod 600 "$ENV_SRC"
set -a; source "$ENV_SRC"; set +a

if [ -z "${LITELLM_KEY:-}" ]; then
  echo "  [FAIL] LITELLM_KEY is not set in $ENV_SRC."
  echo "         Hermes is wired through the LiteLLM proxy, which requires it."
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Core install
# ---------------------------------------------------------------------------
hermes_bin() {
  if [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then
    printf '%s' "$HERMES_HOME/hermes-agent/venv/bin/hermes"
  elif command -v hermes >/dev/null 2>&1; then
    command -v hermes
  else
    printf ''
  fi
}

HERMES_BIN="$(hermes_bin)"
if [ -z "$HERMES_BIN" ]; then
  echo "==> Installing Hermes Agent (official installer, --skip-setup)..."
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  curl -fsSL "https://hermes-agent.nousresearch.com/install.sh" -o "$tmp_dir/hermes-install.sh"
  bash "$tmp_dir/hermes-install.sh" --skip-setup --non-interactive --skip-browser --skip-computer-use
  trap - EXIT
  rm -rf "$tmp_dir"
  HERMES_BIN="$(hermes_bin)"
  if [ -z "$HERMES_BIN" ]; then
    echo "  [FAIL] Hermes installed but the binary was not found."
    exit 1
  fi
fi
echo "  [ OK ] Hermes Agent binary: $HERMES_BIN"

run() { # hermes config helper (silent unless it fails)
  if ! "$HERMES_BIN" config set "$1" "$2" --force >/dev/null 2>&1; then
    echo "  [WARN] \`hermes config set $1 $2\` failed"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2. Model routing -> LiteLLM (custom endpoint), Pro default + Flash aux
# ---------------------------------------------------------------------------
LITELLM_BASE_URL="${LITELLM_BASE_URL:-http://localhost:4000/v1}"
MAIN_MODEL="deepseek-v4-pro-deepseek"
AUX_MODEL="deepseek-v4-flash-deepseek"
echo "==> Wiring model to LiteLLM proxy ($LITELLM_BASE_URL)..."

run model.default "$MAIN_MODEL"
run model.provider "custom"
run model.base_url "$LITELLM_BASE_URL"
run model.api_key "$LITELLM_KEY"

# Text-only auxiliary tasks -> flash route on the same endpoint (provider
# "main" reuses the custom endpoint + key above). Vision is left on "auto"
# (routes to main) since DeepSeek is text-only.
for task in compression title_generation web_extract session_search; do
  run "auxiliary.$task.provider" "main"
  run "auxiliary.$task.model" "$AUX_MODEL"
done
# DeepSeek via LiteLLM rejects the OpenAI "reasoning_effort" param (HTTP 400:
# "openai does not support parameters: ['reasoning_effort']"), so agent-side
# reasoning effort is disabled. This only turns off the explicit effort knob;
# DeepSeek still reasons natively.
run agent.reasoning_effort "none"
echo "  [ OK ] model.default=$MAIN_MODEL, auxiliary=$AUX_MODEL, reasoning_effort=none"

# The LiteLLM master key now lives in the machine-local config file; harden it.
chmod 600 "$HERMES_HOME/config.yaml" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Phoenix MCP (observability) - same endpoint as opencode's phoenix MCP
# ---------------------------------------------------------------------------
echo "==> Adding Phoenix MCP server..."
if ! run mcp_servers.phoenix.url "http://localhost:6006/mcp"; then
  echo "  [WARN] Could not set mcp_servers.phoenix.url — add it manually to $HERMES_HOME/config.yaml"
fi

# ---------------------------------------------------------------------------
# 4. Plugins
# ---------------------------------------------------------------------------
echo "==> Installing plugins..."
# backsearch - official Nous plugin (inert until OPENREWARD_API_KEY is set).
# NB: `plugins list` exits non-zero even on success, so capture output before
# testing (avoid pipefail false-negatives).
set +e
backsearch_hits="$("$HERMES_BIN" plugins list 2>&1 | grep -ci backsearch)"
set -e
if [ "${backsearch_hits:-0}" -gt 0 ]; then
  echo "  [ OK ] plugin: backsearch (already installed)"
else
  if "$HERMES_BIN" plugins install "NousResearch/hermes-plugin-backsearch" --enable >/dev/null 2>&1; then
    echo "  [ OK ] plugin: backsearch"
  else
    echo "  [WARN] backsearch plugin install failed — install manually:"
    echo "         $HERMES_BIN plugins install NousResearch/hermes-plugin-backsearch --enable"
  fi
fi

# Optional key for backsearch (from .env.local -> ~/.hermes/.env), never required.
upsert_env() {
  local key="$1" val="$2"
  if [ -z "$val" ]; then return 0; fi
  local env_file="$HERMES_HOME/.env"
  touch "$env_file"; chmod 600 "$env_file"
  if grep -q "^${key}=" "$env_file" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$env_file" && rm -f "$env_file.bak"
  else
    printf '\n%s=%s\n' "$key" "$val" >> "$env_file"
  fi
}
upsert_env "OPENREWARD_API_KEY" "${OPENREWARD_API_KEY:-}"

# ---------------------------------------------------------------------------
# 5. Hub skills (curated, official)
# ---------------------------------------------------------------------------
echo "==> Installing hub skills..."
install_skill() {
  local ident="$1"
  if "$HERMES_BIN" skills list 2>/dev/null | grep -q "$ident"; then
    echo "  [ OK ] skill: $ident (already installed)"
  elif "$HERMES_BIN" skills install "$ident" --yes >/dev/null 2>&1; then
    echo "  [ OK ] skill: $ident"
  else
    echo "  [WARN] skill install failed: $ident"
  fi
}
install_skill "official/devops/docker-management"

# ---------------------------------------------------------------------------
# 6. hermes-agent-self-evolution utility (research/dev tool, NOT a runtime
#    plugin — has no plugin.yaml). Cloned into ~/.hermes with its own venv.
# ---------------------------------------------------------------------------
echo "==> Setting up hermes-agent-self-evolution..."
SE_REPO="$HERMES_HOME/hermes-agent-self-evolution"
SE_VENV="$HERMES_HOME/venvs/self-evolution"
if [ ! -d "$SE_REPO/.git" ]; then
  git clone --depth 1 "https://github.com/NousResearch/hermes-agent-self-evolution.git" "$SE_REPO" >/dev/null 2>&1 \
    && echo "  [ OK ] cloned hermes-agent-self-evolution" \
    || echo "  [WARN] could not clone hermes-agent-self-evolution"
fi
if [ -d "$SE_REPO/.git" ] && [ ! -x "$SE_VENV/bin/python" ]; then
  uv venv "$SE_VENV" --python 3.11 >/dev/null 2>&1 || true
  uv pip install --python "$SE_VENV/bin/python" -e ".[dev]" --directory "$SE_REPO" >/dev/null 2>&1 \
    && echo "  [ OK ] self-evolution venv ready" \
    || echo "  [WARN] self-evolution deps install incomplete (see: $SE_VENV)"
fi
# Launcher on PATH (~/.local/bin is on PATH via dotfiles)
LOCAL_BIN="$DOTFILES_DIR/.local/bin"
mkdir -p "$LOCAL_BIN"
if [ -f "$DOTFILES_DIR/topics-ai/hermes/scripts/hermes-evolve-skill" ]; then
  ln -sf "$DOTFILES_DIR/topics-ai/hermes/scripts/hermes-evolve-skill" "$LOCAL_BIN/hermes-evolve-skill"
  echo "  [ OK ] launcher: hermes-evolve-skill -> $LOCAL_BIN"
fi

# ---------------------------------------------------------------------------
# 7. Desktop app (Electron) build
# ---------------------------------------------------------------------------
# Build the native desktop app in place (apps/desktop/release/<os>-<arch>/…)
# so `hermes desktop` launches without a first-run npm install + Electron
# package step. Idempotent (content-hash stamp). Best-effort: a failed build
# must not abort the topic — the CLI still works and `hermes desktop` will
# simply build on first launch.
echo "==> Building Hermes Desktop (Electron) app..."
if "$HERMES_BIN" desktop --build-only >/dev/null 2>&1; then
  echo "  [ OK ] desktop app built (run \`hermes desktop\` to launch)"
else
  echo "  [WARN] desktop build failed — run \`hermes desktop\` manually to build on first launch"
fi

# macOS: anchor a self-signed code-signing identity so TCC grants (microphone,
# Full Disk Access, Accessibility, Files and Folders) survive app rebuilds.
# Idempotent; harmless to skip. (The CLI itself is a no-op off macOS.)
if [ "$(uname -s)" = "Darwin" ]; then
  if "$HERMES_BIN" desktop --setup-tcc-identity >/dev/null 2>&1; then
    echo "  [ OK ] desktop TCC signing identity"
  else
    echo "  [WARN] could not set up desktop TCC signing identity (see \`hermes desktop --setup-tcc-identity\`)"
  fi
fi

# ---------------------------------------------------------------------------
# 8. Manifest copy (runtime record)
# ---------------------------------------------------------------------------
if [ -f "$DOTFILES_DIR/topics-ai/hermes/MANIFEST.md" ]; then
  cp "$DOTFILES_DIR/topics-ai/hermes/MANIFEST.md" "$HERMES_HOME/MANIFEST.md"
  echo "  [ OK ] manifest copied to $HERMES_HOME/MANIFEST.md"
fi

# ---------------------------------------------------------------------------
echo ""
echo "==> Hermes topic installer finished."
echo "    Restart your terminal (or re-source ~/.zshrc) so 'hermes' is on PATH."
echo "    Verify with:  hermes doctor"
echo "    Runtime record: $HERMES_HOME/MANIFEST.md"
