"""Tests for audio.py — asserts commons ``rac_audio_*`` delegation (no local DSP)."""

from __future__ import annotations

import numpy as np

from runanywhere.audio import (
    decode_wav,
    downsample,
    encode_wav,
    float32_to_pcm16,
    pcm16_bytes,
    pcm16_to_float32,
    rms,
    set_audio_native_for_tests,
)
from runanywhere.errors import SDKException


class _ForwardingNative:
    def __init__(self) -> None:
        self.calls: list[tuple] = []

    def audio_float32_to_pcm16(self, samples):
        self.calls.append(("float32_to_pcm16", len(samples)))
        return np.zeros(len(samples), dtype=np.int16)

    def audio_pcm16_to_float32(self, samples):
        self.calls.append(("pcm16_to_float32", len(samples)))
        return np.zeros(len(samples), dtype=np.float32)

    def audio_resample_f32(self, samples, in_rate, out_rate):
        self.calls.append(("resample", len(samples), in_rate, out_rate))
        n = max(1, int(len(samples) * out_rate / in_rate))
        return np.zeros(n, dtype=np.float32)

    def audio_compute_rms(self, samples):
        self.calls.append(("rms", len(samples)))
        return 0.25

    def audio_float32_to_wav(self, samples, sample_rate):
        self.calls.append(("encode_wav", len(samples), sample_rate))
        return b"\x01\x02\x03"

    def audio_wav_to_float32(self, data):
        self.calls.append(("decode_wav", len(data)))
        return 16000, np.array([0.0, 0.5], dtype=np.float32)


def setup_function() -> None:
    set_audio_native_for_tests(_ForwardingNative())


def teardown_function() -> None:
    set_audio_native_for_tests(None)


def test_float32_pcm16_and_bytes_forward_to_commons() -> None:
    native = _ForwardingNative()
    set_audio_native_for_tests(native)
    assert float32_to_pcm16(np.array([0.0, 1.0], dtype=np.float32)).shape == (2,)
    assert pcm16_to_float32(np.array([0, 1], dtype=np.int16)).shape == (2,)
    assert len(pcm16_bytes(np.array([0.0, 1.0], dtype=np.float32))) == 4
    assert [c[0] for c in native.calls] == [
        "float32_to_pcm16",
        "pcm16_to_float32",
        "float32_to_pcm16",
    ]


def test_downsample_rms_wav_forward_to_commons() -> None:
    native = _ForwardingNative()
    set_audio_native_for_tests(native)
    out = downsample(np.zeros(4800, dtype=np.float32), 48000, 16000)
    assert out.dtype == np.float32 and out.size > 0
    assert rms(np.array([0.5, 0.5], dtype=np.float32)) == 0.25
    assert rms(np.array([], dtype=np.float32)) == 0.0
    assert encode_wav(np.zeros(1, dtype=np.float32), 16000) == b"\x01\x02\x03"
    rate, samples = decode_wav(b"\x09\x09\x09")
    assert rate == 16000 and samples.tolist() == [0.0, 0.5]
    assert any(c[0] == "resample" for c in native.calls)
    assert any(c[0] == "rms" for c in native.calls)


def test_downsample_rejects_nonpositive_rates() -> None:
    set_audio_native_for_tests(_ForwardingNative())
    x = np.zeros(10, dtype=np.float32)
    for args in ((0, 16000), (16000, 0), (-1, 16000), (16000, -1)):
        try:
            downsample(x, *args)
        except SDKException:
            pass
        else:  # pragma: no cover
            raise AssertionError(f"expected SDKException for rates {args}")
