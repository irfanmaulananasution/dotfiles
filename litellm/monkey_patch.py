"""
Monkey-patch LiteLLM to preserve DeepSeek cache fields in OTel metadata.

DeepSeek's API returns ``prompt_cache_hit_tokens`` and ``prompt_cache_miss_tokens``
alongside ``prompt_tokens_details.cached_tokens``.  LiteLLM drops these during
streaming usage aggregation and serialization, so the OTel span's
``metadata.usage_object`` never gets them.  This patcher:

1. Adds the missing fields to ``Usage`` so they survive ``model_dump``.
2. Ensures ``prompt_tokens_details.cached_tokens`` is preserved through the
   ``PromptTokensDetailsWrapper`` that LiteLLM uses internally.
3. Carries the cache fields forward in ``calculate_total_usage`` (the final
   client-facing chunk usage for streams).
4. Normalizes raw OpenAI SDK ``CompletionUsage`` chunks to ``litellm.Usage`` so
   per-chunk aggregation (``_usage_chunk_calculation_helper``) sees the fields.
5. Carries top-level cache fields through ``ChunkProcessor.calculate_usage``
   (the ``stream_chunk_builder`` assembled response usage).
6. Injects the live Usage object into the logging payload, because
   ``ModelResponse.model_dump()`` drops ``cached_tokens`` from the nested
   ``prompt_tokens_details`` even when the live object still carries it.
7. Attaches ``CostSpanProcessor`` to LiteLLM's ``TracerProvider`` so that
   every span gets ``llm.token_count.*`` attributes (incl. costs) written
   synchronously on the request path, before Phoenix ingest.
"""

from __future__ import annotations

import functools
from typing import Any, Optional

import pydantic
from opentelemetry.sdk.trace import SpanProcessor
from pydantic import BaseModel


class CostSpanProcessor(SpanProcessor):
    """Layer-3 OTel SpanProcessor that computes token counts + costs on the request path.

    Runs synchronously (on the thread that ends the span) — must remain trivially
    cheap (no I/O, no DB, no per-span logging).  Wrapped in try/except so a bug
    can never break span export or the proxy.
    """

    def __init__(self) -> None:
        import sys
        sys.path.insert(0, "/app")
        import otel_utils
        self._utils = otel_utils

    def on_start(self, span, parent_context=None) -> None:
        pass

    def _on_ending(self, span) -> None:
        # OTel SDK >= 1.39 calls this with the live span right before
        # on_end(). on_end() itself only receives a read-only ReadableSpan
        # in these versions, so enrichment must happen here.
        self._enrich(span)

    def on_end(self, span) -> None:
        # Older SDKs pass the mutable span to on_end(); newer ones pass a
        # ReadableSpan (already enriched in _on_ending above).
        if hasattr(span, "set_attribute"):
            self._enrich(span)

    def _enrich(self, span) -> None:
        try:
            attrs = span.attributes or {}
            if "llm.token_count.total_cost" in attrs:
                return
            usage_raw = attrs.get("metadata.usage_object")
            if not usage_raw:
                return
            prompt, completion, hit, miss, write = self._utils.parse_usage(usage_raw)
            model = (attrs.get("llm.model_name")
                     or attrs.get("llm.openai.model")
                     or attrs.get("gen_ai.request.model") or "")
            ip, op, chp = self._utils.lookup_pricing(model)
            if hit is not None or write is not None or miss is not None:
                pcost, ccost = self._utils.compute_cache_aware_cost(
                    prompt, hit, miss, completion, ip, chp, op, write)
            else:
                pcost, ccost = self._utils.compute_cost(prompt, completion, ip, op)

            total = None
            if pcost is not None and ccost is not None:
                total = round(pcost + ccost, 8)
            elif pcost is not None:
                total = pcost
            elif ccost is not None:
                total = ccost

            new_attrs = {
                # Phoenix's cost calculator requires openinference.span.kind="LLM".
                # Set it here so future spans get cost-computed at ingest time.
                "openinference.span.kind": "LLM",
                "llm.token_count.prompt": prompt,
                "llm.token_count.completion": completion,
                "llm.token_count.total": (prompt + completion)
                if prompt is not None and completion is not None else None,
                "llm.token_count.prompt_details.cache_read": hit,
                "llm.token_count.prompt_details.cache_write": write,
                "llm.token_count.cache_miss": miss,
                "llm.token_count.prompt_cost": pcost,
                "llm.token_count.completion_cost": ccost,
                "llm.token_count.total_cost": total,
                "llm.model_name": model or None,
                # Phoenix traces page reads gen_ai.cost.* (OpenInference standard),
                # not llm.token_count.*_cost — write both so all views show data.
                "gen_ai.cost.total_cost": total,
                "gen_ai.cost.input_cost": pcost,
                "gen_ai.cost.output_cost": ccost,
            }

            # The SDK freezes the span (sets _end_time, marks attributes
            # immutable) before processor hooks run, so set_attribute() is a
            # rejected no-op at this point. Write through the live attributes
            # store, temporarily lifting the immutability flag.
            live_attrs = getattr(span, "_attributes", None)
            if live_attrs is not None:
                was_immutable = getattr(live_attrs, "_immutable", False)
                if was_immutable:
                    live_attrs._immutable = False
                try:
                    for k, v in new_attrs.items():
                        if v is not None and k not in attrs:
                            live_attrs[k] = v
                finally:
                    if was_immutable:
                        live_attrs._immutable = True
            else:
                for k, v in new_attrs.items():
                    if v is not None and k not in attrs:
                        span.set_attribute(k, v)
        except Exception:
            pass


def apply() -> None:
    import litellm.utils
    from litellm.types.utils import PromptTokensDetailsWrapper

    # 1. Add cache fields to Usage model so model_dump preserves them
    # -----------------------------------------------------------------
    Usage = litellm.utils.Usage

    for field_name, field_default in (
        ("prompt_cache_hit_tokens", None),
        ("prompt_cache_miss_tokens", None),
    ):
        if field_name not in Usage.model_fields:
            Usage.model_fields[field_name] = pydantic.Field(
                default=field_default, annotation=Optional[int]
            )
            Usage.__annotations__[field_name] = Optional[int]
            setattr(Usage, field_name, field_default)

    Usage.model_rebuild(force=True)

    # 2. Ensure prompt_tokens_details preserves cached_tokens
    # -----------------------------------------------------------------
    # LiteLLM's PromptTokensDetailsWrapper extends the OpenAI version
    # but the constructor may misinterpret non-OpenAI keys.  Wrap
    # __init__ to always accept ``cached_tokens`` if present.

    _orig_init = PromptTokensDetailsWrapper.__init__

    @functools.wraps(_orig_init)
    def _patched_init(self, **kwargs: Any) -> None:
        # Ensure cached_tokens is passed through even if extra kwargs exist
        cached = kwargs.pop("cached_tokens", None)
        _orig_init(self, **kwargs)
        if cached is not None:
            object.__setattr__(self, "cached_tokens", cached)

    PromptTokensDetailsWrapper.__init__ = _patched_init

    # 3. Preserve cache fields in streaming usage reconstruction
    # -----------------------------------------------------------------
    # For streaming requests, LiteLLM rebuilds the final Usage from the
    # accumulated chunks via ``calculate_total_usage``, which only keeps
    # prompt/completion/total token counts and drops the DeepSeek cache
    # fields.  Patch it to carry the cache fields forward from the most
    # recent usage chunk (the OpenAI SDK preserves them as extra fields).
    from litellm.litellm_core_utils.streaming_handler import calculate_total_usage as _orig_ctu

    @functools.wraps(_orig_ctu)
    def _patched_calculate_total_usage(chunks: list) -> Any:
        usage = _orig_ctu(chunks)

        latest_usage_chunk = None
        for chunk in chunks:
            if "usage" in chunk and chunk["usage"] is not None:
                latest_usage_chunk = chunk["usage"]

        if latest_usage_chunk is not None:
            src = (
                latest_usage_chunk
                if isinstance(latest_usage_chunk, dict)
                else latest_usage_chunk.model_dump()
            )
            for key in ("prompt_cache_hit_tokens", "prompt_cache_miss_tokens"):
                val = src.get(key)
                if val is not None:
                    setattr(usage, key, val)
            details = src.get("prompt_tokens_details")
            if details is not None and getattr(usage, "prompt_tokens_details", None) is None:
                try:
                    usage.prompt_tokens_details = PromptTokensDetailsWrapper(**details)
                except Exception:
                    pass

        return usage

    import litellm.litellm_core_utils.streaming_handler as _sh

    _sh.calculate_total_usage = _patched_calculate_total_usage

    # 4. Normalize usage chunks before per-chunk aggregation
    # -----------------------------------------------------------------
    # ``stream_chunk_builder``/``ChunkProcessor`` aggregates per-chunk usage
    # via ``_usage_chunk_calculation_helper``, which reads fields with
    # dict-style access (``"prompt_tokens" in usage_chunk`` / ``.get``).
    # That works for ``litellm.Usage`` but returns False for a raw OpenAI
    # SDK ``CompletionUsage`` (the type found on streaming chunks for
    # openai-compatible providers).  As a result prompt_tokens is dropped
    # and the cache fields are lost.  Normalize any BaseModel usage to a
    # ``litellm.Usage`` built from ``model_dump()`` (which now preserves
    # the cache fields).
    from litellm.litellm_core_utils.streaming_chunk_builder_utils import (
        ChunkProcessor,
    )
    from litellm.utils import Usage as _Usage

    _orig_extract = ChunkProcessor._extract_usage_chunk

    @staticmethod
    @functools.wraps(_orig_extract)
    def _patched_extract_usage_chunk(chunk: Any) -> Any:
        usage_chunk = _orig_extract(chunk)
        if usage_chunk is not None and isinstance(usage_chunk, BaseModel) and not isinstance(usage_chunk, _Usage):
            try:
                return _Usage(**usage_chunk.model_dump())
            except Exception:
                pass
        return usage_chunk

    ChunkProcessor._extract_usage_chunk = _patched_extract_usage_chunk

    # 5. Carry top-level cache fields through stream_chunk_builder usage
    # -----------------------------------------------------------------
    # ``ChunkProcessor.calculate_usage`` (used by the stream_chunk_builder
    # fast path and slow path) copies ``prompt_tokens_details`` from the
    # aggregated chunks but drops the top-level ``prompt_cache_hit_tokens`` /
    # ``prompt_cache_miss_tokens`` fields.  Mirror the prompt_tokens_details
    # copy for those top-level fields so the assembled Usage carries them.
    from litellm.types.utils import PromptTokensDetailsWrapper as _PTDW

    _orig_calc_usage = ChunkProcessor.calculate_usage

    @functools.wraps(_orig_calc_usage)
    def _patched_calculate_usage(self, chunks, model, completion_output, messages=None, reasoning_tokens=None):
        usage = _orig_calc_usage(self, chunks, model, completion_output, messages, reasoning_tokens)

        latest_usage_chunk = None
        for chunk in chunks:
            cu = ChunkProcessor._extract_usage_chunk(chunk)
            if cu is not None:
                latest_usage_chunk = cu

        if latest_usage_chunk is not None:
            src = (
                latest_usage_chunk.model_dump()
                if isinstance(latest_usage_chunk, BaseModel)
                else latest_usage_chunk
            )
            for key in ("prompt_cache_hit_tokens", "prompt_cache_miss_tokens"):
                val = src.get(key)
                if val is not None:
                    setattr(usage, key, val)
            details = src.get("prompt_tokens_details")
            if details is not None:
                try:
                    usage.prompt_tokens_details = _PTDW(**details)
                except Exception:
                    pass

        return usage

    ChunkProcessor.calculate_usage = _patched_calculate_usage

    # 6. Inject the live usage object into the logging payload
    # -----------------------------------------------------------------
    # ``ModelResponse.model_dump()`` (used by
    # ``_extract_response_obj_and_hidden_params``) drops ``cached_tokens``
    # from the nested ``prompt_tokens_details`` even though the live Usage
    # object still carries it.  Replace ``response_obj["usage"]`` with the
    # live Usage model_dump so the span's ``metadata.usage_object`` (and the
    # enrich sidecar) sees the cache fields.
    from litellm.litellm_core_utils.litellm_logging import _extract_response_obj_and_hidden_params as _orig_extract_resp

    @functools.wraps(_orig_extract_resp)
    def _patched_extract_response_obj_and_hidden_params(init_response_obj, original_exception):
        response_obj, hidden_params = _orig_extract_resp(init_response_obj, original_exception)
        if isinstance(init_response_obj, BaseModel):
            usage = getattr(init_response_obj, "usage", None)
            if usage is not None and isinstance(usage, BaseModel):
                try:
                    response_obj["usage"] = usage.model_dump()
                except Exception:
                    pass
        return response_obj, hidden_params

    import litellm.litellm_core_utils.litellm_logging as _ll

    _ll._extract_response_obj_and_hidden_params = _patched_extract_response_obj_and_hidden_params

    # 7. Attach CostSpanProcessor to LiteLLM's TracerProvider
    # litellm calls set_tracer_provider during run_server() startup, AFTER
    # apply(), so the deferred hook is the path that actually fires.
    from opentelemetry.sdk.trace import TracerProvider, SpanProcessor
    import opentelemetry.trace as otel_trace

    proc = CostSpanProcessor()
    tp = otel_trace.get_tracer_provider()
    if isinstance(tp, TracerProvider):
        tp.add_span_processor(proc)
    else:
        _orig_set = otel_trace.set_tracer_provider

        def _patched_set(provider):
            if isinstance(provider, TracerProvider):
                provider.add_span_processor(proc)
            return _orig_set(provider)

        otel_trace.set_tracer_provider = _patched_set
