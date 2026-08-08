#!/usr/bin/env python3
"""Slim enrich sidecar: token promotion to trace roots + session grouping.

Cost/token computation is now done at the layer-3 ``CostSpanProcessor`` (in
``monkey_patch.py``) on the request path.  This sidecar only handles the
post-ingest work that can't be done on the request thread:

- **promotion**: copy ``llm.token_count`` from the LLM child span up to its
  trace root so Phoenix displays them on the root span.
- **sessions**: group root spans into Phoenix sessions by time proximity.

Watermarks are persisted in the ``enrich_cursor`` table so full-table scans
are never needed — only new spans are examined each cycle.
"""

import argparse
import datetime
import json
import os
import sys
import time
import uuid
from typing import Any, Dict, List, Optional, Tuple


def _ensure_cursors(cur: Any, conn: Any) -> None:
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

    for cursor_name in ("enrich-promotion", "enrich-sessions", "eval-accuracy"):
        cur.execute("""
            INSERT INTO enrich_cursor (name, last_span_id, updated_at)
            VALUES (%(name)s, %(max_id)s, now())
            ON CONFLICT (name) DO NOTHING
        """, {"name": cursor_name, "max_id": max_id})
    conn.commit()


def _read_cursor(cur: Any, name: str) -> int:
    cur.execute("SELECT last_span_id FROM enrich_cursor WHERE name = %(name)s", {"name": name})
    row = cur.fetchone()
    return row[0] if row else 0


def _write_cursor(cur: Any, conn: Any, name: str, last_id: int) -> None:
    cur.execute("""
        INSERT INTO enrich_cursor (name, last_span_id, updated_at)
        VALUES (%(name)s, %(last_id)s, now())
        ON CONFLICT (name) DO UPDATE
            SET last_span_id = %(last_id)s, updated_at = now()
    """, {"name": name, "last_id": last_id})
    conn.commit()


def _promote_tokens_to_roots(cur: Any, conn: Any, watermark: int,
                             limit: int = 10, dry_run: bool = False) -> Tuple[int, int]:
    """Promote token/usage fields from the LLM child span up to the trace root.

    LiteLLM exports a tree of internal spans around every request (``auth``,
    ``proxy_pre_call``, ``router``, ``self``, ``litellm_request``,
    ``raw_gen_ai_request``); only ``litellm_request`` carries ``llm.token_count``.
    Phoenix surfaces the root span first (``Received Proxy Server Request``),
    which has no token data — making every trace look like 0 tokens.

    This pass:
      1. copies ``llm.token_count`` + ``llm.model_name`` from the LLM span up to
         its trace's root span (and sets the root's ``llm_token_count_*``
         columns), and
      2. tags every non-root span in that trace ``llm.internal_span: true`` so
         the orchestration noise can be filtered out.

    Idempotent: LLM spans already promoted (``llm.promoted_to_root``) are skipped,
    and promoted roots carry ``llm.promoted_root`` so they won't be re-processed.
    """
    cur.execute("""
        SELECT s.id, s.trace_rowid, s.parent_id, s.attributes,
               s.llm_token_count_prompt, s.llm_token_count_completion
        FROM spans s
        WHERE s.id > %(wm)s
          AND s.attributes->'llm' ? 'token_count'
          AND NOT (s.attributes->'llm' ? 'promoted_to_root')
        ORDER BY s.id ASC
        LIMIT %(limit)s
    """, {"wm": watermark, "limit": limit})
    src_rows = cur.fetchall()
    if not src_rows:
        return 0, watermark

    max_id = max(r["id"] for r in src_rows)

    trace_ids = sorted({r["trace_rowid"] for r in src_rows})
    cur.execute("""
        SELECT id, trace_rowid, span_id, parent_id, attributes
        FROM spans
        WHERE trace_rowid = ANY(%(trace_ids)s)
    """, {"trace_ids": trace_ids})
    all_spans = cur.fetchall()
    by_span_id = {r["span_id"]: r for r in all_spans}

    n = 0
    for src in src_rows:
        src_llm = (src["attributes"] or {}).get("llm", {})
        tc = src_llm.get("token_count")
        model_name = src_llm.get("model_name")
        if not isinstance(tc, dict):
            if not dry_run:
                cur.execute(
                    "UPDATE spans SET attributes = jsonb_set(attributes, %(p)s, 'true', true) WHERE id = %(id)s",
                    {"id": src["id"], "p": ["llm", "promoted_to_root"]},
                )
            continue

        chain: List[Dict[str, Any]] = []
        node = src
        seen: set = set()
        while node is not None and node["id"] not in seen:
            seen.add(node["id"])
            chain.append(node)
            pid = node.get("parent_id")
            if not pid:
                break
            node = by_span_id.get(pid)
        root = chain[-1]

        if dry_run:
            print(f"[DRY] promote span {src['id']} -> root {root['id']} "
                  f"prompt={tc.get('prompt')} completion={tc.get('completion')} "
                  f"model={model_name}")
            continue

        root_attrs = root.get("attributes") or {}
        root_llm = dict(root_attrs.get("llm", {}))
        if not isinstance(root_attrs.get("llm"), dict):
            root_llm = {}
        new_token_count = dict(root_llm.get("token_count", {}) or {})
        new_token_count.update(tc)
        root_llm["token_count"] = new_token_count
        if model_name:
            root_llm["model_name"] = model_name

        if root["id"] == src["id"]:
            root_llm["promoted_root"] = True
            root_llm["promoted_to_root"] = True
            root_llm["internal_span"] = True
            cur.execute(
                "UPDATE spans SET attributes = attributes || %(patch)s::jsonb WHERE id = %(id)s",
                {"id": root["id"], "patch": json.dumps({"llm": root_llm})},
            )
            root_row = root
        else:
            root_llm["promoted_root"] = True
            cur.execute(
                "UPDATE spans SET attributes = attributes || %(patch)s::jsonb WHERE id = %(id)s",
                {"id": root["id"], "patch": json.dumps({"llm": root_llm})},
            )
            src_llm_new = dict((src["attributes"] or {}).get("llm", {}))
            src_llm_new["promoted_to_root"] = True
            src_llm_new["internal_span"] = True
            cur.execute(
                "UPDATE spans SET attributes = attributes || %(patch)s::jsonb WHERE id = %(id)s",
                {"id": src["id"], "patch": json.dumps({"llm": src_llm_new})},
            )
            root_row = root

        cur.execute("""
            UPDATE spans
            SET llm_token_count_prompt = %(p)s,
                llm_token_count_completion = %(c)s,
                cumulative_llm_token_count_prompt =
                    GREATEST(cumulative_llm_token_count_prompt, %(p)s),
                cumulative_llm_token_count_completion =
                    GREATEST(cumulative_llm_token_count_completion, %(c)s)
            WHERE id = %(id)s
        """, {"id": root["id"], "p": tc.get("prompt"), "c": tc.get("completion")})

        for span in all_spans:
            if span["id"] in (root_row["id"], src["id"]):
                continue
            span_llm = dict((span.get("attributes") or {}).get("llm", {}))
            span_llm["internal_span"] = True
            cur.execute(
                "UPDATE spans SET attributes = attributes || %(patch)s::jsonb WHERE id = %(id)s",
                {"id": span["id"], "patch": json.dumps({"llm": span_llm})},
            )
        n += 1

    conn.commit()
    return n, max_id


def _assign_sessions(cur: Any, conn: Any, watermark: int, project_id: int = 1,
                     gap_minutes: int = 30, limit: int = 200,
                     dry_run: bool = False) -> Tuple[int, int]:
    """Group traces into Phoenix sessions by time proximity.

    Finds root spans without ``session.id``, clusters them by start-time
    gaps (≤ *gap_minutes*), and writes the attribute back.  Also inserts
    into ``project_sessions`` so the Phoenix UI sees them.

    Idempotent – spans already carrying ``session.id`` are skipped.
    """
    cur.execute("""
        SELECT s.id, s.start_time, s.end_time
        FROM spans s
        WHERE s.id > %(wm)s
          AND s.parent_id IS NULL
          AND NOT (s.attributes ? 'session.id')
        ORDER BY s.start_time ASC
        LIMIT %(limit)s
    """, {"wm": watermark, "limit": limit})
    rows = cur.fetchall()
    if not rows:
        return 0, watermark

    max_id = max(r["id"] for r in rows)

    not_before = rows[0]["start_time"] - datetime.timedelta(minutes=gap_minutes)
    cur.execute("""
        SELECT session_id, start_time, end_time
        FROM project_sessions
        WHERE project_id = %(pid)s AND end_time >= %(cutoff)s
        ORDER BY end_time DESC
    """, {"pid": project_id, "cutoff": not_before})
    sessions: List[Dict[str, Any]] = [dict(r) for r in cur.fetchall()]

    n = 0
    for row in rows:
        span_id = row["id"]
        span_start = row["start_time"]
        span_end = row["end_time"]

        matched_sid: Optional[str] = None
        gap = datetime.timedelta(minutes=gap_minutes)
        for sess in sessions:
            if abs((span_start - sess["end_time"]).total_seconds()) <= gap.total_seconds():
                matched_sid = sess["session_id"]
                sess["end_time"] = max(sess["end_time"], span_end)
                break

        if matched_sid is None:
            matched_sid = str(uuid.uuid4())
            sessions.insert(0, {
                "session_id": matched_sid,
                "start_time": span_start,
                "end_time": span_end,
            })

        if dry_run:
            print(f"[DRY] span {span_id}: session.id={matched_sid}")
        else:
            cur.execute(
                "UPDATE spans SET attributes = attributes || %(patch)s::jsonb WHERE id = %(id)s",
                {"id": span_id, "patch": json.dumps({"session.id": matched_sid})},
            )
            cur.execute("""
                INSERT INTO project_sessions (session_id, project_id, start_time, end_time)
                VALUES (%(sid)s, %(pid)s, %(st)s, %(et)s)
                ON CONFLICT (session_id)
                DO UPDATE SET end_time = GREATEST(project_sessions.end_time, %(et)s)
            """, {"sid": matched_sid, "pid": project_id, "st": span_start, "et": span_end})
        n += 1

    conn.commit()
    return n, max_id


def enrich_cycle(db_url: str, dry_run: bool = False) -> int:
    import psycopg2
    from psycopg2.extras import RealDictCursor

    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=RealDictCursor)

    _ensure_cursors(cur, conn)

    wm_promotion = _read_cursor(cur, "enrich-promotion")
    wm_sessions = _read_cursor(cur, "enrich-sessions")

    cur.execute("SELECT COALESCE(MAX(id), 0) FROM spans")
    current_max = cur.fetchone()[0]

    promoted, max_promoted = _promote_tokens_to_roots(cur, conn, wm_promotion,
                                                      dry_run=dry_run)
    if promoted:
        print(f"Promoted tokens to {promoted} trace roots.")

    sessions_assigned, max_session = _assign_sessions(cur, conn, wm_sessions,
                                                      dry_run=dry_run)
    if sessions_assigned:
        print(f"Assigned {sessions_assigned} traces to sessions.")

    new_wm_promotion = max(current_max, max_promoted)
    new_wm_sessions = max(current_max, max_session)
    _write_cursor(cur, conn, "enrich-promotion", new_wm_promotion)
    _write_cursor(cur, conn, "enrich-sessions", new_wm_sessions)

    cur.close()
    conn.close()
    return promoted + sessions_assigned


def main():
    parser = argparse.ArgumentParser(description="Slim enrich sidecar: token promotion + session grouping")
    parser.add_argument("--db-url", default=os.environ.get("PHOENIX_DB_URL",
                        "postgresql://phoenix:phoenix@localhost:5432/phoenix"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--watch", action="store_true", help="Run continuously every 30s")
    args = parser.parse_args()

    if args.watch:
        idle_streak = 0
        while True:
            try:
                total = enrich_cycle(args.db_url, dry_run=args.dry_run)
            except Exception as e:
                print(f"enrich cycle error (will retry): {e}")
                time.sleep(10)
                continue
            if total == 0:
                idle_streak += 1
            else:
                idle_streak = 0
            delay = 120 if idle_streak >= 2 else 30
            time.sleep(delay)
    else:
        enrich_cycle(args.db_url, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
