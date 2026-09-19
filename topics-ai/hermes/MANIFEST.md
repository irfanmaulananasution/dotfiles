# Hermes Agent — installation manifest

Everything installed and wired by `topics-ai/hermes/install.sh` (run via `./install.sh`, the
auto-discovered topic installer). This file is copied to `~/.hermes/MANIFEST.md`
at install time so the runtime record stays next to the config it describes.

## Core

| Item | Value |
|---|---|
| Product | [NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent) (self-improving agentic CLI) |
| Installer | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash` with `--skip-setup --non-interactive --skip-browser --skip-computer-use` |
| Install dir | `~/.hermes/` (`HERMES_HOME`) |
| Binary | `~/.hermes/hermes-agent/venv/bin/hermes` (also `~/.local/bin/hermes` on PATH) |
| Source checkout | `~/.hermes/hermes-agent` |
| Bundled skills | 60 seeded into `~/.hermes/skills/` by the installer |

## Model routing (via LiteLLM proxy)

Hermes uses a **custom endpoint** pointing at the existing LiteLLM stack
(`http://localhost:4000/v1`), authenticated with the `LITELLM_KEY` master key
from `.local/.env.local`. Nothing calls a provider directly — all traffic keeps
flowing through the LiteLLM/Phoenix observability + cost pipeline.

| Setting | Value |
|---|---|
| `model.default` | `deepseek-v4-pro-deepseek` (DeepSeek V4 Pro via your official DeepSeek key) |
| `model.provider` | `custom` |
| `model.base_url` | `http://localhost:4000/v1` |
| `model.api_key` | `$LITELLM_KEY` (written into `~/.hermes/config.yaml`, file chmod 600) |
| `agent.reasoning_effort` | `none` (DeepSeek via LiteLLM rejects the OpenAI `reasoning_effort` param with HTTP 400; DeepSeek still reasons natively) |
| Auxiliary tasks | `deepseek-v4-flash-deepseek` (V4 Flash) for `compression`, `title_generation`, `web_extract`, `session_search` |

Auxiliary tasks (vision, browser screenshots) stay on the main model — DeepSeek
is text-only, so no multimodal fallback is configured.

## MCP servers

| Name | URL | Purpose |
|---|---|---|
| `phoenix` | `http://localhost:6006/mcp` | Same Phoenix observability MCP that opencode uses; Hermes can query its own traces/sessions |

## Plugins (native Hermes plugins)

| Plugin | Source | State |
|---|---|---|
| `backsearch` | [NousResearch/hermes-plugin-backsearch](https://github.com/NousResearch/hermes-plugin-backsearch) | enabled |
| `backsearch` tools | `backsearch`, `backfetch` | **inert until `OPENREWARD_API_KEY` is set** — add it to `.local/.env.local` (prepaid key from https://openreward.ai), then re-run `topics-ai/hermes/install.sh` to copy it into `~/.hermes/.env` |

## Hub skills

| Skill | Identifier | Notes |
|---|---|---|
| docker-management | `official/devops/docker-management` | Docker/Compose management — matches the `topics-ai/litellm/` Compose stack |

Other candidates (`openai/skills/k8s`, etc.) were not available on the reachable
registries at setup time and were deliberately **not** installed from
untrusted/community sources.

## Additional utility tools

| Tool | Source | Install | How to run |
|---|---|---|---|
| Self-evolution | [NousResearch/hermes-agent-self-evolution](https://github.com/NousResearch/hermes-agent-self-evolution) | `git clone` → `~/.hermes/hermes-agent-self-evolution` + own venv at `~/.hermes/venvs/self-evolution` (`uv venv`, `uv pip install -e ".[dev]"`) | `hermes-evolve-skill --skill <name> --iterations N` |

Note: self-evolution is a **dev/research tool** (DSPy + GEPA skill/prompt
optimizer), not a runtime Hermes plugin — it has no `plugin.yaml`. Runs cost
~$2–10 in API calls each and proposes PRs for human review.

## Desktop app (Electron)

| Item | Value |
|---|---|
| Install | Built in place via `hermes desktop --build-only` → `~/.hermes/hermes-agent/apps/desktop/release/<os>-<arch>/Hermes.app` (idempotent, content-hash stamped) |
| Launch | `hermes desktop` (uses the built app; rebuilds only when the source changes) |
| macOS TCC identity | `hermes desktop --setup-tcc-identity` anchors a self-signed code-signing cert (`desktop.macos_signing_identity`) so microphone / Full Disk Access / Accessibility / Files-and-Folders grants survive rebuilds |

The desktop app is the same agent as the CLI — same config, keys, sessions,
skills, and memory. The `/Applications/Hermes.app` bundle (if present) is the
prebuilt website installer and is **not** managed by this topic; the canonical,
self-updating build lives under `apps/desktop/release/`.

## Environment keys (`.env.example`)

| Key | Required | Used by |
|---|---|---|
| `LITELLM_KEY` | yes | LiteLLM proxy auth (already required by the litellm topic) |
| `OPENREWARD_API_KEY` | optional | `backsearch` plugin (add to `.env.local` whenever you get one) |

## Files in this topic

| File | Purpose |
|---|---|
| `topics-ai/hermes/install.sh` | Idempotent installer (core + model + MCP + plugins + skills + self-evolution + desktop app) |
| `topics-ai/hermes/MANIFEST.md` | This record (copied to `~/.hermes/MANIFEST.md`) |
| `topics-ai/hermes/scripts/hermes-evolve-skill` | PATH launcher for the self-evolution tool |

## Re-run / upgrade

- Rerun everything (idempotent): `bash ~/.dotfiles/topics-ai/hermes/install.sh`
- Upgrade Hermes core: `hermes update`
- Change model/provider anytime: `hermes model` or `hermes config set model.default ...`
