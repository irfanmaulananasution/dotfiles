# Dotfiles conventions

## `.local/` pattern
- **Tracked files** in the repo are templates/source of truth.
- **Generated files** go in `.local/` (gitignored), then are **symlinked** to their expected path.
- Example: `.local/gitconfig` ← `repo/git/gitconfig.symlink`, symlinked to `~/.gitconfig`.
- Run `script/bootstrap` to copy all `*.symlink` files into `.local/` and create symlinks.

## Secrets
- **Single source of truth**: `.local/.env.local` (gitignored, created from `.env.example`).
- Symlinked to `~/.env`, sourced by `.zshrc` at shell startup.
- **Real secrets never live outside `.local/`.** Per-service env files are generated under `.local/`:
  - `.local/litellm.env.local` → passed to Docker Compose via `--env-file` (no `litellm/.env` is created or left behind).
  - `.local/k8s.env.local` → copied to a **temporary** `k8s/.env` only for the kustomize apply, then deleted.
- Never prompt the user to manually fill a second env file — extract from `.local/.env.local`.

## Topic installers
- Each topic directory can have an `install.sh` that runs automatically during bootstrap.
- Must be idempotent.

## Naming
- Generated env files in `.local/` use the `.local` suffix: `foo.env.local`.
- Symlinks point from the expected location back to `.local/`.

## LiteLLM + Phoenix observability stack
See `litellm/README.md` for the full guide (architecture, features/evaluation pipeline, and model/provider changes). Quick recap:

- **Models** are defined in `litellm/config.yaml` under `model_list`. **Naming convention: `model_name = <real_upstream_model_name>-<provider>`** (e.g. `deepseek-v4-pro-opencodego`, `deepseek-v4-pro-deepseek`). One entry per model. Each provider gets its own clearly-marked section (big comment banner) with its own `api_base` + `api_key`.
- **Pricing** lives in two places and both must be updated when models change:
  1. `litellm/otel_utils.py` — `MODEL_PRICING` dict (per-1M-token prices, shared source read by both `CostSpanProcessor` in litellm and the old enrich path). Price changes here only require `docker restart litellm` (no rebuild).
  2. Phoenix `generative_models` + `token_prices` tables — seeded idempotently from `litellm/db/pricing.sql` (auto-run by `litellm/install.sh`). These drive Phoenix's `costSummary` in the dashboard. The `name_pattern` column must be a regex that matches the span's `llm.model_name` attribute. Update both `MODEL_PRICING` and `pricing.sql` when models change.
- **Spans record the UPSTREAM model name** (e.g. `deepseek-v4-pro`), not the LiteLLM route name (`deepseek-v4-pro-deepseek`). So `MODEL_PRICING` keys and Phoenix `name_pattern`s are keyed on the **real model name** — they're shared across routes/providers of the same model.
- **The enrich sidecar** (`docker compose` service `enrich`) runs a slim `enrich_spans.py --watch` every 30s: cursor-gated token promotion to trace roots + session grouping. Cost/token computation is now done at the request path by `CostSpanProcessor` (layer 3 in `monkey_patch.py`) — the enrich sidecar no longer computes costs or writes `cache_hit_rate`/`cost_efficiency`/`latency_s` annotations.
- **Evaluators**: the `task_accuracy` LLM-as-judge evaluator is registered in Phoenix via `litellm/db/evaluators.sql` (idempotent; auto-seeded by `litellm/install.sh` after the stack is healthy). The judge model is the DeepSeek official API configured through a custom provider (`deepseek-official-eval`), created by `install.sh` via the Phoenix GraphQL API (its key is encrypted server-side, so it can't be seeded via SQL) — it does NOT route through litellm. `litellm/scripts/evaluate_accuracy.py` writes `task_accuracy` annotations directly to `span_annotations`. The Evaluators page lists registered evaluator configs; span annotations are visible on span detail.
- When changing the upstream provider:
  - Update `api_base` + `api_key` in `config.yaml` for every model in that provider section.
  - Update `docker-compose.yml` env vars (`OTEL_ENDPOINT`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `PERSONAL_OPENCODE_API_KEY`, `PERSONAL_DEEPSEEK_API_KEY`).
  - Run `script/bootstrap` then `litellm/install.sh` to regenerate env files and rebuild containers.

## Due diligence — repo conventions to follow
When making any change in this repo, follow these rules. If you discover a new convention or pattern, add it here.

### File placement
- **Templates go in the repo root or topic dirs.** Never commit generated or machine-local files.
- **Generated/local files go in `.local/`** (gitignored), then symlinked to their expected path. Examples: `.local/.zshrc`, `.local/gitconfig`, `.local/litellm.env.local`.
- **Never mutate `~/.zshrc` directly** — edit `zsh/` topic files or `.zshrc` (the tracked one), then run `script/bootstrap`.

### Environment variables and secrets
- **`.env.example` is the canonical template.** New secrets/env vars must be added there first.
- **`.local/.env.local` is the runtime source** (gitignored). `script/bootstrap` copies `.env.example` → `.local/.env.local` if it doesn't exist.
- **Per-service env files** are generated from `.local/.env.local` by their respective `install.sh`/`setup.sh` scripts and **never persist outside `.local/`**: `litellm/.env` is not created at all (Compose uses `--env-file`), and `k8s/.env` exists only transiently during apply. Never create or symlink secret files into repo scope.
- **All env file names** generated in `.local/` use the `.local` suffix (e.g. `foo.env.local`).

### Installers
- Every topic dir that needs setup must have an `install.sh`. It must be idempotent.
- `install.sh` scripts should source `.local/.env.local` for secrets rather than prompting the user.
- Run `script/bootstrap` after making changes to `.symlink` files or `install.sh` files.

### Docker Compose (litellm stack)
- The stack is defined in `litellm/docker-compose.yml` with 5 services: `postgres`, `phoenix`, `litellm`, `enrich`, `eval-accuracy`.
- Secrets are passed to Compose via `--env-file .local/litellm.env.local` (generated by `litellm/install.sh` from `.local/.env.local`). No `litellm/.env` file is created.
- Rebuild with `docker compose --env-file .local/litellm.env.local build --pull && docker compose --env-file .local/litellm.env.local up -d` (or run `litellm/install.sh`).

### Kubernetes (k8s stack)
- Manifest files are in `k8s/`. `kustomization.yaml` ties them together with a `secretGenerator` that reads `k8s/.env`.
- `k8s/setup.sh` generates `.local/k8s.env.local`, copies it to a **temporary** `k8s/.env`, runs `kubectl apply -k k8s/`, then deletes the temp `.env`. Secrets never persist outside `.local/`.
- Run `k8s/setup.sh` before `kubectl apply -k k8s/` (or let setup.sh do both).

### Config files and formatting
- **`opencode/opencode.jsonc`**: model provider config for opencode. One provider group per upstream provider (e.g. `opencodego`, `deepseek-official`), each pointing at the LiteLLM proxy (`http://localhost:4000/v1`) unless it's a direct fallback. Model ids must match the LiteLLM `model_name` (e.g. `deepseek-v4-pro-opencodego`). **Avoid naming a group `deepseek`** — it collides with opencode's built-in DeepSeek provider (models.dev catalog auto-merges `deepseek-chat`/`deepseek-reasoner`/`deepseek-v4-*`). Use a unique id (e.g. `deepseek-official`) and add the colliding built-in to `disabled_providers`. The built-in `opencode` provider is whitelisted to only `deepseek-v4-flash-free`.
- **`install.sh` (root)**: iterates over all topic `install.sh` files. New topic dirs with an `install.sh` are auto-discovered.

### Model/pricing changes (most important for AI agents)
When adding, removing, or changing LLM models or providers:
1. Update model entries in `litellm/config.yaml` (one entry per model, `model_name = <real_model>-<provider>`, placed in the right provider section).
2. Update `MODEL_PRICING` dict in `litellm/otel_utils.py`.
3. Insert/update `generative_models` + `token_prices` rows in Postgres (Phoenix's DB) using direct SQL. The `name_pattern` must regex-match the span's `llm.model_name` (the **upstream** model name).
4. Update `opencode/opencode.jsonc` if the model should be available in opencode (add to the matching provider group).
5. Rebuild and restart: `docker compose --env-file .local/litellm.env.local up -d --build enrich` (or run `litellm/install.sh`).

### Observability stack (new rules after WS refactor)

- **Cost/token computation is layer-3 (request path).** `CostSpanProcessor` (patch #7 in `monkey_patch.py`) writes `llm.token_count.*` (including costs) synchronously on the request thread. The enrich sidecar does NOT compute costs anymore.
- **Enrich is slim: promotion + sessions only.** `enrich_spans.py` only does `_promote_tokens_to_roots` + `_assign_sessions`, both cursor-gated. It does NOT write `input`/`output`/`cost_efficiency`/`cache_hit_rate`/`latency_s`.
- **Cursor table (`enrich_cursor`).** Cursor-gated lookups are the norm — never do a full seq scan on `spans`. Each process has a cursor row (`enrich-promotion`, `enrich-sessions`, `eval-accuracy`). Queries use `WHERE s.id > %(wm)s`.
- **Never write top-level `input`/`output` attributes.** These duplicate `llm.input_messages`/`llm.output_messages` and waste ~354 KB per big span. `CostSpanProcessor` doesn't write them; enrich doesn't either.
- **Pricing source is `otel_utils.py`.** `MODEL_PRICING` is the single source for cost computation (used by `CostSpanProcessor`). Two places to update: `otel_utils.MODEL_PRICING` + `db/pricing.sql`. Price-only changes need only `docker restart litellm` (no rebuild).
- **`parse_indexed_messages` handles flat dotted-key JSONB.** `otel_utils.parse_indexed_messages()` converts `{"0.message.role": ..., "0.message.content": ...}` to `[{"role": ..., "content": ...}]` with numeric index sorting. Use this anywhere messages need reconstructing from span attributes.
