"""Curated built-in model catalog so callers can load models by id instead of files."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

ModelType = Literal["llm", "vlm", "embedder", "stt", "tts"]

_HF = "https://huggingface.co"
_K2 = "https://github.com/k2-fsa/sherpa-onnx/releases/download"


@dataclass
class CatalogFile:
    """A single downloadable file. ``name`` is the save-as filename (electron field ``as``)."""

    url: str
    name: str  # electron field 'as' — filename to save as inside the model's dir


@dataclass
class CatalogEntry:
    """One catalog model: its type, files to download, and load metadata."""

    type: str
    files: list[CatalogFile]
    primary: str
    archive: bool = False
    mmproj: str | None = None
    label: str | None = None
    params: str | None = None
    size_mb: int | None = None
    heavy: bool = False


def _llm(
    repo: str, file: str, label: str, params: str, size_mb: int, heavy: bool = False
) -> CatalogEntry:
    return CatalogEntry(
        type="llm",
        files=[CatalogFile(url=f"{_HF}/{repo}/resolve/main/{file}", name="model.gguf")],
        primary="model.gguf",
        label=label,
        params=params,
        size_mb=size_mb,
        heavy=heavy,
    )


def _vlm(
    repo: str,
    file: str,
    mm: str,
    label: str,
    params: str,
    size_mb: int,
    heavy: bool = False,
) -> CatalogEntry:
    return CatalogEntry(
        type="vlm",
        files=[
            CatalogFile(url=f"{_HF}/{repo}/resolve/main/{file}", name="model.gguf"),
            CatalogFile(url=f"{_HF}/{repo}/resolve/main/{mm}", name="mmproj.gguf"),
        ],
        primary="model.gguf",
        mmproj="mmproj.gguf",
        label=label,
        params=params,
        size_mb=size_mb,
        heavy=heavy,
    )


def _whisper(size: str, label: str, size_mb: int) -> CatalogEntry:
    return CatalogEntry(
        type="stt",
        files=[
            CatalogFile(
                url=f"{_K2}/asr-models/sherpa-onnx-whisper-{size}.tar.bz2",
                name="whisper.tar.bz2",
            )
        ],
        archive=True,
        primary=f"sherpa-onnx-whisper-{size}",
        label=label,
        size_mb=size_mb,
    )


def _piper(voice: str, label: str, size_mb: int) -> CatalogEntry:
    return CatalogEntry(
        type="tts",
        files=[
            CatalogFile(
                url=f"{_K2}/tts-models/vits-piper-en_US-{voice}-medium.tar.bz2",
                name="piper.tar.bz2",
            )
        ],
        archive=True,
        primary=f"vits-piper-en_US-{voice}-medium",
        label=label,
        size_mb=size_mb,
    )


CATALOG: dict[str, CatalogEntry] = {
    # ---- LLMs (GGUF, llama.cpp) ----
    "smollm2-135m": _llm(
        "bartowski/SmolLM2-135M-Instruct-GGUF",
        "SmolLM2-135M-Instruct-Q4_K_M.gguf",
        "SmolLM2 135M",
        "135M",
        92,
    ),
    "smollm2-360m": _llm(
        "bartowski/SmolLM2-360M-Instruct-GGUF",
        "SmolLM2-360M-Instruct-Q4_K_M.gguf",
        "SmolLM2 360M",
        "360M",
        258,
    ),
    "smollm2-1.7b": _llm(
        "bartowski/SmolLM2-1.7B-Instruct-GGUF",
        "SmolLM2-1.7B-Instruct-Q4_K_M.gguf",
        "SmolLM2 1.7B",
        "1.7B",
        1007,
    ),
    "qwen2.5-0.5b": _llm(
        "bartowski/Qwen2.5-0.5B-Instruct-GGUF",
        "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf",
        "Qwen2.5 0.5B",
        "0.5B",
        398,
    ),
    "qwen2.5-1.5b": _llm(
        "bartowski/Qwen2.5-1.5B-Instruct-GGUF",
        "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
        "Qwen2.5 1.5B",
        "1.5B",
        940,
    ),
    "qwen2.5-3b": _llm(
        "bartowski/Qwen2.5-3B-Instruct-GGUF",
        "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
        "Qwen2.5 3B",
        "3B",
        1841,
        True,
    ),
    "llama-3.2-1b": _llm(
        "bartowski/Llama-3.2-1B-Instruct-GGUF",
        "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        "Llama 3.2 1B",
        "1B",
        770,
    ),
    "llama-3.2-3b": _llm(
        "bartowski/Llama-3.2-3B-Instruct-GGUF",
        "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        "Llama 3.2 3B",
        "3B",
        1926,
        True,
    ),
    "gemma-2-2b": _llm(
        "bartowski/gemma-2-2b-it-GGUF",
        "gemma-2-2b-it-Q4_K_M.gguf",
        "Gemma 2 2B",
        "2B",
        1629,
        True,
    ),
    "phi-3.5-mini": _llm(
        "bartowski/Phi-3.5-mini-instruct-GGUF",
        "Phi-3.5-mini-instruct-Q4_K_M.gguf",
        "Phi 3.5 mini",
        "3.8B",
        2283,
        True,
    ),
    # ---- VLMs (GGUF + mmproj, llama.cpp mtmd) ----
    "smolvlm-256m": _vlm(
        "ggml-org/SmolVLM-256M-Instruct-GGUF",
        "SmolVLM-256M-Instruct-Q8_0.gguf",
        "mmproj-SmolVLM-256M-Instruct-Q8_0.gguf",
        "SmolVLM 256M",
        "256M",
        300,
    ),
    "smolvlm-500m": _vlm(
        "ggml-org/SmolVLM-500M-Instruct-GGUF",
        "SmolVLM-500M-Instruct-Q8_0.gguf",
        "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf",
        "SmolVLM 500M",
        "500M",
        521,
    ),
    "smolvlm-2.2b": _vlm(
        "ggml-org/SmolVLM-Instruct-GGUF",
        "SmolVLM-Instruct-Q8_0.gguf",
        "mmproj-SmolVLM-Instruct-Q8_0.gguf",
        "SmolVLM 2.2B",
        "2.2B",
        2402,
        True,
    ),
    "smolvlm2-500m": _vlm(
        "ggml-org/SmolVLM2-500M-Video-Instruct-GGUF",
        "SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
        "mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
        "SmolVLM2 500M (video)",
        "500M",
        521,
    ),
    "qwen2-vl-2b": _vlm(
        "ggml-org/Qwen2-VL-2B-Instruct-GGUF",
        "Qwen2-VL-2B-Instruct-Q8_0.gguf",
        "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
        "Qwen2-VL 2B",
        "2B",
        2247,
        True,
    ),
    # ---- Embeddings (ONNX) ----
    "minilm": CatalogEntry(
        type="embedder",
        files=[
            CatalogFile(
                url=f"{_HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx",
                name="model.onnx",
            ),
            CatalogFile(
                url=f"{_HF}/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt",
                name="vocab.txt",
            ),
        ],
        primary="model.onnx",
        label="all-MiniLM-L6-v2",
        params="22M",
        size_mb=90,
    ),
    # ---- Speech-to-text (Whisper via sherpa-onnx) ----
    "whisper-tiny": _whisper("tiny.en", "Whisper tiny (en)", 75),
    "whisper-base": _whisper("base.en", "Whisper base (en)", 142),
    "whisper-small": _whisper("small.en", "Whisper small (en)", 466),
    # ---- Text-to-speech (Piper via sherpa-onnx) ----
    "piper-lessac": _piper("lessac", "Piper · Lessac", 64),
    "piper-amy": _piper("amy", "Piper · Amy", 64),
    "piper-ryan": _piper("ryan", "Piper · Ryan", 64),
}


def is_catalog_id(id_or_path: str) -> bool:
    """True iff ``id_or_path`` is a known built-in catalog id."""
    return id_or_path in CATALOG
