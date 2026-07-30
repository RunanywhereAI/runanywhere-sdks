"""Lifecycle + per-category serialization for the server (no fastapi import).

The SDK keeps one model resident per category, so the manager hands out one lock per
category: same-category requests serialize (and swap the resident model when a request names
a different id), while different categories run concurrently. Models stay resident until
:meth:`stop`, matching ``llama-server`` and ``mlx_lm.server``.
"""
from __future__ import annotations

import asyncio
from typing import Dict, List

import runanywhere as ra

from ..inputs import ModelFilter

# Per-modality defaults used when a request omits ``model``.
DEFAULT_LLM = "qwen2.5-0.5b"
DEFAULT_VLM = "smolvlm-256m"
DEFAULT_EMBEDDER = "minilm"
DEFAULT_STT = "whisper-tiny"
DEFAULT_TTS = "piper-lessac"


class ModelManager:
    """Owns SDK bring-up and the per-category request locks."""

    def __init__(
        self,
        *,
        default_llm: str = DEFAULT_LLM,
        default_vlm: str = DEFAULT_VLM,
        default_embedder: str = DEFAULT_EMBEDDER,
        default_stt: str = DEFAULT_STT,
        default_tts: str = DEFAULT_TTS,
    ) -> None:
        self.default_llm = default_llm
        self.default_vlm = default_vlm
        self.default_embedder = default_embedder
        self.default_stt = default_stt
        self.default_tts = default_tts
        self._locks: Dict[str, asyncio.Lock] = {}

    # -- lifecycle -----------------------------------------------------------
    def start(self) -> None:
        ra.initialize()

    def stop(self) -> None:
        ra.reset()

    def backends(self) -> List[str]:
        return ra.backends()

    def downloaded(self) -> set:
        """Ids of the models already on disk (best-effort metadata for /v1/models)."""
        try:
            return {model.id for model in ra.models.list(ModelFilter(downloaded=True))}
        except Exception:  # noqa: BLE001 — status is metadata, never fatal
            return set()

    # -- serialization -------------------------------------------------------
    def lock(self, category: str) -> asyncio.Lock:
        """The lock guarding one category's resident model."""
        return self._locks.setdefault(category, asyncio.Lock())
