"""Wrap a token stream as LLMStreamEvents, computing per-generation timing metrics."""

from __future__ import annotations

import time
from typing import AsyncIterable, AsyncIterator, Callable, Iterable, Iterator

from .results import LLMGenerationResult, LLMStreamEvent


def _default_now() -> float:
    """Milliseconds monotonic clock — the injectable default for both variants."""
    return time.monotonic() * 1000.0


def stream_with_metrics(
    source: Iterable[str],
    now: Callable[[], float] | None = None,
) -> Iterator[LLMStreamEvent]:
    """Wrap a sync token iterable as a stream of LLMStreamEvent with timing metrics.

    Non-final events carry a ``token``; the final event carries an empty token,
    ``is_final=True`` and the aggregated ``LLMGenerationResult`` (time-to-first-token,
    tokens/second, total time). ``now`` returns milliseconds and is injectable for
    deterministic tests (default: ``time.monotonic() * 1000``).
    """
    clock = now if now is not None else _default_now
    start = clock()
    first_at = -1.0
    count = 0
    text = ""
    for token in source:
        if first_at < 0:
            first_at = clock()
        count += 1
        text += token
        yield LLMStreamEvent(token=token, is_final=False)
    end = clock()
    gen_ms = 0.0 if first_at < 0 else end - first_at
    yield LLMStreamEvent(
        token="",
        is_final=True,
        result=LLMGenerationResult(
            text=text,
            token_count=count,
            time_to_first_token_ms=0.0 if first_at < 0 else first_at - start,
            tokens_per_second=(count / (gen_ms / 1000.0)) if gen_ms > 0 else 0.0,
            total_time_ms=end - start,
        ),
    )


async def astream_with_metrics(
    source: AsyncIterable[str],
    now: Callable[[], float] | None = None,
) -> AsyncIterator[LLMStreamEvent]:
    """Async twin of :func:`stream_with_metrics` over an async token iterable."""
    clock = now if now is not None else _default_now
    start = clock()
    first_at = -1.0
    count = 0
    text = ""
    async for token in source:
        if first_at < 0:
            first_at = clock()
        count += 1
        text += token
        yield LLMStreamEvent(token=token, is_final=False)
    end = clock()
    gen_ms = 0.0 if first_at < 0 else end - first_at
    yield LLMStreamEvent(
        token="",
        is_final=True,
        result=LLMGenerationResult(
            text=text,
            token_count=count,
            time_to_first_token_ms=0.0 if first_at < 0 else first_at - start,
            tokens_per_second=(count / (gen_ms / 1000.0)) if gen_ms > 0 else 0.0,
            total_time_ms=end - start,
        ),
    )
