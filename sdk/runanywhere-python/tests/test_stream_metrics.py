"""Deterministic tests for stream_with_metrics / astream_with_metrics via an injected clock."""

from __future__ import annotations

import asyncio
from typing import AsyncIterator, Callable, List

from runanywhere.results import LLMGenerationResult, LLMStreamEvent
from runanywhere.stream_metrics import astream_with_metrics, stream_with_metrics


def _fake_now(ticks: List[float]) -> Callable[[], float]:
    """Return a now() that yields each value in ``ticks`` on successive calls.

    The metrics code calls now() exactly three times for a non-empty stream:
    once at start, once at the first token, and once at the end.
    """
    seq = iter(ticks)
    return lambda: next(seq)


async def _agen(tokens: List[str]) -> AsyncIterator[str]:
    for t in tokens:
        yield t


def test_stream_with_metrics_deterministic() -> None:
    tokens = ["He", "llo", " ", "world"]
    # start=1000, first_at=1050, end=1250
    now = _fake_now([1000.0, 1050.0, 1250.0])

    events = list(stream_with_metrics(tokens, now=now))

    # 4 token events + 1 final event.
    assert len(events) == len(tokens) + 1

    body = events[:-1]
    assert all(isinstance(e, LLMStreamEvent) for e in body)
    assert [e.token for e in body] == tokens
    assert all(e.is_final is False for e in body)
    assert all(e.result is None for e in body)

    final = events[-1]
    assert final.is_final is True
    assert final.token == ""
    assert isinstance(final.result, LLMGenerationResult)

    r = final.result
    assert r.text == "Hello world"
    assert r.token_count == 4
    assert r.time_to_first_token_ms == 50.0          # 1050 - 1000
    assert r.tokens_per_second == 20.0               # 4 / ((1250-1050)/1000) = 4/0.2
    assert r.total_time_ms == 250.0                  # 1250 - 1000


def test_stream_with_metrics_empty_source() -> None:
    # No tokens => now() called only twice (start, end); no first-token tick.
    now = _fake_now([500.0, 700.0])
    events = list(stream_with_metrics([], now=now))

    assert len(events) == 1
    final = events[0]
    assert final.is_final is True
    assert final.token == ""
    r = final.result
    assert isinstance(r, LLMGenerationResult)
    assert r.text == ""
    assert r.token_count == 0
    assert r.time_to_first_token_ms == 0.0
    assert r.tokens_per_second == 0.0                # gen_ms == 0 guard
    assert r.total_time_ms == 200.0                  # 700 - 500


def test_stream_with_metrics_default_clock_runs() -> None:
    # Smoke test the default now = time.monotonic()*1000 path.
    events = list(stream_with_metrics(["a", "b"]))
    assert [e.token for e in events[:-1]] == ["a", "b"]
    final = events[-1]
    assert final.is_final is True
    assert final.result is not None
    assert final.result.token_count == 2
    assert final.result.total_time_ms >= 0.0


def test_astream_with_metrics_deterministic() -> None:
    tokens = ["a", "bc", "d"]
    # start=100, first_at=110, end=160 -> ttft=10, gen=50ms, tps = 3/0.05 = 60
    now = _fake_now([100.0, 110.0, 160.0])

    async def run() -> List[LLMStreamEvent]:
        out: List[LLMStreamEvent] = []
        async for ev in astream_with_metrics(_agen(tokens), now=now):
            out.append(ev)
        return out

    events = asyncio.run(run())

    assert len(events) == len(tokens) + 1
    assert [e.token for e in events[:-1]] == tokens
    assert all(e.is_final is False for e in events[:-1])

    final = events[-1]
    assert final.is_final is True
    assert final.token == ""
    r = final.result
    assert isinstance(r, LLMGenerationResult)
    assert r.text == "abcd"
    assert r.token_count == 3
    assert r.time_to_first_token_ms == 10.0
    assert r.tokens_per_second == 60.0
    assert r.total_time_ms == 60.0                   # 160 - 100


def test_astream_with_metrics_empty_source() -> None:
    now = _fake_now([10.0, 25.0])

    async def run() -> List[LLMStreamEvent]:
        return [ev async for ev in astream_with_metrics(_agen([]), now=now)]

    events = asyncio.run(run())
    assert len(events) == 1
    final = events[0]
    assert final.is_final is True
    r = final.result
    assert r.token_count == 0
    assert r.time_to_first_token_ms == 0.0
    assert r.tokens_per_second == 0.0
    assert r.total_time_ms == 15.0
