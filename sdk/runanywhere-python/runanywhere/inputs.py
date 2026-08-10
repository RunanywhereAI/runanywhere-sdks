"""Input value types shared by the namespaces (audio, image, messages, model refs)."""

from __future__ import annotations

import os
import struct
import tempfile
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Any, Dict, List, Optional

import numpy as np

from ._generated_defaults import AudioCaptureDefaults
from .audio import decode_wav, downsample, float32_to_pcm16, pcm16_bytes
from .errors import SDKException

__all__ = [
    "AudioEncoding",
    "AudioFormat",
    "AudioFormatSpec",
    "AudioInput",
    "ChatMessage",
    "ImageInput",
    "JsonSchema",
    "ModelCategory",
    "ModelRef",
    "ModelRegistration",
    "ModelFilter",
    "Role",
    "STT_SAMPLE_RATE",
    "ToolDefinition",
    "RagDocument",
]

#: A JSON Schema, as a plain dict (what ``llm.generate_structured`` constrains decoding to).
JsonSchema = Dict[str, Any]

# The bridge transcribes mono PCM16 at the capture rate only, so every AudioInput
# normalizes to that. The rate itself is centralized in idl/sdk_defaults.proto.
STT_SAMPLE_RATE = AudioCaptureDefaults.MIC_SAMPLE_RATE_HZ


class AudioEncoding(IntEnum):
    """How the bytes of an :class:`AudioInput` are laid out."""

    PCM16 = 0
    FLOAT32 = 1
    WAV = 2


class AudioFormat(IntEnum):
    """Container of synthesized audio (:class:`~runanywhere.results.Audio`)."""

    PCM = 0
    WAV = 1


@dataclass(frozen=True)
class AudioFormatSpec:
    """Sample layout of an :class:`AudioInput`."""

    encoding: AudioEncoding
    sample_rate: int
    channels: int = 1


@dataclass(frozen=True)
class AudioInput:
    """Audio handed to ``stt``, ``vad`` or ``diarization``, in any supported layout.

    Build one with :meth:`pcm16`, :meth:`float32`, :meth:`wav` or :meth:`file` rather than
    the constructor.
    """

    data: bytes
    format: AudioFormatSpec

    @classmethod
    def pcm16(cls, data: bytes, sample_rate: int = STT_SAMPLE_RATE, channels: int = 1) -> "AudioInput":
        """Wrap signed 16-bit little-endian PCM bytes."""
        return cls(bytes(data), AudioFormatSpec(AudioEncoding.PCM16, sample_rate, channels))

    @classmethod
    def float32(cls, samples: "np.ndarray | List[float]", sample_rate: int) -> "AudioInput":
        """Wrap float samples in [-1, 1]."""
        arr = np.asarray(samples, dtype=np.float32)
        return cls(arr.tobytes(), AudioFormatSpec(AudioEncoding.FLOAT32, sample_rate, 1))

    @classmethod
    def wav(cls, data: bytes) -> "AudioInput":
        """Wrap the bytes of a 16-bit RIFF/WAVE file."""
        return cls(bytes(data), AudioFormatSpec(AudioEncoding.WAV, 0, 1))

    @classmethod
    def file(cls, path: str) -> "AudioInput":
        """Read a 16-bit WAV file from disk.

        Raises:
            SDKException: the file cannot be read.
        """
        try:
            with open(path, "rb") as handle:
                return cls.wav(handle.read())
        except OSError as exc:
            raise SDKException.storage_error(f"could not read audio file {path}: {exc}") from exc

    def samples(self, sample_rate: int = STT_SAMPLE_RATE) -> np.ndarray:
        """Decode to mono float32 samples resampled to ``sample_rate``."""
        if self.format.encoding == AudioEncoding.WAV:
            rate, samples = decode_wav(self.data)
        elif self.format.encoding == AudioEncoding.FLOAT32:
            rate = self.format.sample_rate
            samples = np.frombuffer(self.data, dtype=np.float32)
        else:
            rate = self.format.sample_rate
            raw = np.frombuffer(self.data, dtype="<i2").astype(np.float32) / 32768.0
            samples = raw
        if self.format.encoding != AudioEncoding.WAV and self.format.channels > 1:
            samples = samples.reshape(-1, self.format.channels).mean(axis=1)
        if not rate:
            raise SDKException.invalid_input("audio input has no sample rate")
        samples = np.asarray(samples, dtype=np.float32)
        if rate > sample_rate:
            samples = downsample(samples, rate, sample_rate)
        elif rate < sample_rate and samples.size:
            # audio.downsample only decimates, so interpolate when the input is slower than
            # the target — passing it through at the wrong rate would garble transcription.
            count = int(round(samples.size * sample_rate / rate))
            samples = np.interp(
                np.linspace(0.0, samples.size - 1, count),
                np.arange(samples.size),
                samples,
            ).astype(np.float32)
        return np.ascontiguousarray(samples, dtype=np.float32)

    def to_pcm16(self, sample_rate: int = STT_SAMPLE_RATE) -> bytes:
        """Encode to signed 16-bit mono PCM bytes at ``sample_rate``."""
        return pcm16_bytes(self.samples(sample_rate))

    def duration_ms(self, sample_rate: int = STT_SAMPLE_RATE) -> int:
        """Length of the audio in milliseconds."""
        return int(round(len(self.samples(sample_rate)) / sample_rate * 1000))


def _bmp24(data: bytes, width: int, height: int) -> bytes:
    """Encode packed RGB bytes as a 24-bit BMP (the container the engines' image loader reads)."""
    if width <= 0 or height <= 0:
        raise SDKException.invalid_input("image width and height must be positive")
    if len(data) != width * height * 3:
        raise SDKException.invalid_input(
            f"raw RGB data is {len(data)} bytes, expected {width * height * 3}"
        )
    pad = b"\x00" * ((-(width * 3)) % 4)  # BMP scanlines are 4-byte aligned
    rgb = np.frombuffer(data, dtype=np.uint8).reshape(height, width, 3)
    bgr = rgb[::-1, :, ::-1]  # bottom-up scanlines, BGR channel order
    pixels = b"".join(row.tobytes() + pad for row in np.ascontiguousarray(bgr))
    size = 54 + len(pixels)
    header = struct.pack("<2sIHHI", b"BM", size, 0, 0, 54)
    info = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 0, 0, 0, 0)
    return header + info + pixels


@dataclass
class ImageInput:
    """Image handed to ``vlm`` or ``segmentation``.

    Build one with :meth:`file`, :meth:`bytes` or :meth:`raw_rgb`.
    ``segmentation`` needs decoded pixels — use :meth:`raw_rgb` (there is no image
    decoder in commons). ``vlm`` accepts a path or encoded bytes via :meth:`resolve_path`.
    """

    path: Optional[str] = None
    data: Optional[bytes] = None
    width: int = 0
    height: int = 0
    # Packed RGB8 pixels when built via :meth:`raw_rgb` (``rac_segmentation_image_t``).
    rgb: Optional[bytes] = None
    _temp: bool = False

    @classmethod
    def file(cls, path: str) -> "ImageInput":
        """Reference an image already on disk (JPEG/PNG/BMP)."""
        if not os.path.isfile(path):
            raise SDKException.invalid_input(f"image file not found: {path}")
        return cls(path=path)

    @classmethod
    def bytes(cls, data: bytes) -> "ImageInput":
        """Wrap encoded image bytes (JPEG/PNG/BMP)."""
        return cls(data=bytes(data))

    @classmethod
    def raw_rgb(cls, data: bytes, width: int, height: int) -> "ImageInput":
        """Wrap packed 8-bit RGB pixels, row-major from the top-left."""
        raw = bytes(data)
        return cls(
            data=_bmp24(raw, width, height),
            width=width,
            height=height,
            rgb=raw,
        )

    def resolve_path(self) -> str:
        """Return a filesystem path for this image, materializing bytes into a temp file."""
        if self.path is not None:
            return self.path
        if self.data is None:
            raise SDKException.invalid_input("image input carries neither a path nor bytes")
        fd, path = tempfile.mkstemp(suffix=".img")
        with os.fdopen(fd, "wb") as handle:
            handle.write(self.data)
        self.path = path
        self._temp = True
        return path

    def release(self) -> None:
        """Delete the temp file created by :meth:`resolve_path` (no-op for disk images)."""
        if self._temp and self.path is not None:
            try:
                os.unlink(self.path)
            except OSError:
                pass
            self.path = None
            self._temp = False


class Role(IntEnum):
    """Author of a :class:`ChatMessage`."""

    SYSTEM = 0
    USER = 1
    ASSISTANT = 2
    TOOL = 3


@dataclass
class ChatMessage:
    """One turn of a conversation passed to ``llm.generate``."""

    role: Role
    content: str
    tool_call_id: Optional[str] = None


@dataclass(frozen=True)
class ModelRef:
    """A model id, plus the voice to use when the model is a TTS voice bank."""

    id: str
    voice: Optional[str] = None


class ModelCategory(IntEnum):
    """What a model does. Values mirror ``rac_model_category_t`` (the C ABI, not proto wire)."""

    LANGUAGE = 0
    SPEECH_RECOGNITION = 1
    SPEECH_SYNTHESIS = 2
    VISION = 3
    IMAGE_GENERATION = 4
    MULTIMODAL = 5
    AUDIO = 6
    EMBEDDING = 7
    VOICE_ACTIVITY_DETECTION = 8
    SPEAKER_DIARIZATION = 9
    SEMANTIC_SEGMENTATION = 10
    UNKNOWN = 99


class InferenceFramework(IntEnum):
    """Engine that executes a model. Values mirror ``rac_inference_framework_t``."""

    ONNX = 0
    LLAMACPP = 1
    FOUNDATION_MODELS = 2
    SYSTEM_TTS = 3
    FLUID_AUDIO = 4
    BUILTIN = 5
    NONE = 6
    MLX = 7
    COREML = 8
    SHERPA = 12
    QHEXRT = 13
    UNKNOWN = 99


@dataclass
class ModelRegistration:
    """A model to add to the registry: one url, an archive, or a set of files.

    Exactly one of ``url``, ``files`` or ``path`` describes where the weights come from.
    """

    id: str
    category: ModelCategory
    url: Optional[str] = None
    files: List[str] = field(default_factory=list)
    archive: bool = False
    path: Optional[str] = None
    primary: Optional[str] = None
    framework: Optional[InferenceFramework] = None
    label: Optional[str] = None
    size_bytes: int = 0


@dataclass
class ModelFilter:
    """Narrows :meth:`runanywhere.models.list` to a category and/or download state."""

    category: Optional[ModelCategory] = None
    downloaded: Optional[bool] = None


@dataclass
class ToolDefinition:
    """A tool the model may call, described by its JSON-Schema parameters."""

    name: str
    parameters: JsonSchema = field(default_factory=lambda: {"type": "object"})
    description: Optional[str] = None


@dataclass
class RagDocument:
    """A document to ingest into a :class:`~runanywhere.api.rag.RagSession`."""

    text: str
    metadata: Optional[Dict[str, str]] = None
    id: str = ""

    @classmethod
    def file(cls, path: str) -> "RagDocument":
        """Read a UTF-8 text file, tagging the document with its path.

        Raises:
            SDKException: the file cannot be read.
        """
        try:
            with open(path, "r", encoding="utf-8") as handle:
                text = handle.read()
        except OSError as exc:
            raise SDKException.storage_error(f"could not read document {path}: {exc}") from exc
        return cls(text=text, metadata={"source": path}, id=os.path.basename(path))
