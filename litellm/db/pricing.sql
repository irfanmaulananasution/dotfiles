-- Seed Phoenix generative_models + token_prices for the CUSTOM models in
-- litellm/config.yaml. Idempotent — safe to run repeatedly.
--
-- Runs as part of litellm/install.sh after the stack is healthy.
-- Must be kept in sync with `MODEL_PRICING` in litellm/scripts/enrich_spans.py.
--
-- The `name_pattern` regex-matches the span's `llm.model_name` attribute, which
-- is the UPSTREAM model name (e.g. `deepseek-v4-pro`), not the LiteLLM route name.

BEGIN;

-- Helper: upsert a generative model and its token prices.
-- token_type values: input, output, cache_read, cache_write (is_prompt = true for prompt-side types).
DO $$
DECLARE
    _gm_id bigint;
BEGIN
    -- grok-4.5
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('grok-4.5', 'grok-4\.5', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'grok-4.5' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 3.0e-10),
        (_gm_id, 'input', true, 2.0e-06),
        (_gm_id, 'output', false, 6.0e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- gpt-5.6-luna
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('gpt-5.6-luna', 'gpt-5\.6-luna', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'gpt-5.6-luna' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 2.0e-11),
        (_gm_id, 'cache_write', true, 2.5e-10),
        (_gm_id, 'input', true, 1.0e-07),
        (_gm_id, 'output', false, 6.0e-07)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- glm-5.2
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('glm-5.2', 'glm-5\.2', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'glm-5.2' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 2.6e-10),
        (_gm_id, 'input', true, 9.66e-07),
        (_gm_id, 'output', false, 3.036e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- glm-5.1
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('glm-5.1', 'glm-5\.1', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'glm-5.1' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 2.6e-10),
        (_gm_id, 'input', true, 9.66e-07),
        (_gm_id, 'output', false, 3.036e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- kimi-k3
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('kimi-k3', 'kimi-k3', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'kimi-k3' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 3.0e-10),
        (_gm_id, 'input', true, 3.0e-06),
        (_gm_id, 'output', false, 1.5e-05)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- kimi-k2.7-code
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('kimi-k2.7-code', 'kimi-k2\.7-code', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'kimi-k2.7-code' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 1.9e-10),
        (_gm_id, 'input', true, 7.3e-07),
        (_gm_id, 'output', false, 3.5e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- kimi-k2.6
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('kimi-k2.6', 'kimi-k2\.6', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'kimi-k2.6' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 1.6e-10),
        (_gm_id, 'input', true, 9.5e-07),
        (_gm_id, 'output', false, 4.0e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- mimo-v2.5 (no cache price)
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('mimo-v2.5', 'mimo-v2\.5', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'mimo-v2.5' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'input', true, 1.4e-07),
        (_gm_id, 'output', false, 2.8e-07)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- mimo-v2.5-pro (no cache price)
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('mimo-v2.5-pro', 'mimo-v2\.5-pro', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'mimo-v2.5-pro' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'input', true, 4.35e-07),
        (_gm_id, 'output', false, 8.7e-07)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- minimax-m3
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('minimax-m3', 'minimax-m3', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'minimax-m3' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 6.0e-11),
        (_gm_id, 'input', true, 3.0e-07),
        (_gm_id, 'output', false, 1.2e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- minimax-m2.7
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('minimax-m2.7', 'minimax-m2\.7', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'minimax-m2.7' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 6.0e-11),
        (_gm_id, 'input', true, 2.5e-07),
        (_gm_id, 'output', false, 1.0e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- minimax-m2.5
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('minimax-m2.5', 'minimax-m2\.5', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'minimax-m2.5' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 6.0e-11),
        (_gm_id, 'input', true, 3.0e-07),
        (_gm_id, 'output', false, 1.2e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- qwen3.8-max
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('qwen3.8-max', 'qwen3\.8-max', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'qwen3.8-max' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 2.5e-10),
        (_gm_id, 'cache_write', true, 2.5e-09),
        (_gm_id, 'input', true, 2.0e-06),
        (_gm_id, 'output', false, 6.0e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- qwen3.7-max
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('qwen3.7-max', 'qwen3\.7-max', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'qwen3.7-max' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 5.0e-10),
        (_gm_id, 'cache_write', true, 3.125e-09),
        (_gm_id, 'input', true, 1.475e-06),
        (_gm_id, 'output', false, 4.425e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- qwen3.7-plus
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('qwen3.7-plus', 'qwen3\.7-plus', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'qwen3.7-plus' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 4.0e-11),
        (_gm_id, 'cache_write', true, 5.0e-10),
        (_gm_id, 'input', true, 3.2e-07),
        (_gm_id, 'output', false, 1.28e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- qwen3.6-plus
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('qwen3.6-plus', 'qwen3\.6-plus', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'qwen3.6-plus' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 5.0e-11),
        (_gm_id, 'cache_write', true, 6.25e-10),
        (_gm_id, 'input', true, 3.25e-07),
        (_gm_id, 'output', false, 1.95e-06)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- deepseek-v4-pro
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('deepseek-v4-pro', 'deepseek-v4-pro', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'deepseek-v4-pro' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 3.625e-09),
        (_gm_id, 'input', true, 4.35e-07),
        (_gm_id, 'output', false, 8.7e-07)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- deepseek-v4-flash
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('deepseek-v4-flash', 'deepseek-v4-flash', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'deepseek-v4-flash' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'cache_read', true, 2.8e-09),
        (_gm_id, 'input', true, 1.4e-07),
        (_gm_id, 'output', false, 2.8e-07)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    -- hy3 (no cache price)
    INSERT INTO generative_models (name, name_pattern, provider, is_built_in)
    VALUES ('hy3', 'hy3', '', false)
    ON CONFLICT (name, is_built_in) WHERE deleted_at IS NULL DO NOTHING;
    SELECT id INTO _gm_id FROM generative_models WHERE name = 'hy3' AND is_built_in = false;
    INSERT INTO token_prices (model_id, token_type, is_prompt, base_rate) VALUES
        (_gm_id, 'input', true, 1.32e-07),
        (_gm_id, 'output', false, 5.28e-07)
    ON CONFLICT (model_id, token_type, is_prompt) DO NOTHING;

    RAISE NOTICE 'Pricing seeded for all custom models.';
END $$;

COMMIT;
