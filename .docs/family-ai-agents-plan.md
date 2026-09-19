# Family AI Agents — Plan

Status: draft, not implemented.

## Goal

Set up AI agents for my father and sister, reusing infrastructure I already
pay for and run:

- **Model access** → my existing OpenCode Go subscription (the "engine").
- **Gateway** → a LiteLLM proxy on AWS Lambda + DynamoDB, free forever on the
  AWS free tier.
- **Clients** → Hermes Agent on each laptop (mine, sister's, father's).
- **Access control** → 3 API keys, one per person.

## Architecture

```
[ Father laptop  : Hermes ] ─┐
[ Sister laptop  : Hermes ] ─┼─ per-person key ─▶ [ LiteLLM proxy (Lambda) ] ─▶ [ OpenCode Go (models) ]
[ My laptop      : Hermes ] ─┘                            │
                                                          └──▶ [ DynamoDB: 3 keys + usage ]
```

One proxy, three keys, one shared model backend. Each person's usage is
tracked separately by key.

## Components

### 1. Model backend — OpenCode Go subscription
- Already paid for; provides the model access.
- LiteLLM routes upstream to it (already wired in this machine's
  `topics-ai/litellm/config.yaml` — the `opencodego` provider section).

### 2. Gateway — LiteLLM proxy on AWS Lambda + DynamoDB
- **Lambda**: 1M requests/month + 400k GB-seconds, free permanently.
- **DynamoDB**: 25 GB storage + 200M requests/month, free permanently — stores
  the 3 virtual API keys and per-key usage.
- LiteLLM supports DynamoDB as a key/config backend, and can run on Lambda via
  `aws-lambda-web-adapter`.

### 3. Keys — 3 LiteLLM virtual keys
- One per person (me, sister, father).
- Enables per-person usage/cost tracking and independent revocation.

### 4. Client — Hermes Agent on each laptop
- Reuse the existing `topics-ai/hermes/install.sh`.
- Point each install at the Lambda endpoint + that person's key.
- Same setup for everyone; only the key differs.

## Onboarding material (for father and sister)

- **Watch first:** "Hermes Agent Desktop: Full Setup + Real Use Cases" by Greg
  Isenberg — https://www.youtube.com/watch?v=EJm8Ka-gVOc

## Implementation steps

1. **Verify upstream** — confirm OpenCode Go exposes an OpenAI-compatible
   endpoint LiteLLM can proxy (it already does on this machine).
2. **Stand up LiteLLM on Lambda + DynamoDB** — container image via
   `aws-lambda-web-adapter`; configure OpenCode Go as the upstream provider;
   DynamoDB as the key store.
3. **Create 3 virtual keys** in DynamoDB (one per person).
4. **Extend the Hermes installer** — accept `HERMES_BASE_URL` + `HERMES_API_KEY`
   (or a small per-person config) so one script sets up any family laptop.
5. **Onboard** — sister and father watch the video, run the installer, start
   chatting.

## Costs

- Infra: **$0** (Lambda + DynamoDB free tiers are permanent, not 12-month).
- Models: covered by the existing OpenCode Go subscription.

## Caveats / risks

- **Subscription ToS** — sharing one OpenCode Go subscription across 3 people
  may violate its terms. Verify before handing keys to family; this is a
  compliance question, not a technical one.
- **Lambda cold starts** — LiteLLM is a long-running proxy; Lambda fits only at
  low request volume. Fine here (tens of req/hr), but expect a cold-start
  latency hit on the first request after idle.
- **Streaming** — enable Lambda response streaming so output is token-by-token,
  not buffered.
- **Request volume** — measured usage is ~37–69 req/hr active. 1M/month is far
  more than enough even for 3 users.

## Open questions

1. Does OpenCode Go's ToS allow family sharing? (blocking check)
2. Current best path for LiteLLM on Lambda: `aws-lambda-web-adapter` vs a
   serverless-native LiteLLM build — verify before phase 2.
3. Which models to expose to family (subset of the subscription's models)?

## References

- Onboarding video: https://www.youtube.com/watch?v=EJm8Ka-gVOc
