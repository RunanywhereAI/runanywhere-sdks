"""The public namespaces: one per modality, each holding the spec's verbs."""

from __future__ import annotations

from .diarization import diarization
from .embeddings import embeddings
from .images import images
from .llm import llm
from .lora import lora
from .models import models
from .rag import RagSession, rag
from .rerank import rerank
from .segmentation import segmentation
from .stt import stt
from .tts import tts
from .vad import vad
from .vlm import vlm
from .voice import voice

__all__ = [
    "RagSession",
    "diarization",
    "embeddings",
    "images",
    "llm",
    "lora",
    "models",
    "rag",
    "rerank",
    "segmentation",
    "stt",
    "tts",
    "vad",
    "vlm",
    "voice",
]
