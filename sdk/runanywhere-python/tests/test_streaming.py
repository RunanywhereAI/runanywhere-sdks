"""Tests for iter_tokens / aiter_tokens using in-Python fake native_call closures."""

from __future__ import annotations

import asyncio
import threading
from typing import Callable, List

import pytest

from runanywhere._streaming import aiter_tokens, iter_tokens

OnToken = Callable[[str], "bool | None"]


def _fake_native(tokens: List[str], observed: dict) -> Callable[[OnToken], None]:
    """A fake native_call: pushes each token; honours a False return by stopping early.

    ``observed`` records whether the loop saw a False return (stop-on-close) and how many
    tokens it actually emitted.
    """
    observed.setdefault("stopped", False)
    observed.setdefault("emitted", 0)

    def native(on_token: OnToken) -> None:
        for tok in tokens:
            keep = on_token(tok)
            observed["emitted"] += 1
            if keep is False:
                observed["stopped"] = True
                return

    return native


def _raising_native(before: List[str]) -> Callable[[OnToken], None]:
    """A fake native_call that emits ``before`` then raises mid-stream."""

    def native(on_token: OnToken) -> None:
        for tok in before:
            on_token(tok)
        raise RuntimeError("boom")

    return native


def test_iter_tokens_yields_all() -> None:
    observed: dict = {}
    native = _fake_native(["a", "b", "c"], observed)

    out = list(iter_tokens(native))

    assert out == ["a", "b", "c"]
    assert observed["stopped"] is False


def test_iter_tokens_break_stops_and_joins() -> None:
    observed: dict = {}
    # Long stream so a break is guaranteed to happen before the fake finishes.
    native = _fake_native([str(i) for i in range(1000)], observed)

    seen: List[str] = []
    gen = iter_tokens(native, maxsize=4)
    for tok in gen:
        seen.append(tok)
        if len(seen) == 3:
            break
    # Closing the generator (leaving the for-loop) triggers the finally: stop + join.
    gen.close()

    assert seen == ["0", "1", "2"]
    # The fake observed a False return and stopped early — it did NOT run all 1000.
    assert observed["stopped"] is True
    assert observed["emitted"] < 1000

    # No lingering stream worker thread == we joined without hanging.
    assert not any(t.name == "ra-stream" and t.is_alive() for t in threading.enumerate())


def test_iter_tokens_reraises_worker_exception() -> None:
    native = _raising_native(["x", "y"])

    got: List[str] = []
    with pytest.raises(RuntimeError, match="boom"):
        for tok in iter_tokens(native):
            got.append(tok)

    # Tokens emitted before the raise still reached the consumer.
    assert got == ["x", "y"]
    assert not any(t.name == "ra-stream" and t.is_alive() for t in threading.enumerate())


def test_iter_tokens_empty_stream() -> None:
    observed: dict = {}
    native = _fake_native([], observed)
    assert list(iter_tokens(native)) == []


def test_aiter_tokens_yields_all() -> None:
    observed: dict = {}
    native = _fake_native(["a", "b", "c"], observed)

    async def run() -> List[str]:
        return [tok async for tok in aiter_tokens(native)]

    out = asyncio.run(run())
    assert out == ["a", "b", "c"]
    assert observed["stopped"] is False


def test_aiter_tokens_break_stops_and_joins() -> None:
    observed: dict = {}
    native = _fake_native([str(i) for i in range(1000)], observed)

    async def run() -> List[str]:
        seen: List[str] = []
        agen = aiter_tokens(native, maxsize=4)
        async for tok in agen:
            seen.append(tok)
            if len(seen) == 3:
                break
        await agen.aclose()
        return seen

    seen = asyncio.run(run())
    assert seen == ["0", "1", "2"]
    assert observed["stopped"] is True
    assert observed["emitted"] < 1000
    assert not any(t.name == "ra-stream" and t.is_alive() for t in threading.enumerate())


def test_aiter_tokens_reraises_worker_exception() -> None:
    native = _raising_native(["x", "y"])

    async def run() -> List[str]:
        got: List[str] = []
        async for tok in aiter_tokens(native):
            got.append(tok)
        return got

    with pytest.raises(RuntimeError, match="boom"):
        asyncio.run(run())
