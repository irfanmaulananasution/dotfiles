# LiteLLM + Phoenix observability stack

A Docker Compose stack that turns a plain LLM proxy into a **self-observing AI
flow**: every opencode request through the LiteLLM proxy gets traced into Phoenix,
enriched with cache/cost/latency/accuracy signals, and grouped into sessions.

What you get beyond a normal proxy:

- **Cache hit/miss tracking** — see how much of each prompt was served from
  DeepSeek's context cache.
- **Cost** — cache-discounted USD cost per call, computed in real time on the request path.
- **Latency** — end-to-end response time per call (viewable on span details).
- **Accuracy** — an independent LLM judge rates how well the agent did the task.
- **Sessions** — traces grouped into conversations in the Phoenix UI.

## Architecture

```
opencode ──► litellm (localhost:4000) ──► upstream (opencode.ai/zen/go/v1, api.deepseek.com)
                 │  OTLP spans (CostSpanProcessor writes llm.token_count.* on request path)
                 ▼
             phoenix (localhost:6006) ──► postgres
                 ▲                        ▲
                 │  cursor-gated promotion │  cursor-gated sampling
                 │  + sessions (30s)       │  LLM-as-judge (30 min, 5%)
             enrich sidecar            eval-accuracy sidecar
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| `postgres` | 5432 (internal) | Stores Phoenix traces + spans |
| `phoenix` | 6006 (UI), 4317 (OTLP gRPC) | Arize Phoenix observability |
| `litellm` | 4000 | LLM proxy routing to upstream API |
| `enrich` | — | Sidecar: cursor-gated token promotion & sessions (30s watch, `enrich_cursor` watermark) |
| `eval-accuracy` | — | Sidecar: LLM-as-judge accuracy annotations (30 min watch, `enrich_cursor` watermark) |

---

## Features & evaluation pipeline

Each feature below covers **what it gives you**, **how it works**, and **how to
verify** it.

### 1. Cache hit / miss tracking

**What it gives you:** the proxy records how many prompt tokens were served from
DeepSeek's context cache (`prompt_cache_hit_tokens`) vs. freshly processed
(`prompt_cache_miss_tokens`). Visible in the proxy response and on each Phoenix span
as `llm.token_count.prompt_details.cache_read` / `cache_miss` / `cache_write`.

**Why it matters:** cached tokens are billed ~100× cheaper than misses. Tracking the
hit rate tells you whether your prompts (system prompts, tool definitions, long
contexts) are stable enough to benefit from caching.

**How it works:**

- DeepSeek's API returns cache fields on the `usage` object. LiteLLM's streaming
  aggregation and serialization historically dropped them.
- `litellm/monkey_patch.py` patches LiteLLM (applied at container startup via
  `litellm/docker-entrypoint.sh`) so the fields survive: it adds them to
  `litellm.utils.Usage`, preserves `prompt_tokens_details.cached_tokens`, and carries
  them through both streaming usage-reconstruction paths.
- `CostSpanProcessor` in `litellm/monkey_patch.py` (layer 3, runs on the request
  path) and the enrich sidecar both read the cache fields and write
  ``llm.token_count.prompt_details.cache_read`` (and ``cache_miss``) to span
  attributes.

**Verify:**

```bash
# proxy response includes the fields
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-pro-deepseek","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['usage'])"
# → includes prompt_cache_hit_tokens / prompt_cache_miss_tokens
```

### 2. Cost

**What it gives you:** every span carries `total_cost` / `prompt_cost` /
`completion_cost` in its attributes, computed in real time on the request path by
`CostSpanProcessor` (patch #7 in `monkey_patch.py`). The Phoenix dashboard
`costSummary` reads from `token_prices` (seeded by `db/pricing.sql`).

**How it works:**

- Per-model prices live in `litellm/otel_utils.py` → `MODEL_PRICING`
  (per-1M-token: input, output, and optional cache-hit price). This is shared by
  both the `CostSpanProcessor` (litellm request path) and any callers that import it.
- The same prices are mirrored into Phoenix's `generative_models` + `token_prices`
  tables (seeded from `litellm/db/pricing.sql`), which drive the dashboard's
  `costSummary`.
- `CostSpanProcessor` computes cost with a **cache-aware** formula:
  `cost = cache_hit_tokens × cache_price + cache_miss_tokens × input_price + completion_tokens × output_price`.
- **Price changes only need `docker restart litellm`** — `otel_utils.py` is volume-mounted
  and read at process start (no rebuild needed).

**Verify:**

```sql
-- a recent span with discounted cost
docker exec postgres psql -U phoenix -d phoenix \
  -c "select attributes->'llm'->'token_count' from spans
      where attributes->'llm'->'token_count' ? 'prompt_details'
      order by id desc limit 1;"
-- → prompt_details.cache_read > 0 and total_cost reflects the discount
```

### 3. Latency

**What it gives you:** end-to-end response time per call, viewable on span details
as `start_time` / `end_time` (Phoenix computes duration automatically).

**How it works:** LiteLLM records `start_time` and `end_time` on every OTel span.
Phoenix surfaces the duration in the span detail view — no separate annotation needed.

**Verify:** open any span in the Phoenix UI to see the duration.

### 4. Accuracy (LLM-as-judge)

**What it gives you:** an independent DeepSeek V4 Flash model rates how well the
coding agent actually completed each task. The verdict is a categorical label —
`excellent / good / adequate / poor / incomplete` — with a short explanation,
stored as the `task_accuracy` annotation per span.

**How it works:**

- `litellm/scripts/evaluate_accuracy.py` (the `eval-accuracy` sidecar) samples ~5% of
  unevaluated spans every 30 minutes.
- For each sampled span it reconstructs the system prompt + user request + model
  response from the span attributes and sends them to the judge model.
- The **judge model is DeepSeek V4 Flash via the official API directly**
  (`api.deepseek.com`), configured with its own key. It does **not** route through
  the litellm proxy, so evaluation never competes with your real traffic.
- The label is written straight to `span_annotations` (`annotator_kind = LLM`).
  Rationale: the native Phoenix evaluator framework is dataset/experiment oriented and
  needs a sandbox backend for code evaluators; the direct-annotation approach keeps
  live per-span judgment without that infrastructure.

**Verify:** the `task_accuracy` row in `span_annotations` (§1 query). On the Phoenix
UI, open any span to see its accuracy annotation.

### 5. Registered evaluator config (Evaluators page)

**What it gives you:** the `task_accuracy` LLM evaluator also appears as a *registered
evaluator* on Phoenix's **Evaluators** page, so you can see the config even though the
live annotations are written by the sidecar.

**How it works:** `litellm/db/evaluators.sql` (idempotent, auto-run by
`litellm/install.sh`) seeds:

- a DeepSeek custom provider (`deepseek-official-eval`) pointing at the official API,
- the judge prompt template (system + user with `{{mustache}}` variables),
- the `evaluators` / `llm_evaluators` / `dataset_evaluators` rows.

The custom provider's API key is encrypted server-side by Phoenix, so it is created
via the Phoenix GraphQL API during `install.sh` (never via SQL, never in the repo).

**Note:** cost and cache metrics are now computed on the request path by
`CostSpanProcessor` — the enrich sidecar only handles token promotion and sessions.

### 6. Session grouping

**What it gives you:** the Phoenix UI shows traces grouped into **sessions** (like
"one opencode conversation"), instead of a flat list of spans.

**How it works:** the enrich sidecar groups traces by time proximity (a new session
starts after a gap) and writes `project_sessions` rows, which Phoenix surfaces in the
UI.

### 7. Self-healing sidecars

**What it gives you:** the `enrich` and `eval-accuracy` sidecars no longer die
permanently on a transient Postgres disconnect (e.g. a container restart). Their
`--watch` loops now catch per-cycle errors, log, back off 10s, and continue — while
Docker's `restart: unless-stopped` still covers a full process crash.

### 8. Cursor-gated processing (`enrich_cursor`)

**What it gives you:** the enrich and eval-accuracy sidecars never full-table scan the
`spans` table. Each cycle only looks at spans with `id > last_processed_id`, using a
persistent watermark in the `enrich_cursor` table.

**How it works:**

- `enrich_spans.py` and `evaluate_accuracy.py` create `enrich_cursor` on startup (if
  it doesn't exist), with one cursor row per process: `enrich-promotion`,
  `enrich-sessions`, `eval-accuracy`.
- At the start of each cycle, the current watermark is read. Queries use
  `WHERE s.id > %(wm)s` (PK-index range scan, not a seq scan).
- After each cycle, the watermark advances to `max(fetched_ids, current_max_id)` —
  sampled-out spans are never re-fetched/re-judged.
- One-shot safeguard: if a cursor row is missing (fresh DB after wipe), it seeds to the
  current `MAX(id)` — never reprocesses history.
- Cursors survive laptop reboots and container restarts (stored in Postgres).

**Verify:**

```sql
docker exec postgres psql -U phoenix -d phoenix \
  -c "SELECT name, last_span_id, updated_at FROM enrich_cursor;"
```

---

## Configuration quick reference

| Concern | File |
|---|---|
| Models / routes / api keys | `litellm/config.yaml` |
| Per-model pricing | `litellm/otel_utils.py` (`MODEL_PRICING`) |
| Phoenix cost tables | `litellm/db/pricing.sql` (seeds `generative_models` + `token_prices`) |
| Cache-field preservation + cost processor | `litellm/monkey_patch.py` |
| Span token promotion + sessions | `litellm/scripts/enrich_spans.py` |
| Accuracy judge | `litellm/scripts/evaluate_accuracy.py` |
| Evaluator registration | `litellm/db/evaluators.sql` (run by `litellm/install.sh`) |
| opencode provider mapping | `opencode/opencode.jsonc` |
| Stack orchestration | `litellm/docker-compose.yml` |

## Proxy auth (`LITELLM_KEY`)

The proxy's admin key is **auto-generated** on first install as
`sk-litellm-local-dev-<32 hex chars>` (`openssl rand -hex 16`) and persisted in `.local/.env.local`
(single source of truth). It is forwarded to the `litellm` container via
`.local/litellm.env.local` (from `litellm/install.sh`) and to opencode via the
`LITELLM_KEY` environment variable (`opencode/opencode.jsonc` reads it with
`{env:LITELLM_KEY}`).

To rotate it, set a new value in `.local/.env.local` and re-run `litellm/install.sh`
(an empty or missing `LITELLM_KEY` regenerates a fresh one).

---

## How to change the upstream LLM provider

When switching from one API provider to another (e.g. OpenCodeGO → OpenRouter):

### 1. Update `config.yaml`

`model_name` follows the convention **`<real_model_name>-<provider>`** (e.g.
`deepseek-v4-pro-opencodego` for DeepSeek V4 Pro via OpenCodeGO, or
`deepseek-v4-pro-deepseek` for the official DeepSeek API). Each provider has its
own clearly-marked section with a big comment banner. Change `api_base` and
`api_key` for every model entry in that provider's section:

```yaml
# PROVIDER: OpenRouter — https://openrouter.ai/api/v1
# API KEY:  os.environ/PERSONAL_OPENROUTER_API_KEY
- model_name: "deepseek-v4-pro-openrouter"
  litellm_params:
    model: "openai/deepseek-v4-pro"
    api_base: "https://openrouter.ai/api/v1"
    api_key: "os.environ/PERSONAL_OPENROUTER_API_KEY"
```

### 2. Update `.env.example` and `docker-compose.yml`

- Add the new API key env var to `.env.example` and `.local/.env.local`.
- Update `litellm/docker-compose.yml`:
  - The `litellm` service env vars: `PERSONAL_OPENCODE_API_KEY` / `PERSONAL_DEEPSEEK_API_KEY` → new key name(s).
  - The `OTEL_ENDPOINT` and `OTEL_EXPORTER_OTLP_ENDPOINT` point to Phoenix (internal Docker network, don't change).

### 3. Rebuild and restart

```bash
script/bootstrap
litellm/install.sh
```

## How to add or remove a model

### Add a model

**`litellm/config.yaml`** — Add ONE entry under the provider's section (see the
comment banners for which section/`api_base`/`api_key` to use):

```yaml
- model_name: "new-model-opencodego"
  litellm_params:
    model: "openai/new-model"
    api_base: "https://opencode.ai/zen/go/v1"
    api_key: "os.environ/PERSONAL_OPENCODE_API_KEY"
```

**`litellm/otel_utils.py`** — Add pricing to `MODEL_PRICING` dict (prices per 1M tokens, keyed on the **real upstream model name**):

```python
"new-model": (input_price, output_price),
```

**Phoenix model registry** — Add the model + prices to `litellm/db/pricing.sql` (idempotent, auto-run by `install.sh`):
```sql
-- example: add under the custom-model blocks
INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
VALUES ('new-model', 'new-model', '', false)
ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
-- then INSERT INTO token_prices ... (see pricing.sql for the pattern)
```

The `name_pattern` must regex-match the `llm.model_name` attribute on incoming
spans — which is the **upstream** model name (e.g. `new-model`), NOT the
LiteLLM route name (`new-model-opencodego`).

**`opencode/opencode.jsonc`** — Add to the matching provider group (e.g. `opencodego`), using the LiteLLM route name as the model id. Don't name a group after a built-in provider (e.g. `deepseek`); opencode will merge the models.dev catalog into it. Use a unique id instead and add the built-in to `disabled_providers`.
```json
"new-model-opencodego": { "name": "New Model" }
```

**Rebuild** — `litellm/install.sh` (or `docker compose --env-file .local/litellm.env.local up -d --build enrich` for just the enrich sidecar, or `docker restart litellm` for price-only changes).

### Remove a model

Reverse the steps above. Soft-delete from Phoenix by setting `deleted_at` on the `generative_models` row.

## Pricing sources

Official OpenCodeGO pricing: `https://opencode.ai/docs/zen/#pricing`

Pricing must be kept in sync in TWO places:
1. `litellm/otel_utils.py` — `MODEL_PRICING` dict (shared source used by `CostSpanProcessor` in litellm). Price changes here only need `docker restart litellm` (no rebuild).
2. `litellm/db/pricing.sql` → Phoenix `generative_models` + `token_prices` tables (drives the dashboard `costSummary`).

## Rebuild / reinstall (idempotent)

```bash
script/bootstrap          # copies .env.example → .local/.env.local, runs all installers
litellm/install.sh        # builds images, starts stack, seeds pricing + evaluators
```

Everything above is defined in this dotfiles repo — cloning it on a new machine and
running the install scripts reproduces the same stack and features (secrets come from
`.local/.env.local`, generated from `.env.example`).

## Useful commands

```bash
# Rebuild and redeploy everything
litellm/install.sh

# Rebuild only the enrich sidecar (after pricing changes)
docker compose --env-file .local/litellm.env.local -f litellm/docker-compose.yml up -d --build enrich

# Restart litellm for price/MODEL_PRICING changes (no rebuild needed)
docker restart litellm

# View enrich / eval-accuracy / LiteLLM logs
docker logs enrich -f
docker logs eval-accuracy -f
docker logs litellm -f

# Query Phoenix API
curl -s http://localhost:6006/health
```
