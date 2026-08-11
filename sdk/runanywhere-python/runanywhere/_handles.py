"""Internal handle wrappers around the opaque integer handles the native bridge returns.

Not part of the public surface: the namespaces in :mod:`runanywhere.api` own the public verbs
and hold these handles through :mod:`runanywhere._runtime`. Each class is a thin adapter over
``_core`` — one in-flight generation per handle, cancel on teardown, idempotent unload.
"""

from __future__ import annotations

import asyncio
import queue
import threading
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Callable, Dict, Iterator, List, Optional, TypeVar

import numpy as np

from ._generation import StreamDelta
from ._streaming import aiter_tokens, iter_tokens
from .errors import SDKException
from .results import AppliedAdapter, FinishReason, Synthesis

__all__ = [
    "DiarizationModel",
    "DiffusionModel",
    "Embedder",
    "LLMModel",
    "STTModel",
    "SegmentationModel",
    "TTSVoice",
    "Vad",
    "VLMModel",
    "VoiceAgent",
]

# Gap message shared by the LoRA and diarization handle methods below: both bindings are
# new (native/module.cpp's lora_apply_proto/... and load_diarization_model/diarize/...), so a
# native _core built before this change simply lacks the attribute — fail with a clear,
# actionable message instead of an opaque AttributeError.
def _rebuild_gap(name: str, symbols: str) -> SDKException:
    return SDKException.unsupported_capability(
        name,
        f"this native/_core build predates the {name.split('.')[0]} bindings "
        f"({symbols} are not exported by native/module.cpp) — rebuild the native extension",
    )


# on_token callback type: called per token; returning False stops the native loop.
_OnToken = Callable[[str], "bool | None"]

_T = TypeVar("_T")


class _GenerationGuard:
    """A non-reentrant, non-blocking guard: a second concurrent generate raises.

    A concurrent generate on the same model is a programming error, so we raise
    ``invalid_state`` immediately rather than deadlock or queue behind the in-flight stream.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()

    def acquire(self) -> None:
        if not self._lock.acquire(blocking=False):
            raise SDKException.invalid_state("a generation is already in progress on this model")

    def release(self) -> None:
        try:
            self._lock.release()
        except RuntimeError:
            # Already released (defensive) — never mask the original error.
            pass


def _guarded_iter(guard: _GenerationGuard, source: Iterator[_T]) -> Iterator[_T]:
    """Yield from ``source`` while holding ``guard`` for the whole stream lifetime."""
    guard.acquire()
    try:
        yield from source
    finally:
        guard.release()


async def _aguarded_iter(guard: _GenerationGuard, source: AsyncIterator[_T]) -> AsyncIterator[_T]:
    """Async twin of :func:`_guarded_iter`."""
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
    """A loaded LLM handle; ``generate`` yields commons-typed stream deltas."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._guard = _GenerationGuard()
        self._unloaded = False
        self._lora_applied: Dict[str, Optional[float]] = {}

    def _ensure_loaded(self) -> None:
        if self._unloaded:
            raise SDKException.invalid_state("model has been unloaded")

    def cancel(self) -> None:
        """Request cancellation of an in-flight generate (safe from another thread)."""
        if hasattr(self._core, "llm_cancel_proto"):
            try:
                self._core.llm_cancel_proto()
            except Exception:  # noqa: BLE001
                pass
        self._core.cancel_generate(self._handle)

    def generate(self, prompt: str, kwargs: dict) -> Iterator[StreamDelta]:
        """Stream commons-typed deltas (answer vs thinking), then a terminal marker."""
        self._ensure_loaded()
        has_proto = hasattr(self._core, "llm_generate_stream_proto")
        prefer_legacy = bool(getattr(self._core, "prefer_legacy_generate", False))
        needs_proto = bool(kwargs.get("structured_schema"))
        if needs_proto and not prefer_legacy:
            if not has_proto:
                raise SDKException.not_implemented(
                    "structured_output requires llm_generate_stream_proto "
                    "(commons owns schema→GBNF); this native/_core build has no proto stream"
                )
            source = self._iter_proto(prompt, kwargs)
        elif has_proto and not prefer_legacy:
            source = self._iter_proto(prompt, kwargs)
        else:
            source = self._iter_legacy(prompt, kwargs)
        return _guarded_iter(self._guard, source)

    def agenerate(self, prompt: str, kwargs: dict) -> AsyncIterator[StreamDelta]:
        """Async twin of :meth:`generate`."""
        self._ensure_loaded()

        async def _agen() -> AsyncIterator[StreamDelta]:
            # Drive the sync generator off-loop so cancel still reaches the native call.
            loop = asyncio.get_running_loop()
            queue: asyncio.Queue = asyncio.Queue()
            _DONE = object()
            _ERR = object()
            error: list = []

            def worker() -> None:
                try:
                    for delta in self.generate(prompt, kwargs):
                        loop.call_soon_threadsafe(queue.put_nowait, delta)
                    loop.call_soon_threadsafe(queue.put_nowait, _DONE)
                except BaseException as exc:  # noqa: BLE001
                    error.append(exc)
                    loop.call_soon_threadsafe(queue.put_nowait, _ERR)

            thread = threading.Thread(target=worker, name="ra-llm-agen", daemon=True)
            thread.start()
            try:
                while True:
                    item = await queue.get()
                    if item is _DONE:
                        break
                    if item is _ERR:
                        raise error[0]
                    yield item  # type: ignore[misc]
            finally:
                self.cancel()
                await asyncio.shield(loop.run_in_executor(None, thread.join))

        return _agen()

    def _iter_proto(self, prompt: str, kwargs: dict) -> Iterator[StreamDelta]:
        from ._llm_stream import build_llm_generate_request, decode_llm_stream_event

        request = build_llm_generate_request(
            prompt,
            max_tokens=kwargs.get("max_tokens"),
            temperature=kwargs.get("temperature"),
            top_p=kwargs.get("top_p"),
            top_k=kwargs.get("top_k"),
            system_prompt=kwargs.get("system_prompt"),
            grammar=kwargs.get("grammar"),
            structured_schema=kwargs.get("structured_schema"),
            disable_thinking=kwargs.get("disable_thinking"),
            include_thoughts=bool(kwargs.get("include_thoughts")),
            stop_sequences=kwargs.get("stop_sequences"),
        )
        q: queue.Queue = queue.Queue()
        _DONE = object()
        _ERR = object()
        error: list = []

        def on_event(raw: bytes) -> bool:
            try:
                deltas, terminal = decode_llm_stream_event(bytes(raw))
                for delta in deltas:
                    q.put(delta)
                if terminal is not None:
                    q.put(
                        StreamDelta(
                            is_terminal=True,
                            finish_reason=terminal.finish_reason,
                            usage=dict(terminal.usage) if terminal.usage else None,
                            final_text=terminal.text,
                            final_thinking=terminal.thinking_text,
                        )
                    )
            except BaseException as exc:  # noqa: BLE001
                error.append(exc)
                q.put(_ERR)
                return False
            return True

        def worker() -> None:
            try:
                self._core.llm_generate_stream_proto(request, on_event)
                q.put(_DONE)
            except BaseException as exc:  # noqa: BLE001
                error.append(exc)
                q.put(_ERR)

        thread = threading.Thread(target=worker, name="ra-llm-proto", daemon=True)
        thread.start()
        try:
            while True:
                item = q.get()
                if item is _DONE:
                    break
                if item is _ERR:
                    raise error[0]
                yield item  # type: ignore[misc]
        finally:
            self.cancel()
            thread.join()

    def _iter_legacy(self, prompt: str, kwargs: dict) -> Iterator[StreamDelta]:
        bridge_kwargs = {
            k: v
            for k, v in kwargs.items()
            if k
            in (
                "max_tokens",
                "temperature",
                "top_p",
                "top_k",
                "system_prompt",
                "disable_thinking",
                "structured_schema",
            )
        }
        q: queue.Queue = queue.Queue()
        _DONE = object()
        _ERR = object()
        error: list = []

        def on_delta(text: str, is_thinking: bool = False) -> bool:
            q.put(StreamDelta(text=text, is_thinking=bool(is_thinking)))
            return True

        def on_token(token: str) -> bool:
            return on_delta(token, False)

        def worker() -> None:
            try:
                if hasattr(self._core, "generate_typed"):
                    self._core.generate_typed(self._handle, prompt, on_delta, **bridge_kwargs)
                else:
                    self._core.generate(self._handle, prompt, on_token, **bridge_kwargs)
                q.put(
                    StreamDelta(
                        is_terminal=True,
                        finish_reason=FinishReason(
                            int(getattr(self._core, "finish_reason", FinishReason.UNSPECIFIED))
                        ),
                        usage=getattr(self._core, "usage", None),
                        final_text=getattr(self._core, "final_text", None),
                        final_thinking=getattr(self._core, "final_thinking", None),
                    )
                )
                q.put(_DONE)
            except BaseException as exc:  # noqa: BLE001
                error.append(exc)
                q.put(_ERR)

        thread = threading.Thread(target=worker, name="ra-llm-legacy", daemon=True)
        thread.start()
        try:
            while True:
                item = q.get()
                if item is _DONE:
                    break
                if item is _ERR:
                    raise error[0]
                yield item  # type: ignore[misc]
        finally:
            self.cancel()
            thread.join()

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_model(self._handle)

    # -- LoRA (lifecycle proto ABI — commons owns optional scale resolution) -
    def lora_apply(self, adapter_path: str, scale: Optional[float]) -> None:
        """Load and apply a LoRA adapter; unset ``scale`` is left unset for commons."""
        self._ensure_loaded()
        if not hasattr(self._core, "lora_apply_proto"):
            raise _rebuild_gap("lora.apply", "lora_apply_proto")
        from ._proto import lora_options_pb2 as lora_pb

        req = lora_pb.LoraApplyRequest()
        req.keep_existing = True
        adapter = req.adapters.add()
        # Path-only SDK: use the filesystem path as both id and path.
        adapter.adapter_id = adapter_path
        adapter.adapter_path = adapter_path
        if scale is not None:
            adapter.scale = float(scale)
        raw = self._core.lora_apply_proto(req.SerializeToString())
        result = lora_pb.LoraApplyResult()
        result.ParseFromString(bytes(raw))
        if result.HasField("error"):
            raise SDKException.generation_failed(
                result.error.message or "lora apply failed"
            )
        # Mirror commons-resolved scales from the apply result (never invent 1.0).
        for info in result.adapters:
            key = info.adapter_id or info.adapter_path or adapter_path
            self._lora_applied[key] = float(info.scale)

    def lora_remove(self, adapter_path: str) -> None:
        """Remove one adapter by the path used in :meth:`lora_apply`."""
        self._ensure_loaded()
        if not hasattr(self._core, "lora_remove_proto"):
            raise _rebuild_gap("lora.remove", "lora_remove_proto")
        from ._proto import lora_options_pb2 as lora_pb

        req = lora_pb.LoraRemoveRequest()
        req.adapter_ids.append(adapter_path)
        self._core.lora_remove_proto(req.SerializeToString())
        self._lora_applied.pop(adapter_path, None)

    def lora_remove_all(self) -> None:
        """Remove every adapter currently applied."""
        self._ensure_loaded()
        if not hasattr(self._core, "lora_remove_proto"):
            raise _rebuild_gap("lora.remove_all", "lora_remove_proto")
        from ._proto import lora_options_pb2 as lora_pb

        req = lora_pb.LoraRemoveRequest()
        req.clear_all = True
        self._core.lora_remove_proto(req.SerializeToString())
        self._lora_applied.clear()

    def lora_list(self) -> List[AppliedAdapter]:
        """Adapters currently applied — prefers commons ``lora_list_proto`` when bound."""
        if hasattr(self._core, "lora_list_proto"):
            from ._proto import lora_options_pb2 as lora_pb

            raw = self._core.lora_list_proto(b"")
            state = lora_pb.LoraState()
            state.ParseFromString(bytes(raw))
            out: List[AppliedAdapter] = []
            for info in state.loaded_adapters:
                if not info.applied:
                    continue
                out.append(
                    AppliedAdapter(
                        id=info.adapter_id or info.adapter_path,
                        scale=float(info.scale),
                    )
                )
            return out
        return [
            AppliedAdapter(id=path, scale=float(scale if scale is not None else 0.0))
            for path, scale in self._lora_applied.items()
        ]


class VLMModel:
    """A loaded vision-language model handle."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._guard = _GenerationGuard()
        self._unloaded = False

    def _native_call(self, image_path: str, prompt: str, kwargs: dict) -> Callable[[_OnToken], None]:
        core = self._core
        handle = self._handle
        # The VLM bridge entry point takes the sampling subset only.
        allowed = ("max_tokens", "temperature", "top_p", "top_k", "system_prompt")
        opts = {k: v for k, v in kwargs.items() if k in allowed}

        def call(on_token: _OnToken) -> None:
            core.generate_vlm(handle, image_path, prompt, on_token, **opts)

        return call

    def cancel(self) -> None:
        """Request cancellation of an in-flight generate (safe from another thread)."""
        self._core.cancel_generate_vlm(self._handle)

    def generate(self, image_path: str, prompt: str, kwargs: dict) -> Iterator[str]:
        """Stream an answer over an image + prompt."""
        source = iter_tokens(self._native_call(image_path, prompt, kwargs), on_stop=self.cancel)
        return _guarded_iter(self._guard, source)

    def agenerate(self, image_path: str, prompt: str, kwargs: dict) -> AsyncIterator[str]:
        """Async twin of :meth:`generate`."""
        source = aiter_tokens(self._native_call(image_path, prompt, kwargs), on_stop=self.cancel)
        return _aguarded_iter(self._guard, source)

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_vlm_model(self._handle)


class Embedder:
    """A loaded text-embedding model handle."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def embed(self, text: str) -> np.ndarray:
        """Return the embedding of ``text`` as a float32 array."""
        return self._core.embed(self._handle, text)

    def embed_batch(self, texts: List[str]) -> List[np.ndarray]:
        """Embed several texts, one array per input, in input order."""
        return list(self._core.embed_batch(self._handle, texts))

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_embedding_model(self._handle)


class STTModel:
    """A loaded speech-to-text model handle."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def transcribe(self, pcm16: bytes) -> str:
        """Transcribe 16 kHz mono PCM16 audio bytes."""
        return self._core.transcribe(self._handle, pcm16)

    async def atranscribe(self, pcm16: bytes) -> str:
        """Async twin of :meth:`transcribe` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self.transcribe, pcm16)

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_stt_model(self._handle)


class TTSVoice:
    """A loaded text-to-speech voice handle."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def synthesize(self, text: str) -> Synthesis:
        """Synthesize ``text`` to float32 PCM at the voice's native sample rate."""
        out = self._core.synthesize(self._handle, text)
        # Newer bridges return (samples, sample_rate, duration_ms); older builds
        # return the 2-tuple and leave commons duration unsourced (0).
        if len(out) >= 3:
            samples, sample_rate, duration_ms = out[0], out[1], int(out[2])
        else:
            samples, sample_rate, duration_ms = out[0], out[1], 0
        return Synthesis(samples=samples, sample_rate=sample_rate, duration_ms=duration_ms)

    async def asynthesize(self, text: str) -> Synthesis:
        """Async twin of :meth:`synthesize` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self.synthesize, text)

    def unload(self) -> None:
        """Release the voice. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_tts_voice(self._handle)


class Vad:
    """A voice-activity detector handle (built-in energy VAD, or a loaded model VAD)."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def load_model(self, model_path: str, *, id: str | None = None, name: str | None = None) -> None:
        """Upgrade this detector to a model VAD (a directory of Silero/sherpa files)."""
        self._core.load_vad_model(self._handle, model_path, id, name)

    def process(self, samples: np.ndarray) -> bool:
        """True if this frame of float samples contains speech."""
        return bool(self._core.vad_process(self._handle, samples))

    def is_speech_active(self) -> bool:
        """True if speech is currently active (debounced across frames)."""
        return bool(self._core.vad_is_active(self._handle))

    def set_threshold(self, threshold: float) -> None:
        """Adjust the activation threshold."""
        self._core.vad_set_threshold(self._handle, threshold)

    def reset(self) -> None:
        """Reset detector state between utterances."""
        self._core.vad_reset(self._handle)

    def unload(self) -> None:
        """Release the detector. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_vad(self._handle)

    # The runtime's teardown loop calls unload(); close() is the ergonomic alias.
    close = unload


class DiarizationModel:
    """A loaded speaker-diarization model handle (offline batch; ONNX Sortformer)."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def diarize(
        self,
        samples: np.ndarray,
        *,
        sample_rate_hz: int,
        threshold: Optional[float] = None,
        minimum_duration_ms: Optional[int] = None,
        merge_gap_ms: Optional[int] = None,
    ) -> dict:
        """Diarize float32 mono samples; returns ``{segments, speaker_count, duration_ms}``."""
        if not hasattr(self._core, "diarize"):
            raise _rebuild_gap("diarization.diarize", "load_diarization_model / diarize")
        return self._core.diarize(
            self._handle,
            samples,
            sample_rate_hz=sample_rate_hz,
            threshold=threshold,
            minimum_duration_ms=minimum_duration_ms,
            merge_gap_ms=merge_gap_ms,
        )

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_diarization_model(self._handle)


class SegmentationModel:
    """A loaded semantic-segmentation model handle (offline batch; ONNX)."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def segment(
        self,
        data: bytes,
        *,
        width: int,
        height: int,
        pixel_format: int = 1,
        stride_bytes: int = 0,
        include_diagnostic_rgba: bool = False,
    ) -> dict:
        """Segment packed RGB/RGBA pixels; returns ``{width, height, class_mask, classes}``."""
        if not hasattr(self._core, "segment"):
            raise _rebuild_gap(
                "segmentation.segment", "load_segmentation_model / segment"
            )
        return self._core.segment(
            self._handle,
            data,
            width,
            height,
            pixel_format=pixel_format,
            stride_bytes=stride_bytes or None,
            include_diagnostic_rgba=include_diagnostic_rgba,
        )

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_segmentation_model(self._handle)


class DiffusionModel:
    """A loaded diffusion (text-to-image) model handle — CoreML builds only."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def generate(
        self,
        prompt: str,
        *,
        negative_prompt: Optional[str] = None,
        width: Optional[int] = None,
        height: Optional[int] = None,
        steps: Optional[int] = None,
        guidance_scale: Optional[float] = None,
        seed: Optional[int] = None,
    ) -> dict:
        """Generate an image; returns ``{image_data, width, height, seed, ...}``."""
        if not hasattr(self._core, "generate_image"):
            raise _rebuild_gap("images.generate", "load_diffusion_model / generate_image")
        return self._core.generate_image(
            self._handle,
            prompt,
            negative_prompt=negative_prompt,
            width=width,
            height=height,
            steps=steps,
            guidance_scale=guidance_scale,
            seed=seed,
        )

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_diffusion_model(self._handle)


class VoiceAgent:
    """A standalone voice-agent handle (file-PCM turns; STT → LLM → TTS)."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._unloaded = False

    def process_turn(self, pcm16: bytes) -> dict:
        """Run one turn over 16 kHz mono PCM16; returns a decoded result dict."""
        if not hasattr(self._core, "process_voice_turn"):
            raise _rebuild_gap(
                "voice.process_turn", "create_voice_agent / process_voice_turn"
            )
        return self._core.process_voice_turn(self._handle, pcm16)

    async def aprocess_turn(self, pcm16: bytes) -> dict:
        """Async twin of :meth:`process_turn` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self.process_turn, pcm16)

    def unload(self) -> None:
        """Release the agent. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.destroy_voice_agent(self._handle)

    close = unload
