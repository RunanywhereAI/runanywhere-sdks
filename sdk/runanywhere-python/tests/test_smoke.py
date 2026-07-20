"""Gated integration / system smoke tests over the REAL native core + REAL cached models.

These are the only tests that touch the compiled ``runanywhere._core`` extension and the
models under ``~/.runanywhere/models``. The whole module is skipped unless the native core
loads (``requires_native``), and every test is additionally skipped unless the specific
model it needs is already downloaded (``requires_model(<id>)``) — nothing here downloads a
model or builds native code, so on a clean machine the entire module is a no-op (skipped).

Run them, once a native build + cached models exist, with::

    pytest tests/test_smoke.py

Each test asserts only end-to-end behaviour (a real answer, a real embedding, real audio),
never internal calls — the fake-core unit tests cover wiring.
"""

from __future__ import annotations

import asyncio
import struct
import zlib

import pytest

np = pytest.importorskip("numpy")

from runanywhere import RunAnywhere
from runanywhere.audio import pcm16_bytes
from runanywhere.results import Synthesis

from conftest import requires_model, requires_native

# Skip the ENTIRE module unless the native extension is built and loadable.
pytestmark = requires_native

# Catalog ids exercised here (see runanywhere/catalog.py).
LLM_ID = "qwen2.5-0.5b"
EMBEDDER_ID = "minilm"
STT_ID = "whisper-tiny"
TTS_ID = "piper-lessac"
VLM_ID = "smolvlm-256m"

_ONE_WORD_FRANCE = "What is the capital of France? Answer in one word."


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------
def _silence_pcm16(seconds: float = 0.5, sample_rate: int = 16000) -> bytes:
    """A short buffer of 16 kHz mono silence as little-endian PCM16 bytes.

    Built through the SDK's own ``pcm16_bytes`` so it exactly matches what STT expects.
    """
    samples = np.zeros(int(seconds * sample_rate), dtype=np.float32)
    return pcm16_bytes(samples)


def _tiny_png(tmp_path, size: int = 8) -> str:
    """Write a minimal solid-gray PNG and return its path (a valid image for the VLM).

    Encoded with stdlib only (struct + zlib) so no image library is needed — the VLM just
    needs a decodable image to caption.
    """

    def _chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    width = height = size
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    row = b"\x00" + b"\x80\x80\x80" * width  # filter byte 0 + gray pixels
    raw = row * height
    idat = zlib.compress(raw, 9)
    png = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", idat) + _chunk(b"IEND", b"")
    path = tmp_path / "smoke.png"
    path.write_bytes(png)
    return str(path)


# --------------------------------------------------------------------------------------
# (1) system: sync LLM generation
# --------------------------------------------------------------------------------------
@requires_model(LLM_ID)
def test_llm_generate_capital_of_france() -> None:
    with RunAnywhere() as ra:
        llm = ra.load_llm(LLM_ID)
        text = "".join(llm.generate(_ONE_WORD_FRANCE))
        assert "paris" in text.lower()


# --------------------------------------------------------------------------------------
# (2) async: agenerate via asyncio.run
# --------------------------------------------------------------------------------------
@requires_model(LLM_ID)
def test_llm_agenerate_capital_of_france() -> None:
    async def run() -> str:
        with RunAnywhere() as ra:
            llm = ra.load_llm(LLM_ID)
            out: list[str] = []
            async for token in llm.agenerate(_ONE_WORD_FRANCE):
                out.append(token)
            return "".join(out)

    text = asyncio.run(run())
    assert "paris" in text.lower()


# --------------------------------------------------------------------------------------
# (3) generate_text non-empty
# --------------------------------------------------------------------------------------
@requires_model(LLM_ID)
def test_llm_generate_text_non_empty() -> None:
    with RunAnywhere() as ra:
        llm = ra.load_llm(LLM_ID)
        text = llm.generate_text("Say hello.")
        assert isinstance(text, str)
        assert text.strip() != ""


# --------------------------------------------------------------------------------------
# (4) generate_structured returns a dict for a tiny schema
# --------------------------------------------------------------------------------------
@requires_model(LLM_ID)
def test_llm_generate_structured_returns_dict() -> None:
    schema = {
        "type": "object",
        "properties": {"city": {"type": "string"}},
        "required": ["city"],
    }
    with RunAnywhere() as ra:
        llm = ra.load_llm(LLM_ID)
        result = llm.generate_structured(
            "Return the capital of France as JSON with a 'city' field.", schema
        )
        assert isinstance(result, dict)
        assert "city" in result


# --------------------------------------------------------------------------------------
# (5) embedder: 1-D float32 ndarray with >0 dims
# --------------------------------------------------------------------------------------
@requires_model(EMBEDDER_ID)
def test_embedder_embed_shape_and_dtype() -> None:
    with RunAnywhere() as ra:
        embedder = ra.load_embedder(EMBEDDER_ID)
        vec = embedder.embed("hello world")
        assert isinstance(vec, np.ndarray)
        assert vec.ndim == 1
        assert vec.shape[0] > 0
        assert vec.dtype == np.float32


# --------------------------------------------------------------------------------------
# (6) stt: transcribe short silence returns a str
# --------------------------------------------------------------------------------------
@requires_model(STT_ID)
def test_stt_transcribe_silence_returns_str() -> None:
    with RunAnywhere() as ra:
        stt = ra.load_stt(STT_ID)
        transcript = stt.transcribe(_silence_pcm16())
        assert isinstance(transcript, str)


# --------------------------------------------------------------------------------------
# (7) tts: synthesize returns a Synthesis with 1-D samples + positive sample rate
# --------------------------------------------------------------------------------------
@requires_model(TTS_ID)
def test_tts_synthesize_returns_waveform() -> None:
    with RunAnywhere() as ra:
        voice = ra.load_tts(TTS_ID)
        synthesis = voice.synthesize("Hello there.")
        assert isinstance(synthesis, Synthesis)
        assert isinstance(synthesis.samples, np.ndarray)
        assert synthesis.samples.ndim == 1
        assert synthesis.sample_rate > 0


# --------------------------------------------------------------------------------------
# (8) vlm: caption_text on a small image returns a str
# --------------------------------------------------------------------------------------
@requires_model(VLM_ID)
def test_vlm_caption_text_returns_str(tmp_path) -> None:
    image_path = _tiny_png(tmp_path)
    with RunAnywhere() as ra:
        vlm = ra.load_vlm(VLM_ID)
        caption = vlm.caption_text(image_path, "What is in this image?")
        assert isinstance(caption, str)
