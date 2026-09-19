#!/usr/bin/env python3
"""LLM-as-judge accuracy evaluator for Phoenix spans.

Samples unevaluated LLM spans (5%), sends prompt+response to a judge
LLM, and writes ``task_accuracy`` annotations back to Phoenix.

Evaluator model: DeepSeek V4 Flash official API (cheapest reliable judge).
"""

import argparse
import json
import os
import sys
import time
from typing import Any, Dict, Optional, Tuple

from openai import OpenAI

sys.path.insert(0, "/app")
import otel_utils

EVAL_MODEL = "deepseek-v4-flash"


EVAL_SYSTEM_PROMPT = """\
You are an AI usage evaluator. Your job is to judge how well an AI coding \
agent completed a given task. Rate the answer on its own merits — do not \
compare it to a reference answer, only to whether it fulfilled the user's \
request and the system instructions.

Output ONLY a JSON object with exactly these keys:
{
  "label": "excellent" | "good" | "adequate" | "poor" | "incomplete",
  "explanation": "1-2 sentence concise explanation"
}

Label definitions:
- excellent: fully completed the task correctly, no errors, well-structured
- good: completed the task with minor issues (small mistakes, could be improved)
- adequate: partially completed or rough but still useful output
- poor: mostly incorrect, off-track, or low-quality output
- incomplete: did not meaningfully attempt the task (empty, refusal, or irrelevant)"""


EVAL_USER_TEMPLATE = """## System Instructions
{system_prompt}

## User Request
{user_messages}

## Model Response
{assistant_response}

Judge the quality of the model's response to this coding task."""


def _parse_gen_ai_messages(raw) -> list:
    """Parse gen_ai format: JSON string of ``[{"role","parts":[{"type":"text","content"}]}]``."""
    if isinstance(raw, dict):
        raw = raw.get("messages", "")
    if not isinstance(raw, str) or not raw:
        return []
    try:
        parsed = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return []
    if not isinstance(parsed, list):
        return []
    result = []
    for m in parsed:
        if not isinstance(m, dict):
            continue
        role = m.get("role", "")
        parts = m.get("parts", [])
        content = ""
        if isinstance(parts, list) and parts:
            p0 = parts[0]
            if isinstance(p0, dict):
                content = p0.get("content", "")
        result.append({"role": role, "content": content})
    return result


def extract_messages(attrs: Dict[str, Any]) -> Tuple[str, str, str]:
    """Extract system prompt, user messages, and assistant response from span attributes.

    Primary source: ``llm.input_messages`` / ``llm.output_messages`` (flat dotted-key
    format).  Fallback: ``gen_ai.input.messages`` / ``gen_ai.output.messages``.
    """
    ims_raw = attrs.get("llm", {}).get("input_messages", {}) or {}
    oms_raw = attrs.get("llm", {}).get("output_messages", {}) or {}

    input_msgs = otel_utils.parse_indexed_messages(ims_raw) if ims_raw else []
    output_msgs = otel_utils.parse_indexed_messages(oms_raw) if oms_raw else []

    system_prompt = ""
    user_parts = []
    for m in input_msgs:
        if m.get("role") == "system":
            system_prompt = m.get("content", "")
        elif m.get("role") == "user":
            user_parts.append(m.get("content", ""))

    user_messages = "\n\n".join(user_parts) if user_parts else "(no user messages found)"

    assistant_response = "(no response found)"
    if output_msgs:
        assistant_response = output_msgs[-1].get("content", str(output_msgs[-1]))

    # Fallback: gen_ai format when indexed messages are absent
    if not input_msgs:
        gen_ai = attrs.get("gen_ai", {}) or {}
        gen_input = gen_ai.get("input", {})
        gen_msgs = _parse_gen_ai_messages(gen_input)
        if gen_msgs:
            system_prompt = ""
            user_parts = []
            for m in gen_msgs:
                if m.get("role") == "system":
                    system_prompt = m.get("content", "")
                elif m.get("role") == "user":
                    user_parts.append(m.get("content", ""))
            user_messages = "\n\n".join(user_parts) if user_parts else "(no user messages found)"

    if not output_msgs:
        gen_ai = attrs.get("gen_ai", {}) or {}
        gen_output = gen_ai.get("output", {})
        gen_msgs = _parse_gen_ai_messages(gen_output)
        if gen_msgs:
            assistant_response = gen_msgs[-1].get("content", "(empty)")

    MAX_LEN = 8000
    if len(system_prompt) > MAX_LEN:
        system_prompt = system_prompt[:MAX_LEN] + "\u2026[truncated]"
    if len(user_messages) > MAX_LEN:
        user_messages = user_messages[:MAX_LEN] + "\u2026[truncated]"
    if len(assistant_response) > MAX_LEN:
        assistant_response = assistant_response[:MAX_LEN] + "\u2026[truncated]"

    return system_prompt, user_messages, assistant_response


def evaluate_span(client: OpenAI, attrs: Dict[str, Any], dry_run: bool = False) -> Optional[Tuple[str, str]]:
    """Run LLM judge on one span. Returns (label, explanation) or None."""
    system_prompt, user_messages, assistant_response = extract_messages(attrs)
    user_question = EVAL_USER_TEMPLATE.format(
        system_prompt=system_prompt,
        user_messages=user_messages,
        assistant_response=assistant_response,
    )

    if dry_run:
        print(f"  [DRY] Would send {len(user_question)} chars to judge model")
        return ("adequate", "[dry-run]")

    try:
        resp = client.chat.completions.create(
            model=EVAL_MODEL,
            messages=[
                {"role": "system", "content": EVAL_SYSTEM_PROMPT},
                {"role": "user", "content": user_question},
            ],
            temperature=0.1,
            max_tokens=256,
        )
        content = resp.choices[0].message.content.strip()
        if content.startswith("```"):
            content = content.strip("`").strip()
            if content.startswith("json"):
                content = content[4:]
        result = json.loads(content)
        label = result.get("label", "adequate")
        explanation = result.get("explanation", "")[:500]
        valid = {"excellent", "good", "adequate", "poor", "incomplete"}
        if label not in valid:
            label = "adequate"
        return label, explanation
    except Exception as e:
        print(f"  Judge LLM error: {e}")
        return None


def _ensure_cursor(cur: Any, conn: Any) -> None:
    cur.execute("""
        CREATE TABLE IF NOT EXISTS enrich_cursor (
            name text PRIMARY KEY,
            last_span_id bigint NOT NULL DEFAULT 0,
            updated_at timestamptz NOT NULL DEFAULT now()
        )
    """)
    conn.commit()

    cur.execute("SELECT COALESCE(MAX(id), 0) FROM spans")
    max_id = cur.fetchone()[0]

    cur.execute("""
        INSERT INTO enrich_cursor (name, last_span_id, updated_at)
        VALUES (%(name)s, %(max_id)s, now())
        ON CONFLICT (name) DO NOTHING
    """, {"name": "eval-accuracy", "max_id": max_id})
    conn.commit()


def _read_cursor(cur: Any, name: str) -> int:
    cur.execute("SELECT last_span_id FROM enrich_cursor WHERE name = %(name)s", {"name": name})
    row = cur.fetchone()
    return row[0] if row else 0


def _write_cursor(cur: Any, conn: Any, last_id: int) -> None:
    cur.execute("""
        INSERT INTO enrich_cursor (name, last_span_id, updated_at)
        VALUES ('eval-accuracy', %(last_id)s, now())
        ON CONFLICT (name) DO UPDATE
            SET last_span_id = %(last_id)s, updated_at = now()
    """, {"last_id": last_id})
    conn.commit()


def evaluate_accuracy(db_url: str, deepseek_api_key: str,
                      sample_rate: float = 0.05, limit: int = 50, dry_run: bool = False) -> int:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    if not deepseek_api_key:
        print("No DEEPSEEK_API_KEY set — skipping LLM accuracy evaluation.")
        return 0

    client = OpenAI(api_key=deepseek_api_key, base_url="https://api.deepseek.com/v1")

    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=RealDictCursor)

    _ensure_cursor(cur, conn)
    watermark = _read_cursor(cur, "eval-accuracy")

    cur.execute("""
        SELECT s.id, s.attributes
        FROM spans s
        LEFT JOIN span_annotations sa
          ON sa.span_rowid = s.id AND sa.name = 'task_accuracy'
        WHERE s.id > %(wm)s
          AND s.attributes->'llm' ? 'input_messages'
          AND sa.id IS NULL
        ORDER BY s.id ASC
        LIMIT %(limit)s
    """, {"wm": watermark, "limit": limit})
    rows = cur.fetchall()

    if not rows:
        print("No spans to evaluate for accuracy.")
        cur.close()
        conn.close()
        return 0

    max_fetched = max(r["id"] for r in rows)

    n = 0
    for row in rows:
        if len(rows) > 1:
            import random
            if random.random() > sample_rate:
                continue

        span_id = row["id"]
        attrs = row["attributes"]
        result = evaluate_span(client, attrs, dry_run=dry_run)
        if result is None:
            continue

        label, explanation = result
        if dry_run:
            print(f"[DRY] span {span_id}: accuracy={label} ({explanation[:80]})")
        else:
            cur.execute(
                """INSERT INTO span_annotations
                     (span_rowid, name, annotator_kind, source, label, score, explanation, identifier, metadata)
                   VALUES (%s, 'task_accuracy', 'LLM', 'API', %s, %s, %s, '', '{}')
                   ON CONFLICT (name, span_rowid, identifier) DO NOTHING""",
                (
                    span_id,
                    label,
                    {"excellent": 1.0, "good": 0.75, "adequate": 0.5, "poor": 0.25, "incomplete": 0.0}[label],
                    explanation,
                ),
            )
        n += 1
        print(f"  span {span_id}: accuracy={label} ({explanation[:80]})")

    _write_cursor(cur, conn, max_fetched)

    cur.close()
    conn.close()
    print(f"Evaluated {n} spans for accuracy.")
    return n


def main():
    parser = argparse.ArgumentParser(description="LLM-judge accuracy evaluator for Phoenix spans")
    parser.add_argument("--db-url", default=os.environ.get("PHOENIX_DB_URL",
                        "postgresql://phoenix:phoenix@localhost:5432/phoenix"))
    parser.add_argument("--deepseek-api-key", default=os.environ.get("DEEPSEEK_API_KEY", ""))
    parser.add_argument("--sample-rate", type=float, default=0.05,
                        help="Fraction of unevaluated spans to judge (default 0.05)")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--watch", action="store_true", help="Run continuously every 30 min")
    args = parser.parse_args()

    if args.watch:
        while True:
            try:
                evaluate_accuracy(args.db_url, args.deepseek_api_key,
                                  sample_rate=args.sample_rate, dry_run=args.dry_run)
            except Exception as e:
                print(f"eval cycle error (will retry): {e}")
                time.sleep(10)
                continue
            time.sleep(1800)
    else:
        evaluate_accuracy(args.db_url, args.deepseek_api_key,
                          sample_rate=args.sample_rate, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
