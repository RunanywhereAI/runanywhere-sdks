"""Tests for the audio DSP + WAV codec (float32<->pcm16, downsample, rms, WAV)."""

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
)


def test_float32_pcm16_round_trip_within_tolerance() -> None:
    x = np.linspace(-1.0, 1.0, 2001, dtype=np.float32)
    back = pcm16_to_float32(float32_to_pcm16(x))
    # Round-trip error stays within half a quantization step (1/32768).
    assert np.max(np.abs(back - x)) <= (1.0 / 32768) + 1e-7


def test_float32_pcm16_clamps_out_of_range() -> None:
    x = np.array([-2.0, -1.0, 0.0, 1.0, 2.0], dtype=np.float32)
    pcm = float32_to_pcm16(x)
    assert pcm.dtype == np.int16
    assert pcm.tolist() == [-32768, -32768, 0, 32767, 32767]


def test_float32_pcm16_rounds_half_up() -> None:
    # 0.5 quantization steps must round toward +inf (JS Math.round semantics).
    x = np.array([0.5 / 32768, 1.5 / 32768, 2.5 / 32768], dtype=np.float32)
    assert float32_to_pcm16(x).tolist() == [1, 2, 3]


def test_pcm16_bytes_length_and_little_endian() -> None:
    x = np.array([0.0, 0.5, -0.5, 1.0], dtype=np.float32)
    raw = pcm16_bytes(x)
    assert isinstance(raw, (bytes, bytearray))
    assert len(raw) == 2 * x.shape[0]  # 2 bytes per int16 sample
    # Little-endian: reinterpret and compare to the pcm16 values.
    expected = float32_to_pcm16(x)
    got = np.frombuffer(raw, dtype="<i2")
    assert got.tolist() == expected.tolist()
    # 0.5 -> round(0.5 * 32768) = 16384 -> bytes 0x00 0x40 (little-endian).
    assert raw[2] == 0x00 and raw[3] == 0x40


def test_downsample_length_and_no_op_paths() -> None:
    x = np.arange(48000, dtype=np.float32)
    out = downsample(x, 48000, 16000)
    # ratio 3 -> floor(48000 / 3) = 16000 samples.
    assert out.shape[0] == 16000
    assert out.dtype == np.float32
    # Equal rate -> unchanged copy.
    same = downsample(x, 16000, 16000)
    assert same.shape[0] == x.shape[0]
    assert np.array_equal(same, x)
    assert same is not x
    # Upsample request -> unchanged copy.
    up = downsample(x, 16000, 48000)
    assert up.shape[0] == x.shape[0]


def test_downsample_block_average_values() -> None:
    x = np.array([0.0, 2.0, 4.0, 6.0], dtype=np.float32)
    out = downsample(x, 2, 1)  # ratio 2, out_len 2 -> means of pairs
    assert out.shape[0] == 2
    assert np.allclose(out, [1.0, 5.0])


def test_downsample_rejects_nonpositive_rates() -> None:
    x = np.zeros(10, dtype=np.float32)
    for args in ((0, 16000), (16000, 0), (-1, 16000), (16000, -1)):
        try:
            downsample(x, *args)
        except ValueError:
            pass
        else:  # pragma: no cover
            raise AssertionError(f"expected ValueError for rates {args}")


def test_rms_of_known_signal() -> None:
    # Constant amplitude 0.5 -> RMS 0.5.
    assert abs(rms(np.full(1000, 0.5, dtype=np.float32)) - 0.5) < 1e-6
    # Full-scale sine -> RMS ~ 1/sqrt(2).
    t = np.linspace(0, 2 * np.pi, 10000, endpoint=False, dtype=np.float32)
    sine = np.sin(t).astype(np.float32)
    assert abs(rms(sine) - (1.0 / np.sqrt(2))) < 1e-3
    # Empty frame -> 0.
    assert rms(np.array([], dtype=np.float32)) == 0.0


def test_encode_wav_header() -> None:
    samples = np.array([0.0, 0.25, -0.25, 0.5], dtype=np.float32)
    sr = 16000
    wav = encode_wav(samples, sr)
    data_bytes = 2 * samples.shape[0]
    assert len(wav) == 44 + data_bytes
    assert wav[0:4] == b"RIFF"
    assert int.from_bytes(wav[4:8], "little") == 36 + data_bytes
    assert wav[8:12] == b"WAVE"
    assert wav[12:16] == b"fmt "
    assert int.from_bytes(wav[16:20], "little") == 16  # fmt chunk size
    assert int.from_bytes(wav[20:22], "little") == 1  # PCM
    assert int.from_bytes(wav[22:24], "little") == 1  # mono
    assert int.from_bytes(wav[24:28], "little") == sr
    assert int.from_bytes(wav[28:32], "little") == sr * 2  # byte rate
    assert int.from_bytes(wav[32:34], "little") == 2  # block align
    assert int.from_bytes(wav[34:36], "little") == 16  # bits per sample
    assert wav[36:40] == b"data"
    assert int.from_bytes(wav[40:44], "little") == data_bytes


def test_decode_wav_round_trip() -> None:
    samples = np.linspace(-1.0, 1.0, 512, dtype=np.float32)
    sr = 22050
    wav = encode_wav(samples, sr)
    got_sr, got = decode_wav(wav)
    assert got_sr == sr
    assert got.dtype == np.float32
    assert got.shape[0] == samples.shape[0]
    # WAV is 16-bit PCM: round-trip within one quantization step.
    assert np.max(np.abs(got - samples)) <= (1.0 / 32768) + 1e-6


def test_decode_wav_rejects_non_riff() -> None:
    try:
        decode_wav(b"NOPE" + b"\x00" * 40)
    except ValueError:
        pass
    else:  # pragma: no cover
        raise AssertionError("expected ValueError for non-RIFF input")


def test_decode_wav_downmixes_stereo() -> None:
    # Hand-build a 2-channel WAV: L=+1.0, R=-1.0 -> mono downmix ~0.
    sr = 16000
    channels = 2
    frames = 4
    pcm = np.empty(frames * channels, dtype="<i2")
    pcm[0::2] = 32767   # left
    pcm[1::2] = -32768  # right
    data = pcm.tobytes()
    header = bytearray(44)
    header[0:4] = b"RIFF"
    header[4:8] = (36 + len(data)).to_bytes(4, "little")
    header[8:12] = b"WAVE"
    header[12:16] = b"fmt "
    header[16:20] = (16).to_bytes(4, "little")
    header[20:22] = (1).to_bytes(2, "little")
    header[22:24] = channels.to_bytes(2, "little")
    header[24:28] = sr.to_bytes(4, "little")
    header[28:32] = (sr * channels * 2).to_bytes(4, "little")
    header[32:34] = (channels * 2).to_bytes(2, "little")
    header[34:36] = (16).to_bytes(2, "little")
    header[36:40] = b"data"
    header[40:44] = len(data).to_bytes(4, "little")
    got_sr, got = decode_wav(bytes(header) + data)
    assert got_sr == sr
    assert got.shape[0] == frames
    # (+1.0 + -1.0)/2 ~= 0 (within one LSB).
    assert np.max(np.abs(got)) < 2.0 / 32768
