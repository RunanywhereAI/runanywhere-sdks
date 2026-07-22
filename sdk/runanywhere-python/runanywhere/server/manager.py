"""Lazy, cached, multi-model manager backing the server (no fastapi import).

One process serves LLM + VLM + embedder + STT + TTS at once. Each distinct ``(kind, model_id)``
is loaded on first use (downloading if needed), cached, and guarded by its own ``asyncio.Lock``
so same-model requests serialize (the SDK is single-in-flight per model) while different models
run concurrently. Blocking loads run off the event loop via ``asyncio.to_thread``.

Models stay resident until :meth:`stop` (process exit) — matching llama.cpp ``llama-server`` and
``mlx_lm.server``. An idle-unload TTL is a documented fast-follow (it must never unload a model
mid-stream).
"""
from __future__ import annotations

import asyncio
from typing import Any, Callable

from ..client import RunAnywhere

# Per-modality defaults used when a request omits ``model``.
DEFAULT_LLM = "qwen2.5-0.5b"
DEFAULT_VLM = "smolvlm-256m"
DEFAULT_EMBEDDER = "minilm"
DEFAULT_STT = "whisper-tiny"
DEFAULT_TTS = "piper-lessac"


class ModelManager:
    """Loads + caches one instance of each requested model and serializes same-model calls."""

    def __init__(
        self,
        *,
        default_llm: str = DEFAULT_LLM,
        default_vlm: str = DEFAULT_VLM,
        default_embedder: str = DEFAULT_EMBEDDER,
        default_stt: str = DEFAULT_STT,
        default_tts: str = DEFAULT_TTS,
    ) -> None:
        self.ra = RunAnywhere()
        self.default_llm = default_llm
        self.default_vlm = default_vlm
        self.default_embedder = default_embedder
        self.default_stt = default_stt
        self.default_tts = default_tts
        self._cache: dict[tuple[str, str], object] = {}
        self._locks: dict[tuple[str, str], asyncio.Lock] = {}
        self._load_lock = asyncio.Lock()

    # -- lifecycle -----------------------------------------------------------
    def start(self) -> None:
        self.ra.initialize()

    def stop(self) -> None:
        self.ra.shutdown()

    def backends(self) -> list[str]:
        return self.ra.available_backends()

    def model_status(self) -> dict:
        try:
            return self.ra.model_status()
        except Exception:  # noqa: BLE001 — status is best-effort metadata, never fatal
            return {}

    # -- lazy load + cache ---------------------------------------------------
    async def _get(
        self, kind: str, model_id: str, loader: Callable[[str], Any]
    ) -> tuple[object, asyncio.Lock]:
        key = (kind, model_id)
        if key not in self._cache:
            async with self._load_lock:
                if key not in self._cache:  # double-checked under the lock
                    # Loading is blocking (download on first use + native load); off-thread it.
                    self._cache[key] = await asyncio.to_thread(loader, model_id)
                    self._locks[key] = asyncio.Lock()
        return self._cache[key], self._locks[key]

    async def llm(self, model_id: str):
        return await self._get("llm", model_id, self.ra.load_llm)

    async def vlm(self, model_id: str):
        return await self._get("vlm", model_id, self.ra.load_vlm)

    async def embedder(self, model_id: str):
        return await self._get("emb", model_id, self.ra.load_embedder)

    async def stt(self, model_id: str):
        return await self._get("stt", model_id, self.ra.load_stt)

    async def tts(self, model_id: str):
        return await self._get("tts", model_id, self.ra.load_tts)
