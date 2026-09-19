-- Register task_accuracy LLM evaluator in Phoenix DB.
-- Does NOT touch litellm. Idempotent — safe to run repeatedly.
-- Runs as part of topics-ai/litellm/install.sh after the stack is healthy.
-- Requires the DeepSeek custom provider `deepseek-official-eval` to already
-- exist (created by install.sh via the Phoenix GraphQL API — the provider's
-- API key is encrypted server-side, so it cannot be inserted via SQL).

BEGIN;

DO $$
DECLARE
    _exists boolean;
    _prompt_id integer;
    _pv_id integer;
    _tag_id integer;
    _eval_id integer;
    _ds_id integer;
    _ds_eval_project_id integer;
    _prov_id integer;
    _template jsonb;
BEGIN
    -- Bail out early if evaluator already registered
    SELECT EXISTS (SELECT 1 FROM evaluators WHERE name = 'task_accuracy') INTO _exists;
    IF _exists THEN
        RAISE NOTICE 'Evaluator task_accuracy already registered — nothing to do.';
        RETURN;
    END IF;

    -- 0. Find the DeepSeek custom provider (must exist; install.sh creates it)
    SELECT id INTO _prov_id FROM generative_model_custom_providers WHERE name = 'deepseek-official-eval';
    IF NOT FOUND THEN
        RAISE WARNING 'Custom provider deepseek-official-eval not found — evaluator will need manual model config.';
        _prov_id := NULL;
    END IF;

    -- 1. Ensure prompt exists
    INSERT INTO prompts (name, description, metadata)
    VALUES ('task-accuracy-evaluator', 'LLM-as-judge accuracy evaluator', '{}')
    ON CONFLICT (name) DO NOTHING;

    SELECT id INTO _prompt_id FROM prompts WHERE name = 'task-accuracy-evaluator';
    RAISE NOTICE 'prompt_id=%', _prompt_id;

    -- 2. Insert prompt_version with chat template
    _template := '{
      "type": "chat",
      "messages": [
        {
          "role": "system",
          "content": [{"type": "text", "text": "You are an AI usage evaluator. Your job is to judge how well an AI coding agent completed a given task. Rate the answer on its own merits - do not compare it to a reference answer.\n\nOutput ONLY a JSON object with exactly these keys:\n{\n  \"label\": \"excellent\" | \"good\" | \"adequate\" | \"poor\" | \"incomplete\",\n  \"explanation\": \"1-2 sentence concise explanation\"\n}\n\nLabel definitions:\n- excellent: fully completed correctly, no errors, well-structured\n- good: completed with minor issues\n- adequate: partially completed or rough but useful\n- poor: mostly incorrect or off-track\n- incomplete: did not meaningfully attempt (empty, refusal, irrelevant)"}]
        },
        {
          "role": "user",
          "content": [{"type": "text", "text": "## System Instructions\n{{system_prompt}}\n\n## User Request\n{{user_messages}}\n\n## Model Response\n{{assistant_response}}\n\nJudge the quality of the model response to this coding task."}]
        }
      ]
    }'::jsonb;

    INSERT INTO prompt_versions (
      prompt_id, description, template_type, template_format, template,
      invocation_parameters, tools, model_provider, model_name, custom_provider_id, metadata
    ) VALUES (
      _prompt_id,
      'Task accuracy judge',
      'CHAT',
      'MUSTACHE',
      _template,
      '{"type": "openai", "openai": {"temperature": 0.1, "max_completion_tokens": 256}}'::jsonb,
      '[]'::jsonb,
      'openai',
      'deepseek-v4-flash',
      _prov_id,
      '{}'::jsonb
    )
    RETURNING id INTO _pv_id;
    RAISE NOTICE 'prompt_version_id=%', _pv_id;

    -- 3. Create tag "latest" pointing to this version
    INSERT INTO prompt_version_tags (name, description, prompt_id, prompt_version_id)
    VALUES ('latest', 'Latest version', _prompt_id, _pv_id)
    ON CONFLICT (name, prompt_id) DO UPDATE
      SET prompt_version_id = _pv_id, description = 'Latest version'
    RETURNING id INTO _tag_id;
    RAISE NOTICE 'tag_id=%', _tag_id;

    -- 4. Insert evaluator (LLM kind)
    INSERT INTO evaluators (name, description, metadata, kind)
    VALUES ('task_accuracy', 'LLM judge rating: excellent/good/adequate/poor/incomplete', '{}', 'LLM')
    RETURNING id INTO _eval_id;
    RAISE NOTICE 'evaluator_id=%', _eval_id;

    -- 5. Insert llm_evaluator (polymorphic FK on kind+id)
    INSERT INTO llm_evaluators (id, kind, prompt_id, prompt_version_tag_id, output_configs)
    VALUES (
      _eval_id,
      'LLM',
      _prompt_id,
      _tag_id,
      '[
        {
          "type": "CATEGORICAL",
          "name": "task_accuracy",
          "optimization_direction": "MAXIMIZE",
          "values": [
            {"label": "excellent", "score": 1.0},
            {"label": "good", "score": 0.75},
            {"label": "adequate", "score": 0.5},
            {"label": "poor", "score": 0.25},
            {"label": "incomplete", "score": 0.0}
          ]
        }
      ]'::jsonb
    );

    -- 6. Ensure dataset exists
    INSERT INTO datasets (name, description, metadata)
    VALUES ('opencode-sessions', 'Opencode coding agent sessions for accuracy evaluation', '{}')
    ON CONFLICT (name) DO NOTHING;
    SELECT id INTO _ds_id FROM datasets WHERE name = 'opencode-sessions';

    -- 6b. Use a DEDICATED project for the dataset evaluator. Phoenix's projects
    -- listing excludes any project that has a dataset_evaluator row, so pointing
    -- this at the "default" project would hide all real traces from the UI.
    INSERT INTO projects (name, description)
    VALUES ('evaluators', 'Dataset evaluator project')
    ON CONFLICT (name) DO NOTHING;
    SELECT id INTO _ds_eval_project_id FROM projects WHERE name = 'evaluators';

    -- 7. Link evaluator to dataset
    INSERT INTO dataset_evaluators (dataset_id, evaluator_id, name, description, output_configs, input_mapping, project_id)
    VALUES (
      _ds_id,
      _eval_id,
      'task_accuracy',
      'LLM judge rating: excellent/good/adequate/poor/incomplete',
      '[
        {
          "type": "CATEGORICAL",
          "name": "task_accuracy",
          "optimization_direction": "MAXIMIZE",
          "values": [
            {"label": "excellent", "score": 1.0},
            {"label": "good", "score": 0.75},
            {"label": "adequate", "score": 0.5},
            {"label": "poor", "score": 0.25},
            {"label": "incomplete", "score": 0.0}
          ]
        }
      ]'::jsonb,
      '{"literal_mapping": {}, "path_mapping": {}}'::jsonb,
      _ds_eval_project_id  -- dedicated 'evaluators' project, NOT 'default'
    )
    ON CONFLICT (dataset_id, name) DO NOTHING;

END $$;

COMMIT;
