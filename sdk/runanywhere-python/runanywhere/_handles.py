"""Internal handle wrappers around the opaque integer handles the native bridge returns.

Not part of the public surface: the namespaces in :mod:`runanywhere.api` own the public verbs
and hold these handles through :mod:`runanywhere._runtime`. Each class is a thin adapter over
``_core`` — one in-flight generation per handle, cancel on teardown, idempotent unload.
"""

from __future__ import annotations

import asyncio
import threading
from typing import Any, AsyncIterator, Callable, Iterator, List

import numpy as np

from ._streaming import aiter_tokens, iter_tokens
from .errors import SDKException
from .results import Synthesis

__all__ = [
    "Embedder",
    "LLMModel",
    "STTModel",
    "TTSVoice",
    "Vad",
    "VLMModel",
]

# on_token callback type: called per token; returning False stops the native loop.
_OnToken = Callable[[str], "bool | None"]


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


def _guarded_iter(guard: _GenerationGuard, source: Iterator[str]) -> Iterator[str]:
    """Yield from ``source`` while holding ``guard`` for the whole stream lifetime."""
    guard.acquire()
    try:
        yield from source
    finally:
        guard.release()


async def _aguarded_iter(guard: _GenerationGuard, source: AsyncIterator[str]) -> AsyncIterator[str]:
    """Async twin of :func:`_guarded_iter`.

    ``async for`` does not close ``source`` when this generator is ``aclose``d, so we close it
    explicitly before releasing the guard — that runs ``aiter_tokens``'s cleanup (stop the
    native loop, drain, join the worker) while the model is still reserved.
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
    """A loaded LLM handle; ``generate`` streams tokens straight off the native decode loop."""

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._guard = _GenerationGuard()
        self._unloaded = False

    def _ensure_loaded(self) -> None:
        if self._unloaded:
            raise SDKException.invalid_state("model has been unloaded")

    def _native_call(self, prompt: str, kwargs: dict) -> Callable[[_OnToken], None]:
        self._ensure_loaded()
        core = self._core
        handle = self._handle

        def call(on_token: _OnToken) -> None:
            core.generate(handle, prompt, on_token, **kwargs)

        return call

    def cancel(self) -> None:
        """Request cancellation of an in-flight generate (safe from another thread)."""
        self._core.cancel_generate(self._handle)

    def generate(self, prompt: str, kwargs: dict) -> Iterator[str]:
        """Stream the completion token-by-token."""
        self._ensure_loaded()
        source = iter_tokens(self._native_call(prompt, kwargs), on_stop=self.cancel)
        return _guarded_iter(self._guard, source)

    def agenerate(self, prompt: str, kwargs: dict) -> AsyncIterator[str]:
        """Async twin of :meth:`generate`."""
        self._ensure_loaded()
        source = aiter_tokens(self._native_call(prompt, kwargs), on_stop=self.cancel)
        return _aguarded_iter(self._guard, source)

    def unload(self) -> None:
        """Release the model. Idempotent."""
        if self._unloaded:
            return
        self._unloaded = True
        self._core.unload_model(self._handle)


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
        samples, sample_rate = self._core.synthesize(self._handle, text)
        return Synthesis(samples=samples, sample_rate=sample_rate)

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
