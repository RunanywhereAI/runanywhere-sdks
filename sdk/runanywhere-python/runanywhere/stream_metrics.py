"""Wrap a token stream as LLMStreamEvents, computing per-generation timing metrics.

Also separates a thinking model's ``<think>…</think>`` reasoning from its answer (see
:mod:`runanywhere._thinking_splitter`): streamed events carry ``is_thinking`` per token, and the
final result exposes the clean ``text`` (answer) plus ``thinking_content``. For a model that emits
no thinking tags this is a no-op — every token is an answer token, byte-for-byte as before.
"""

from __future__ import annotations

import time
from typing import AsyncIterable, AsyncIterator, Callable, Iterable, Iterator

from ._thinking_splitter import ThinkingSplitter
from .results import LLMGenerationResult, LLMStreamEvent


def _default_now() -> float:
    """Milliseconds monotonic clock — the injectable default for both variants."""
    return time.monotonic() * 1000.0


def _final_event(
    answer: str, thinking: str, count: int, start: float, first_at: float, end: float
) -> LLMStreamEvent:
    gen_ms = 0.0 if first_at < 0 else end - first_at
    return LLMStreamEvent(
        token="",
        is_final=True,
        result=LLMGenerationResult(
            text=answer,
            token_count=count,
            time_to_first_token_ms=0.0 if first_at < 0 else first_at - start,
            tokens_per_second=(count / (gen_ms / 1000.0)) if gen_ms > 0 else 0.0,
            total_time_ms=end - start,
            thinking_content=thinking or None,
        ),
    )


def stream_with_metrics(
    source: Iterable[str],
    now: Callable[[], float] | None = None,
) -> Iterator[LLMStreamEvent]:
    """Wrap a sync token iterable as a stream of LLMStreamEvent with timing metrics + thinking split.

    Non-final events carry a ``token`` (``is_thinking`` distinguishes reasoning from answer); the
    final event carries ``is_final=True`` and the aggregated ``LLMGenerationResult`` (answer text,
    ``thinking_content``, time-to-first-token, tokens/second, total time). ``now`` returns
    milliseconds and is injectable for deterministic tests.
    """
    clock = now if now is not None else _default_now
    start = clock()
    first_at = -1.0
    count = 0
    answer = ""
    thinking = ""
    splitter = ThinkingSplitter()
    for token in source:
        if first_at < 0:
            first_at = clock()
        count += 1
        for text, is_thinking in splitter.push(token):
            if is_thinking:
                thinking += text
            else:
                answer += text
            yield LLMStreamEvent(token=text, is_final=False, is_thinking=is_thinking)
    for text, is_thinking in splitter.flush():
        if is_thinking:
            thinking += text
        else:
            answer += text
        yield LLMStreamEvent(token=text, is_final=False, is_thinking=is_thinking)
    yield _final_event(answer, thinking, count, start, first_at, clock())


async def astream_with_metrics(
    source: AsyncIterable[str],
    now: Callable[[], float] | None = None,
) -> AsyncIterator[LLMStreamEvent]:
    """Async twin of :func:`stream_with_metrics` over an async token iterable."""
    clock = now if now is not None else _default_now
    start = clock()
    first_at = -1.0
    count = 0
    answer = ""
    thinking = ""
    splitter = ThinkingSplitter()
    async for token in source:
        if first_at < 0:
            first_at = clock()
        count += 1
        for text, is_thinking in splitter.push(token):
            if is_thinking:
                thinking += text
            else:
                answer += text
            yield LLMStreamEvent(token=text, is_final=False, is_thinking=is_thinking)
    for text, is_thinking in splitter.flush():
        if is_thinking:
            thinking += text
        else:
            answer += text
        yield LLMStreamEvent(token=text, is_final=False, is_thinking=is_thinking)
    yield _final_event(answer, thinking, count, start, first_at, clock())
