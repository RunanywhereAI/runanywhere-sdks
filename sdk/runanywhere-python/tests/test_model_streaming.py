"""LLMModel streaming through the PUBLIC wrapper — guard semantics + async early-stop cleanup.

These drive `LLMModel.generate`/`agenerate` (which wrap the raw `iter_tokens`/`aiter_tokens`
bridge in `_guarded_iter`/`_aguarded_iter`), not the bridge directly — so they cover the
single-in-flight guard and, critically, that an early-stopped ASYNC stream still runs the
inner cleanup (stop + join the worker) before releasing the guard. All hermetic (fake core).
"""
from __future__ import annotations

import asyncio
import threading

import pytest

from runanywhere.errors import ErrorCode, SDKException
from runanywhere.models import LLMModel


class FakeCore:
    """Fake native core: generate() pushes tokens on the worker thread, honouring the
    on_token False return (stop request) exactly like the real C decode loop."""

    def __init__(self, tokens):
        self._tokens = tokens
        self.emitted = 0
        self.stopped = False
        self.last_kwargs = None

    def generate(self, handle, prompt, on_token, **kwargs):
        self.last_kwargs = kwargs
        for tok in self._tokens:
            keep = on_token(tok)
            self.emitted += 1
            if keep is False:
                self.stopped = True
                return

    def unload_model(self, handle):
        pass


def _no_live_worker() -> bool:
    return not any(t.name == "ra-stream" and t.is_alive() for t in threading.enumerate())


# --------------------------------------------------------------------------- sync path
def test_generate_text_collects():
    m = LLMModel(FakeCore(["Par", "is"]), 1)
    assert m.generate_text("Capital of France?") == "Paris"


def test_generate_stream_final_event():
    m = LLMModel(FakeCore(["a", "b"]), 1)
    events = list(m.generate_stream("hi"))
    assert "".join(e.token for e in events if not e.is_final) == "ab"
    finals = [e for e in events if e.is_final]
    assert len(finals) == 1 and finals[0].result is not None and finals[0].result.text == "ab"


def test_generate_forwards_options_to_native():
    core = FakeCore(["x"])
    LLMModel(core, 1).generate_text("hi", max_tokens=7, temperature=0.0, disable_thinking=True)
    assert core.last_kwargs["max_tokens"] == 7
    assert core.last_kwargs["temperature"] == 0.0
    assert core.last_kwargs["disable_thinking"] is True


def test_concurrent_generate_raises_invalid_state():
    m = LLMModel(FakeCore([str(i) for i in range(100)]), 1)
    g1 = m.generate("a")
    next(g1)  # first token -> acquires the single-in-flight guard, held until g1 closes
    try:
        with pytest.raises(SDKException) as ei:
            list(m.generate("b"))
        assert ei.value.code == ErrorCode.INVALID_STATE
    finally:
        g1.close()
    # After releasing, a fresh generation succeeds.
    assert m.generate_text("c") is not None


def test_sync_break_releases_guard_and_joins():
    core = FakeCore([str(i) for i in range(1000)])
    m = LLMModel(core, 1)
    seen = []
    g = m.generate("hi")
    for tok in g:
        seen.append(tok)
        if len(seen) == 3:
            break
    g.close()
    assert seen == ["0", "1", "2"] and core.stopped is True
    assert _no_live_worker()
    assert m.generate_text("again") is not None  # guard released


# --------------------------------------------------------------------------- async path (the fix)
def test_async_early_stop_joins_worker_and_frees_guard():
    """Regression: breaking + aclose()ing an async stream must stop+join the worker (no leak)
    and release the guard. Before the _aguarded_iter fix, ``async for`` did not close the inner
    aiter_tokens generator on GeneratorExit, so its stop+join finally never ran.

    We assert state INSIDE the still-open loop right after aclose(): ``asyncio.run()`` calls
    ``loop.shutdown_asyncgens()`` on exit, which would close the leaked inner generator and mask
    the bug — but in a long-running loop (a server) the worker leaks for the loop's lifetime and
    the guard is freed while the native call is still in flight. That in-loop window is the bug.
    """
    core = FakeCore([str(i) for i in range(1000)])
    m = LLMModel(core, 1)
    obs = {}

    async def run():
        seen = []
        agen = m.agenerate("hi")
        async for tok in agen:
            seen.append(tok)
            if len(seen) == 3:
                break
        await agen.aclose()
        # Inspect immediately, before asyncio.run's shutdown_asyncgens can clean up.
        obs["seen"] = seen
        obs["stopped"] = core.stopped
        obs["emitted"] = core.emitted
        obs["worker_alive"] = any(t.name == "ra-stream" and t.is_alive() for t in threading.enumerate())
        obs["guard_locked"] = m._guard._lock.locked()

    asyncio.run(run())
    assert obs["seen"] == ["0", "1", "2"]
    assert obs["stopped"] is True  # aclose() propagated the stop into the native loop
    assert obs["emitted"] < 1000  # it did NOT run to completion
    assert obs["worker_alive"] is False  # worker was joined, not leaked
    assert obs["guard_locked"] is False  # guard released only AFTER the worker stopped


def test_agenerate_text_collects():
    m = LLMModel(FakeCore(["Par", "is"]), 1)
    assert asyncio.run(m.agenerate_text("hi")) == "Paris"
