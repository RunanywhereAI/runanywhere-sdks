"""Pure DSP + WAV codec for the voice pipeline (float32<->pcm16, resample, WAV)."""

from __future__ import annotations

import numpy as np

# The STT model wants 16 kHz mono PCM16 bytes; the TTS model returns float32 at its
# own sample rate. These helpers bridge to/from those formats. Ported from the
# Electron SDK audio.ts DSP + WAV layer (MicRecorder / SpeakerPlayer are browser-only
# and intentionally omitted).

_INT16_SCALE = 0x8000  # 32768


def float32_to_pcm16(x: np.ndarray) -> np.ndarray:
    """Clamp+scale float32 samples in [-1,1] to signed 16-bit PCM.

    Symmetric scale (round(s * 32768)) clamped to the int16 range — round-trip error
    stays within half a quantization step except at exactly +1.0.
    """
    a = np.asarray(x, dtype=np.float32)
    s = np.clip(a, -1.0, 1.0)
    # np.round is banker's rounding; JS Math.round rounds half toward +inf. Match JS.
    scaled = np.floor(s.astype(np.float64) * _INT16_SCALE + 0.5)
    scaled = np.clip(scaled, -32768, 32767)
    return scaled.astype(np.int16)


def pcm16_to_float32(x: np.ndarray) -> np.ndarray:
    """Convert signed 16-bit PCM samples back to float32 in [-1,1]."""
    a = np.asarray(x, dtype=np.int16)
    return (a.astype(np.float32) / _INT16_SCALE).astype(np.float32)


def pcm16_bytes(x: np.ndarray) -> bytes:
    """Little-endian int16 bytes for float32 samples — the shape STT.transcribe wants."""
    pcm = float32_to_pcm16(x)
    return pcm.astype("<i2").tobytes()


def downsample(x: np.ndarray, in_rate: int, out_rate: int) -> np.ndarray:
    """Resample mono float32 audio from `in_rate` to `out_rate` by block averaging.

    Returns a copy unchanged when the rates match or when upsampling (we only need
    downsampling, e.g. a 48 kHz mic capture down to the 16 kHz the STT model wants).
    """
    if out_rate <= 0 or in_rate <= 0:
        raise ValueError("downsample: rates must be positive")
    a = np.asarray(x, dtype=np.float32)
    if out_rate >= in_rate:
        return a.copy()
    ratio = in_rate / out_rate
    out_len = int(a.shape[0] // ratio)
    out = np.zeros(out_len, dtype=np.float32)
    for i in range(out_len):
        start = int(np.floor(i * ratio))
        end = min(a.shape[0], int(np.floor((i + 1) * ratio)))
        if end > start:
            out[i] = np.float32(a[start:end].mean(dtype=np.float64))
        else:
            out[i] = 0.0
    return out


def rms(x: np.ndarray) -> float:
    """Root-mean-square level of a frame — a cheap energy gate for VAD."""
    a = np.asarray(x, dtype=np.float32)
    if a.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(a.astype(np.float64) ** 2)))


_RIFF_HEADER_BYTES = 44


def encode_wav(samples: np.ndarray, sample_rate: int) -> bytes:
    """Encode mono float32 samples as a 16-bit PCM WAV file (RIFF) byte array."""
    pcm = float32_to_pcm16(samples)
    data = pcm.astype("<i2").tobytes()
    data_bytes = len(data)
    header = bytearray(_RIFF_HEADER_BYTES)
    header[0:4] = b"RIFF"
    header[4:8] = (36 + data_bytes).to_bytes(4, "little")
    header[8:12] = b"WAVE"
    header[12:16] = b"fmt "
    header[16:20] = (16).to_bytes(4, "little")  # fmt chunk size
    header[20:22] = (1).to_bytes(2, "little")  # PCM
    header[22:24] = (1).to_bytes(2, "little")  # mono
    header[24:28] = int(sample_rate).to_bytes(4, "little")
    header[28:32] = (int(sample_rate) * 2).to_bytes(4, "little")  # byte rate (mono, 16-bit)
    header[32:34] = (2).to_bytes(2, "little")  # block align
    header[34:36] = (16).to_bytes(2, "little")  # bits per sample
    header[36:40] = b"data"
    header[40:44] = data_bytes.to_bytes(4, "little")
    return bytes(header) + data


def decode_wav(data: bytes) -> tuple[int, np.ndarray]:
    """Decode a 16-bit PCM WAV byte array to (sample_rate, mono float32 samples).

    Scans RIFF sub-chunks for `fmt ` and `data`; stereo is down-mixed to mono.
    """
    b = bytes(data)
    if len(b) < 12 or b[0:4] != b"RIFF" or b[8:12] != b"WAVE":
        raise ValueError("decode_wav: not a RIFF/WAVE file")
    channels = 1
    sample_rate = 16000
    bits = 16
    data_offset = -1
    data_len = 0
    p = 12
    while p + 8 <= len(b):
        chunk_id = b[p:p + 4]
        size = int.from_bytes(b[p + 4:p + 8], "little")
        body = p + 8
        if chunk_id == b"fmt ":
            channels = int.from_bytes(b[body + 2:body + 4], "little") or 1
            sample_rate = int.from_bytes(b[body + 4:body + 8], "little") or 16000
            bits = int.from_bytes(b[body + 14:body + 16], "little") or 16
        elif chunk_id == b"data":
            data_offset = body
            data_len = size
            break
        p = body + size + (size % 2)  # chunks are word-aligned
    if data_offset < 0:
        raise ValueError("decode_wav: no data chunk")
    if bits != 16:
        raise ValueError(f"decode_wav: only 16-bit PCM supported (got {bits}-bit)")
    frames = data_len // 2 // channels
    end = data_offset + frames * channels * 2
    raw = np.frombuffer(b[data_offset:end], dtype="<i2")
    if channels > 1:
        raw = raw.reshape(frames, channels)
        out = (raw.astype(np.float64) / _INT16_SCALE).mean(axis=1).astype(np.float32)
    else:
        out = (raw.astype(np.float32) / _INT16_SCALE).astype(np.float32)
    return sample_rate, np.asarray(out, dtype=np.float32)
