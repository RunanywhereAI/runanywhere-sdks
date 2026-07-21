"""Real-world robustness integration tests on the native ``_core`` + cached models (gated).

Like ``test_smoke``, these exercise the REAL native extension against REAL models under
``~/.runanywhere/models`` and self-skip when either is absent. They go past the single-call
smoke checks: a full STT->LLM->TTS voice turn, multi-turn chat with history, repeated async
generations, the per-model single-in-flight guard, and error paths (bad model, use after
unload).
"""
from __future__ import annotations

import asyncio
import os
import sys

_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

from conftest import _NATIVE_AVAILABLE, model_ready, requires_model, requires_native  # noqa: E402

from runanywhere import RunAnywhere, SDKException  # noqa: E402

LLM_ID = "qwen2.5-0.5b"
_VOICE_MODELS = ("whisper-tiny", LLM_ID, "piper-lessac")

requires_voice = pytest.mark.skipif(
    not (_NATIVE_AVAILABLE and all(model_ready(m) for m in _VOICE_MODELS)),
    reason=f"voice-agent test needs {' + '.join(_VOICE_MODELS)} cached",
)


@requires_voice
def test_voice_agent_end_to_end() -> None:
    """A full STT -> LLM -> TTS turn over 1s of silence: structure + callbacks, no crash."""
    with RunAnywhere() as ra:
        agent = ra.create_voice_agent(
            ra.load_stt("whisper-tiny"),
            ra.load_llm(LLM_ID),
            ra.load_tts("piper-lessac"),
            system_prompt="Answer in one short sentence.",
        )
        seen: dict[str, object] = {"transcript": None, "tokens": 0}
        turn = agent.process_turn(
            bytes(16000 * 2),  # 1s of 16 kHz mono PCM16 silence
            on_transcript=lambda t: seen.__setitem__("transcript", t),
            on_token=lambda _tok: seen.__setitem__("tokens", int(seen["tokens"]) + 1),
        )
        assert isinstance(turn.transcript, str)
        assert isinstance(turn.response, str)
        assert turn.audio.sample_rate > 0
        assert turn.audio.samples.ndim == 1
        assert seen["transcript"] is not None  # the on_transcript callback fired


@requires_model(LLM_ID)
def test_multi_turn_chat_keeps_history_and_resets() -> None:
    with RunAnywhere() as ra:
        chat = ra.create_chat(ra.load_llm(LLM_ID), system="You are terse. Answer briefly.")
        r1 = chat.send_text("What is the capital of France?")
        r2 = chat.send_text("And of Japan?")
        assert r1.strip() and r2.strip()

        roles = [m.role for m in chat.messages]
        assert roles.count("user") == 2 and roles.count("assistant") == 2
        assert chat.messages[0].role == "system"  # system pinned at head

        chat.reset()
        assert [m.role for m in chat.messages] == ["system"]  # reset keeps only system


@requires_model(LLM_ID)
def test_async_repeated_generations() -> None:
    """Several sequential async generations on one model all complete (no deadlock/leak)."""
    with RunAnywhere() as ra:
        llm = ra.load_llm(LLM_ID)

        async def run() -> list[str]:
            out = []
            for q in ("Capital of France? One word.", "2+2? One number.", "Sky color? One word."):
                out.append(await llm.agenerate_text(q, max_tokens=16))
            return out

        results = asyncio.run(run())
        assert len(results) == 3 and all(isinstance(r, str) and r.strip() for r in results)


@requires_model(LLM_ID)
def test_single_in_flight_guard_blocks_concurrent_generate() -> None:
    """A second generation on the SAME model while one is live raises invalid_state."""
    with RunAnywhere() as ra:
        llm = ra.load_llm(LLM_ID)
        live = llm.generate("Count to a hundred slowly.", max_tokens=128)
        next(live)  # start it -> acquires the per-model guard (held until close/exhaust)
        try:
            with pytest.raises(SDKException):
                list(llm.generate("A concurrent prompt.", max_tokens=8))
        finally:
            live.close()  # release the guard; stop the worker
        # After releasing, a fresh generation works again.
        assert llm.generate_text("Capital of France? One word.", max_tokens=8).strip()


@requires_native
def test_load_nonexistent_model_raises_sdk_exception() -> None:
    with RunAnywhere() as ra:
        with pytest.raises(SDKException):
            ra.load_llm(os.path.join(os.sep, "no", "such", "dir", "model.gguf"))


@requires_model(LLM_ID)
def test_generate_after_unload_fails_cleanly() -> None:
    """Using a model after unload() must raise at the Python layer, never crash the process."""
    with RunAnywhere() as ra:
        llm = ra.load_llm(LLM_ID)
        assert isinstance(llm.generate_text("Hi.", max_tokens=4), str)
        llm.unload()
        with pytest.raises(Exception):  # invalid handle -> SDKException/RuntimeError, not a segfault
            list(llm.generate("Should fail after unload.", max_tokens=4))
