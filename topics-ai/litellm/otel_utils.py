"""
Shared pricing, parsing, and utility functions for the observability stack.

Used by:
  - ``monkey_patch.py`` — ``CostSpanProcessor`` computes token counts + costs on the
    request path (layer 3, before Phoenix ingest).
  - ``evaluate_accuracy.py`` — ``parse_indexed_messages()`` fixes the flat-dotted-key
    JSONB storage format to reconstruct messages for the LLM judge.

Price changes here DO NOT need a container rebuild — restart litellm.
``docker restart litellm`` is sufficient (MODEL_PRICING is read at process start).
"""

from __future__ import annotations

import ast
import json
from typing import Any, Dict, List, Optional, Tuple


MODEL_PRICING: Dict[str, Tuple[float, float, Optional[float]]] = {
    "grok-4.5":        (2.00, 6.00, 0.30),
    "grok-build-0.1":  (1.00, 2.00, 0.20),
    "gpt-5.6-luna":    (0.10, 0.60, 0.02),
    "glm-5.2":         (0.966, 3.036, 0.26),
    "glm-5.1":         (0.966, 3.036, 0.26),
    "glm-5":           (1.00, 3.20, 0.20),
    "kimi-k3":         (3.00, 15.00, 0.30),
    "kimi-k2.7-code":  (0.73, 3.50, 0.19),
    "kimi-k2.6":       (0.95, 4.00, 0.16),
    "mimo-v2.5":       (0.14, 0.28),
    "mimo-v2.5-free":  (0.0, 0.0),
    "mimo-v2.5-pro":   (0.435, 0.87),
    "minimax-m3":      (0.30, 1.20, 0.06),
    "minimax-m2.7":    (0.25, 1.00, 0.06),
    "minimax-m2.5":    (0.30, 1.20, 0.06),
    "qwen3.8-max":     (2.00, 6.00, 0.25),
    "qwen3.7-max":     (1.475, 4.425, 0.50),
    "qwen3.7-plus":    (0.32, 1.28, 0.04),
    "qwen3.6-plus":    (0.325, 1.95, 0.05),
    "deepseek-v4-pro": (0.435, 0.87, 0.003625),
    "deepseek-v4-flash": (0.14, 0.28, 0.0028),
    "hy3":             (0.132, 0.528),
}


def lookup_pricing(model_name: str) -> Tuple[float, float, float]:
    clean = model_name
    for prefix in ("openai/", "litellm/"):
        if clean.startswith(prefix):
            clean = clean[len(prefix):]
    entry = MODEL_PRICING.get(clean, (0.0, 0.0))
    input_price, output_price = entry[0], entry[1]
    cache_hit_price = entry[2] if len(entry) > 2 and entry[2] is not None else input_price
    return input_price, output_price, cache_hit_price


def compute_cost(prompt_tokens: Optional[int], completion_tokens: Optional[int],
                 input_price_per_1m: float, output_price_per_1m: float) -> Tuple[Optional[float], Optional[float]]:
    prompt_cost = None
    completion_cost = None
    if prompt_tokens is not None and prompt_tokens > 0:
        prompt_cost = round(prompt_tokens / 1_000_000.0 * input_price_per_1m, 8)
    if completion_tokens is not None and completion_tokens > 0:
        completion_cost = round(completion_tokens / 1_000_000.0 * output_price_per_1m, 8)
    return prompt_cost, completion_cost


def compute_cache_aware_cost(prompt_tokens: Optional[int], cache_hit_tokens: Optional[int],
                             cache_miss_tokens: Optional[int], completion_tokens: Optional[int],
                             input_price: float, cache_hit_price: float, output_price: float,
                             cache_write_tokens: Optional[int] = None) -> Tuple[Optional[float], Optional[float]]:
    prompt_cost = None
    completion_cost = None
    if cache_hit_tokens is not None and cache_hit_tokens > 0:
        prompt_cost = round(cache_hit_tokens / 1_000_000.0 * cache_hit_price, 8)
    if cache_write_tokens is not None and cache_write_tokens > 0:
        wc = round(cache_write_tokens / 1_000_000.0 * input_price, 8)
        prompt_cost = (prompt_cost or 0.0) + wc
    if cache_miss_tokens is not None and cache_miss_tokens > 0:
        mc = round(cache_miss_tokens / 1_000_000.0 * input_price, 8)
        prompt_cost = (prompt_cost or 0.0) + mc
    if prompt_cost is not None:
        prompt_cost = round(prompt_cost, 8)
    if completion_tokens is not None and completion_tokens > 0:
        completion_cost = round(completion_tokens / 1_000_000.0 * output_price, 8)
    return prompt_cost, completion_cost


def _first_not_none(*vals: Optional[int]) -> Optional[int]:
    for v in vals:
        if v is not None:
            return v
    return None


def parse_usage(usage_obj) -> Tuple[Optional[int], Optional[int], Optional[int], Optional[int], Optional[int]]:
    """Returns (prompt_tokens, completion_tokens, cache_hit_tokens, cache_miss_tokens, cache_write_tokens).

    Accepts str (tries json.loads first, then ast.literal_eval) or dict.
    """
    if isinstance(usage_obj, str):
        try:
            usage = json.loads(usage_obj)
        except (json.JSONDecodeError, TypeError):
            try:
                usage = ast.literal_eval(usage_obj)
            except (ValueError, SyntaxError):
                return None, None, None, None, None
    elif isinstance(usage_obj, dict):
        usage = usage_obj
    else:
        return None, None, None, None, None

    prompt = usage.get("prompt_tokens")
    completion = usage.get("completion_tokens")
    details = usage.get("prompt_tokens_details")
    if not isinstance(details, dict):
        details = {}
    cache_hit = _first_not_none(
        usage.get("prompt_cache_hit_tokens"),
        details.get("cached_tokens"),
        usage.get("cached_tokens"),
        usage.get("cache_read_input_tokens"),
    )
    cache_write = _first_not_none(
        usage.get("cache_creation_input_tokens"),
        details.get("cache_write_tokens"),
        usage.get("cache_write_input_tokens"),
    )
    cache_miss = usage.get("prompt_cache_miss_tokens")
    if cache_miss is None and prompt is not None and (cache_hit is not None or cache_write is not None):
        cache_miss = prompt - (cache_hit or 0) - (cache_write or 0)
    return prompt, completion, cache_hit, cache_miss, cache_write


def parse_messages(messages_str):
    try:
        return ast.literal_eval(messages_str) if isinstance(messages_str, str) else messages_str
    except Exception:
        return []


def parse_choices(choices_str):
    try:
        return ast.literal_eval(choices_str) if isinstance(choices_str, str) else choices_str
    except Exception:
        return []


def parse_indexed_messages(im: dict) -> List[Dict[str, str]]:
    """Parse flat dotted-key indexed messages into a list of role/content dicts.

    Input:  ``{"0.message.role": "system", "0.message.content": "You are...",
               "1.message.role": "user", "1.message.content": "Hello"}``
    Output: ``[{"role": "system", "content": "You are..."},
              {"role": "user", "content": "Hello"}]``

    Indices are sorted numerically (so ``"10"`` follows ``"2"``).
    """
    if isinstance(im, list):
        return [dict(m) if isinstance(m, dict) else {"role": "", "content": str(m)} for m in im]

    by_index: Dict[int, Dict[str, str]] = {}
    for key, value in im.items():
        if not isinstance(key, str):
            continue
        parts = key.split(".message.", 1)
        if len(parts) != 2:
            continue
        idx_str, field = parts
        try:
            idx = int(idx_str)
        except ValueError:
            continue
        if idx not in by_index:
            by_index[idx] = {}
        by_index[idx][field] = str(value) if value is not None else ""

    result = []
    for idx in sorted(by_index.keys()):
        entry = by_index[idx]
        result.append({"role": entry.get("role", ""), "content": entry.get("content", "")})

    return result
