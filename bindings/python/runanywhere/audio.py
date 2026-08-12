"""Audio DSP + WAV codec — thin forwards to commons ``rac_audio_*`` via the native bridge.

PCM conversion, resample, RMS, and WAV encode/decode are owned by commons. This
module never re-implements those formulas.
"""

from __future__ import annotations

from typing import Any, Optional, Protocol, Tuple

import numpy as np

from .errors import SDKException

__all__ = [
    "decode_wav",
    "downsample",
    "encode_wav",
    "float32_to_pcm16",
    "pcm16_bytes",
    "pcm16_to_float32",
    "rms",
    "set_audio_native_for_tests",
]


class _AudioNative(Protocol):
    def audio_float32_to_pcm16(self, samples: np.ndarray) -> np.ndarray: ...
    def audio_pcm16_to_float32(self, samples: np.ndarray) -> np.ndarray: ...
    def audio_resample_f32(self, samples: np.ndarray, in_rate: int, out_rate: int) -> np.ndarray: ...
    def audio_compute_rms(self, samples: np.ndarray) -> float: ...
    def audio_float32_to_wav(self, samples: np.ndarray, sample_rate: int) -> bytes: ...
    def audio_wav_to_float32(self, data: bytes) -> Tuple[int, np.ndarray]: ...


_injected: Optional[_AudioNative] = None


def set_audio_native_for_tests(native: Optional[_AudioNative]) -> None:
    """Test hook — unit tests inject a fake so they do not need the compiled ``_core``."""
    global _injected
    _injected = native


def _audio_native() -> Any:
    if _injected is not None:
        return _injected
    from ._native import get_core

    return get_core()


def float32_to_pcm16(x: np.ndarray) -> np.ndarray:
    """Clamp+scale float32 samples in [-1,1] to signed 16-bit PCM via commons."""
    a = np.ascontiguousarray(np.asarray(x, dtype=np.float32))
    return np.asarray(_audio_native().audio_float32_to_pcm16(a), dtype=np.int16)


def pcm16_to_float32(x: np.ndarray) -> np.ndarray:
    """Convert signed 16-bit PCM samples back to float32 in [-1,1] via commons."""
    a = np.ascontiguousarray(np.asarray(x, dtype=np.int16))
    return np.asarray(_audio_native().audio_pcm16_to_float32(a), dtype=np.float32)


def pcm16_bytes(x: np.ndarray) -> bytes:
    """Little-endian int16 bytes for float32 samples — the shape STT.transcribe wants."""
    pcm = float32_to_pcm16(x)
    return pcm.astype("<i2").tobytes()


def downsample(x: np.ndarray, in_rate: int, out_rate: int) -> np.ndarray:
    """Resample mono float32 audio via commons (``rac_audio_resample_f32``)."""
    if out_rate <= 0 or in_rate <= 0:
        raise SDKException.invalid_input("downsample: rates must be positive")
    a = np.ascontiguousarray(np.asarray(x, dtype=np.float32))
    return np.asarray(
        _audio_native().audio_resample_f32(a, int(in_rate), int(out_rate)), dtype=np.float32
    )


def rms(x: np.ndarray) -> float:
    """Root-mean-square level of a float32 frame via commons (``rac_audio_compute_rms``)."""
    a = np.ascontiguousarray(np.asarray(x, dtype=np.float32))
    if a.size == 0:
        return 0.0
    return float(_audio_native().audio_compute_rms(a))


def encode_wav(samples: np.ndarray, sample_rate: int) -> bytes:
    """Encode mono float32 samples as a 16-bit PCM WAV via commons."""
    a = np.ascontiguousarray(np.asarray(samples, dtype=np.float32))
    return bytes(_audio_native().audio_float32_to_wav(a, int(sample_rate)))


def decode_wav(data: bytes) -> tuple[int, np.ndarray]:
    """Decode a 16-bit PCM WAV byte array to (sample_rate, mono float32) via commons."""
    sample_rate, samples = _audio_native().audio_wav_to_float32(bytes(data))
    return int(sample_rate), np.asarray(samples, dtype=np.float32)
