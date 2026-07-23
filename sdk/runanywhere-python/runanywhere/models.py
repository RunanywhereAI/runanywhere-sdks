"""Loaded-model handle classes (LLM/VLM/Embedder/STT/TTS/Vad) — port of RunAnywhere.ts."""

from __future__ import annotations

import asyncio
import threading
from typing import Any, AsyncIterator, Callable, Iterator

import numpy as np

from . import events
from ._streaming import aiter_tokens, iter_tokens
from .errors import SDKException
from .options import generate_kwargs
from .results import LLMStreamEvent, Synthesis
from .stream_metrics import astream_with_metrics, stream_with_metrics
from .structured import (
    ToolCall,
    ToolRun,
    ToolSpec,
    object_grammar,
    parse_structured,
    tool_call_prompt,
    tool_call_schema,
)

__all__ = [
    "LLMModel",
    "VLMModel",
    "Embedder",
    "STTModel",
    "TTSVoice",
    "Vad",
]

# on_token callback type: called per token; returning False stops the native loop.
_OnToken = Callable[[str], "bool | None"]


class _GenerationGuard:
    """A non-reentrant, non-blocking guard: a second concurrent generate raises.

    Mirrors the other SDKs' single-in-flight-generation-per-model contract. Unlike a
    plain lock we never block the caller — a concurrent generate on the same model is a
    programming error, so we raise ``invalid_state`` immediately rather than deadlock or
    queue behind the in-flight stream.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()

    def acquire(self) -> None:
        if not self._lock.acquire(blocking=False):
            raise SDKException.invalid_state(
                "a generation is already in progress on this model"
            )

    def release(self) -> None:
        try:
            self._lock.release()
        except RuntimeError:
            # Already released (defensive) — never mask the original error.
            pass


def _guarded_iter(guard: _GenerationGuard, source: Iterator[str]) -> Iterator[str]:
    """Yield from ``source`` while holding ``guard`` for the whole stream lifetime.

    The guard is acquired before the first token and released when the stream is
    exhausted, closed (break), or raises — so the model is free for the next generate
    exactly when this one is truly done.
    """
    guard.acquire()
    try:
        yield from source
    finally:
        guard.release()


async def _aguarded_iter(
    guard: _GenerationGuard, source: AsyncIterator[str]
) -> AsyncIterator[str]:
    """Async twin of :func:`_guarded_iter`.

    Unlike sync ``yield from`` (which forwards ``GeneratorExit`` into the delegated
    generator on close), ``async for`` does NOT close ``source`` when this generator is
    ``aclose``d. We must close it explicitly in the ``finally`` — that runs
    ``aiter_tokens``'s own cleanup (stop the native loop, drain, join the worker) — and
    do so BEFORE releasing the guard, so the model stays reserved until the native call
    is truly stopped. Without this, an early-stopped async stream leaks the worker thread
    (the native decode keeps running) and the guard is freed while a native call is still
    in flight — allowing a second concurrent generation on the same handle.
    """
    guard.acquire()
    try:
        async for token in source:
            yield token
    finally:
        aclose = getattr(source, "aclose", None)
        if aclose is not None:
            await aclose()
        guard.release()


class LLMModel:
    """A loaded LLM. Text generation streams token-by-token; composition helpers
    (text/stream/structured/tool-call) build on that one stream with no new native
    calls."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._guard = _GenerationGuard()

    # -- native stream -------------------------------------------------------
    def _native_call(self, prompt: str, opts: dict) -> Callable[[_OnToken], None]:
        """Build the ``native_call`` closure ``iter_tokens`` drives on its worker
        thread. It captures the handle + prompt + generation kwargs and invokes
        ``core.generate(handle, prompt, on_token, **kwargs)``; ``on_token`` returning
        False stops the C decode loop (backpressure / cancellation)."""
        core = self._core
        handle = self._handle
        kwargs = generate_kwargs(**opts)

        def call(on_token: _OnToken) -> None:
            core.generate(handle, prompt, on_token, **kwargs)

        return call

    def generate(self, prompt: str, **opts: Any) -> Iterator[str]:
        """Stream the completion token-by-token."""
        source = iter_tokens(self._native_call(prompt, opts))
        return _guarded_iter(self._guard, source)

    def agenerate(self, prompt: str, **opts: Any) -> AsyncIterator[str]:
        """Async twin of :meth:`generate`."""
        source = aiter_tokens(self._native_call(prompt, opts))
        return _aguarded_iter(self._guard, source)

    # -- text ----------------------------------------------------------------
    def generate_text(self, prompt: str, **opts: Any) -> str:
        """Convenience: collect the full completion into one string."""
        out: list[str] = []
        for token in self.generate(prompt, **opts):
            out.append(token)
        return "".join(out)

    async def agenerate_text(self, prompt: str, **opts: Any) -> str:
        """Async twin of :meth:`generate_text`."""
        out: list[str] = []
        async for token in self.agenerate(prompt, **opts):
            out.append(token)
        return "".join(out)

    # -- stream (events + metrics) -------------------------------------------
    def generate_stream(self, prompt: str, **opts: Any) -> Iterator[LLMStreamEvent]:
        """Stream generation as :class:`LLMStreamEvent`; the final event carries the
        aggregated metrics and is also published as a ``GenerationEvent`` on the bus."""
        for event in stream_with_metrics(self.generate(prompt, **opts)):
            if event.is_final and event.result is not None:
                events.bus.emit(events.GenerationEvent(result=event.result))
            yield event

    async def agenerate_stream(self, prompt: str, **opts: Any) -> AsyncIterator[LLMStreamEvent]:
        """Async twin of :meth:`generate_stream`."""
        async for event in astream_with_metrics(self.agenerate(prompt, **opts)):
            if event.is_final and event.result is not None:
                events.bus.emit(events.GenerationEvent(result=event.result))
            yield event

    # -- structured ----------------------------------------------------------
    def generate_structured(self, prompt: str, schema: dict, **opts: Any) -> Any:
        """Constrain decoding to JSON matching ``schema`` (via a GBNF grammar) and
        return the parsed object. Output is guaranteed parseable."""
        opts["grammar"] = object_grammar(schema)
        return parse_structured(self.generate_text(prompt, **opts))

    async def agenerate_structured(self, prompt: str, schema: dict, **opts: Any) -> Any:
        """Async twin of :meth:`generate_structured`."""
        opts["grammar"] = object_grammar(schema)
        return parse_structured(await self.agenerate_text(prompt, **opts))

    def generate_object(self, prompt: str, schema: dict, **opts: Any) -> Any:
        """Deprecated alias for :meth:`generate_structured` (Electron API parity)."""
        return self.generate_structured(prompt, schema, **opts)

    async def agenerate_object(self, prompt: str, schema: dict, **opts: Any) -> Any:
        """Deprecated alias for :meth:`agenerate_structured` (Electron API parity)."""
        return await self.agenerate_structured(prompt, schema, **opts)

    # -- tool calling --------------------------------------------------------
    def generate_tool_call(self, prompt: str, tools: list[ToolSpec], **opts: Any) -> ToolCall:
        """Force the model to pick one of ``tools`` and emit a well-formed
        ``{name, arguments}`` call (grammar-constrained). The caller decides whether a
        tool is needed and executes the call."""
        if not tools:
            raise SDKException.validation_failed(
                field_path="tools", message="at least one tool is required"
            )
        opts["grammar"] = object_grammar(tool_call_schema(tools))
        parsed = parse_structured(self.generate_text(tool_call_prompt(prompt, tools), **opts))
        return _to_tool_call(parsed)

    async def agenerate_tool_call(
        self, prompt: str, tools: list[ToolSpec], **opts: Any
    ) -> ToolCall:
        """Async twin of :meth:`generate_tool_call`."""
        if not tools:
            raise SDKException.validation_failed(
                field_path="tools", message="at least one tool is required"
            )
        opts["grammar"] = object_grammar(tool_call_schema(tools))
        parsed = parse_structured(
            await self.agenerate_text(tool_call_prompt(prompt, tools), **opts)
        )
        return _to_tool_call(parsed)

    def generate_with_tools(self, prompt: str, tools: list[ToolSpec], **opts: Any) -> ToolRun:
        """Pick a tool AND run its ``execute`` function, returning
        ``ToolRun(name, arguments, result)``. Tools without an ``execute`` behave like
        :meth:`generate_tool_call` (no result)."""
        call = self.generate_tool_call(prompt, tools, **opts)
        tool = _find_tool(tools, call.name)
        if tool is not None and tool.execute is not None:
            result = tool.execute(call.arguments)
            return ToolRun(name=call.name, arguments=call.arguments, result=result)
        return ToolRun(name=call.name, arguments=call.arguments)

    async def agenerate_with_tools(
        self, prompt: str, tools: list[ToolSpec], **opts: Any
    ) -> ToolRun:
        """Async twin of :meth:`generate_with_tools`. An async tool ``execute`` result
        is awaited."""
        call = await self.agenerate_tool_call(prompt, tools, **opts)
        tool = _find_tool(tools, call.name)
        if tool is not None and tool.execute is not None:
            result = tool.execute(call.arguments)
            if asyncio.iscoroutine(result):
                result = await result
            return ToolRun(name=call.name, arguments=call.arguments, result=result)
        return ToolRun(name=call.name, arguments=call.arguments)

    # -- lifecycle -----------------------------------------------------------
    def unload(self) -> None:
        """Release the model and emit ``ModelUnloadedEvent('llm')``. Idempotent — a manual
        unload() followed by RunAnywhere.shutdown() (which also unloads tracked models) must
        not double-free or emit a second event."""
        if getattr(self, "_unloaded", False):
            return
        self._unloaded = True
        self._core.unload_model(self._handle)
        events.bus.emit(events.ModelUnloadedEvent(modality="llm"))


def _to_tool_call(parsed: Any) -> ToolCall:
    """Coerce the parsed ``{name, arguments}`` JSON into a :class:`ToolCall`."""
    if not isinstance(parsed, dict):
        raise SDKException.generation_failed(f"tool call was not an object: {parsed!r}")
    name = parsed.get("name")
    args = parsed.get("arguments", {})
    if not isinstance(name, str):
        raise SDKException.generation_failed(f"tool call missing a name: {parsed!r}")
    if not isinstance(args, dict):
        args = {}
    return ToolCall(name=name, arguments=args)


def _find_tool(tools: list[ToolSpec], name: str) -> ToolSpec | None:
    for tool in tools:
        if tool.name == name:
            return tool
    return None


class VLMModel:
    """A loaded vision-language model. Streams a caption/answer over an image + prompt."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._guard = _GenerationGuard()

    def _native_call(self, image_path: str, prompt: str) -> Callable[[_OnToken], None]:
        core = self._core
        handle = self._handle

        def call(on_token: _OnToken) -> None:
            core.generate_vlm(handle, image_path, prompt, on_token)

        return call

    def caption(self, image_path: str, prompt: str) -> Iterator[str]:
        """Stream a caption/answer over an image (JPEG/PNG path) + prompt."""
        source = iter_tokens(self._native_call(image_path, prompt))
        return _guarded_iter(self._guard, source)

    def acaption(self, image_path: str, prompt: str) -> AsyncIterator[str]:
        """Async twin of :meth:`caption`."""
        source = aiter_tokens(self._native_call(image_path, prompt))
        return _aguarded_iter(self._guard, source)

    def caption_text(self, image_path: str, prompt: str) -> str:
        """Convenience: collect the full caption into one string."""
        out: list[str] = []
        for token in self.caption(image_path, prompt):
            out.append(token)
        return "".join(out)

    async def acaption_text(self, image_path: str, prompt: str) -> str:
        """Async twin of :meth:`caption_text`."""
        out: list[str] = []
        async for token in self.acaption(image_path, prompt):
            out.append(token)
        return "".join(out)

    def unload(self) -> None:
        """Release the model and emit ``ModelUnloadedEvent('vlm')``. Idempotent."""
        if getattr(self, "_unloaded", False):
            return
        self._unloaded = True
        self._core.unload_vlm_model(self._handle)
        events.bus.emit(events.ModelUnloadedEvent(modality="vlm"))


class Embedder:
    """A loaded text embedder."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle

    def embed(self, text: str) -> np.ndarray:
        """Return the (L2-normalized) embedding of ``text`` as a float32 array."""
        return self._core.embed(self._handle, text)

    def unload(self) -> None:
        """Release the model and emit ``ModelUnloadedEvent('embedder')``. Idempotent."""
        if getattr(self, "_unloaded", False):
            return
        self._unloaded = True
        self._core.unload_embedding_model(self._handle)
        events.bus.emit(events.ModelUnloadedEvent(modality="embedder"))


class STTModel:
    """A loaded speech-to-text model. Transcription is blocking; ``atranscribe`` runs it
    on the default executor so it never blocks the event loop."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle

    def transcribe(self, pcm16: bytes) -> str:
        """Transcribe 16 kHz mono PCM16 audio bytes."""
        return self._core.transcribe(self._handle, pcm16)

    async def atranscribe(self, pcm16: bytes) -> str:
        """Async twin of :meth:`transcribe` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self.transcribe, pcm16)

    def unload(self) -> None:
        """Release the model and emit ``ModelUnloadedEvent('stt')``. Idempotent."""
        if getattr(self, "_unloaded", False):
            return
        self._unloaded = True
        self._core.unload_stt_model(self._handle)
        events.bus.emit(events.ModelUnloadedEvent(modality="stt"))


class TTSVoice:
    """A loaded text-to-speech voice. Synthesis is blocking; ``asynthesize`` runs it on
    the default executor."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle

    def synthesize(self, text: str) -> Synthesis:
        """Synthesize ``text`` to float32 PCM at the voice's native sample rate."""
        samples, sample_rate = self._core.synthesize(self._handle, text)
        return Synthesis(samples=samples, sample_rate=sample_rate)

    async def asynthesize(self, text: str) -> Synthesis:
        """Async twin of :meth:`synthesize` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self.synthesize, text)

    def unload(self) -> None:
        """Release the voice and emit ``ModelUnloadedEvent('tts')``. Idempotent."""
        if getattr(self, "_unloaded", False):
            return
        self._unloaded = True
        self._core.unload_tts_voice(self._handle)
        events.bus.emit(events.ModelUnloadedEvent(modality="tts"))


class Vad:
    """Voice activity detector (built-in energy VAD; no model needed). Feed 16 kHz mono
    float samples frame-by-frame to segment speech before STT."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle

    def detect(self, samples: np.ndarray) -> bool:
        """True if this frame of float samples contains speech."""
        return bool(self._core.vad_process(self._handle, samples))

    def is_speech_active(self) -> bool:
        """True if speech is currently active (debounced across frames)."""
        return bool(self._core.vad_is_active(self._handle))

    def set_threshold(self, threshold: float) -> None:
        """Adjust the energy threshold."""
        self._core.vad_set_threshold(self._handle, threshold)

    def reset(self) -> None:
        """Reset detector state (e.g. between utterances)."""
        self._core.vad_reset(self._handle)

    def close(self) -> None:
        """Release the detector. Idempotent (safe to close() then have shutdown() close again)."""
        if getattr(self, "_unloaded", False):
            return
        self._unloaded = True
        self._core.unload_vad(self._handle)
