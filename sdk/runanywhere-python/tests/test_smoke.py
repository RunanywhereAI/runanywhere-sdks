"""Gated integration / system tests over the REAL native core + REAL cached models.

These are the only tests that touch the compiled ``runanywhere._core`` extension and the models
under ``~/.runanywhere/models``. The whole module is skipped unless the native core loads
(``requires_native``), and every test is additionally skipped unless the model it needs is
already downloaded (``requires_model(<id>)``) — nothing here downloads a model or builds native
code, so on a clean machine the module is a no-op.

Run them, once a native build and cached models exist, with::

    pytest tests/test_smoke.py
"""

from __future__ import annotations

import asyncio
import struct
import zlib

import pytest

np = pytest.importorskip("numpy")

import runanywhere as ra
from runanywhere import (
    AudioInput,
    EmbedOptions,
    ErrorCode,
    FinishReason,
    ImageInput,
    LlmOptions,
    ModelCategory,
    ModelRef,
    RagDocument,
    SDKException,
    SttOptions,
    TtsOptions,
)
from runanywhere.audio import encode_wav

from conftest import _NATIVE_AVAILABLE, model_ready, requires_model, requires_native

# Skip the ENTIRE module unless the native extension is built and loadable.
pytestmark = requires_native

LLM_ID = "smollm2-135m"
BIG_LLM_ID = "qwen2.5-0.5b"
EMBEDDER_ID = "minilm"
STT_ID = "whisper-tiny"
TTS_ID = "piper-lessac"
VLM_ID = "smolvlm-256m"

_ONE_WORD_FRANCE = "What is the capital of France? Answer in one word."

requires_rag = pytest.mark.skipif(
    not (_NATIVE_AVAILABLE and model_ready(EMBEDDER_ID) and model_ready(LLM_ID)),
    reason=f"RAG test needs {EMBEDDER_ID} + {LLM_ID} cached",
)


@pytest.fixture()
def live_sdk():
    """Initialize the real SDK for one test and tear it down afterwards."""
    ra.initialize()
    try:
        yield
    finally:
        ra.reset()


def _silence(seconds: float = 0.5, sample_rate: int = 16000) -> AudioInput:
    return AudioInput.wav(
        encode_wav(np.zeros(int(seconds * sample_rate), dtype=np.float32), sample_rate)
    )


def _tiny_png(tmp_path, size: int = 8) -> str:
    """Write a minimal solid-gray PNG with the stdlib only and return its path."""

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
    idat = zlib.compress(row * height, 9)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", idat)
        + _chunk(b"IEND", b"")
    )
    path = tmp_path / "smoke.png"
    path.write_bytes(png)
    return str(path)


# --------------------------------------------------------------------------- llm
@requires_model(BIG_LLM_ID)
def test_generate_answers_and_reports_metrics(live_sdk) -> None:
    result = ra.llm.generate(_ONE_WORD_FRANCE, LlmOptions(model=BIG_LLM_ID, max_output_tokens=16))
    assert "paris" in result.text.lower()
    assert result.output_tokens > 0
    assert result.tokens_per_second > 0
    assert result.model == BIG_LLM_ID
    assert result.finish_reason in (FinishReason.STOP, FinishReason.LENGTH)


@requires_model(BIG_LLM_ID)
def test_generate_stream_tokens(live_sdk) -> None:
    text = "".join(
        event.text
        for event in ra.llm.generate_stream(
            _ONE_WORD_FRANCE, LlmOptions(model=BIG_LLM_ID, max_output_tokens=16)
        )
        if event.is_token
    )
    assert "paris" in text.lower()


@requires_model(BIG_LLM_ID)
def test_agenerate(live_sdk) -> None:
    async def run() -> str:
        result = await ra.llm.agenerate(
            _ONE_WORD_FRANCE, LlmOptions(model=BIG_LLM_ID, max_output_tokens=16)
        )
        return result.text

    assert "paris" in asyncio.run(run()).lower()


@requires_model(BIG_LLM_ID)
def test_generate_structured_returns_a_parsed_object(live_sdk) -> None:
    schema = {
        "type": "object",
        "properties": {"city": {"type": "string"}},
        "required": ["city"],
    }
    result = ra.llm.generate_structured(
        "Return the capital of France as JSON with a 'city' field.",
        schema,
        LlmOptions(model=BIG_LLM_ID, max_output_tokens=32),
    )
    assert result.valid is True
    assert isinstance(result.value, dict) and "city" in result.value


@requires_model(LLM_ID)
def test_stop_sequences_cut_the_answer(live_sdk) -> None:
    result = ra.llm.generate(
        "Count: one two three four five",
        LlmOptions(model=LLM_ID, max_output_tokens=64, stop_sequences=["three"]),
    )
    assert "three" not in result.text


@requires_model(LLM_ID)
def test_models_state_tracks_the_resident_model(live_sdk) -> None:
    ra.models.load(LLM_ID)
    state = ra.models.state()
    assert state.loaded[ModelCategory.LANGUAGE].id == LLM_ID
    assert state.storage_used_bytes > 0
    ra.models.unload(ModelCategory.LANGUAGE)
    assert ModelCategory.LANGUAGE not in ra.models.state().loaded


@requires_native
def test_loading_a_missing_model_raises(live_sdk) -> None:
    with pytest.raises(SDKException):
        ra.llm.generate("hi", LlmOptions(model="/no/such/dir/model.gguf"))


@requires_model(LLM_ID)
def test_concurrent_generation_is_refused(live_sdk) -> None:
    options = LlmOptions(model=LLM_ID, max_output_tokens=128)
    stream = ra.llm.generate_stream("Count to a hundred slowly.", options)
    next(stream)
    next(stream)
    try:
        with pytest.raises(SDKException) as error:
            list(ra.llm.generate_stream("A concurrent prompt.", options))
        assert error.value.code == ErrorCode.INVALID_STATE
    finally:
        stream.close()
    assert ra.llm.generate("Say hi.", options).text.strip()


# --------------------------------------------------------------------------- speech + embeddings
@requires_model(EMBEDDER_ID)
def test_embed_returns_vectors(live_sdk) -> None:
    vectors = ra.embeddings.embed(["hello world", "second"], EmbedOptions(model=EMBEDDER_ID))
    assert [v.index for v in vectors] == [0, 1]
    assert vectors[0].vector.ndim == 1 and vectors[0].vector.shape[0] > 0
    assert vectors[0].vector.dtype == np.float32


@requires_model(STT_ID)
def test_transcribe_silence(live_sdk) -> None:
    transcription = ra.stt.transcribe(_silence(), SttOptions(model=STT_ID))
    assert isinstance(transcription.text, str)
    assert transcription.duration_ms == 500
    assert ra.stt.state().is_ready is True


@requires_model(TTS_ID)
def test_synthesize_produces_audio(live_sdk) -> None:
    audio = ra.tts.synthesize("Hello there.", TtsOptions(model=TTS_ID))
    assert audio.sample_rate > 0 and audio.duration_ms > 0
    assert len(audio.data) > 0
    assert audio.samples().ndim == 1


@requires_model(TTS_ID)
def test_synthesize_can_emit_wav(live_sdk) -> None:
    from runanywhere import AudioFormat

    audio = ra.tts.synthesize("Hello.", TtsOptions(model=TTS_ID, format=AudioFormat.WAV))
    assert audio.data[:4] == b"RIFF"


@requires_native
def test_vad_detects_no_speech_in_silence(live_sdk) -> None:
    result = ra.vad.detect(_silence(1.0))
    assert result.is_speech is False and result.segments == []


# --------------------------------------------------------------------------- vision + rag
@requires_model(VLM_ID)
def test_vlm_describes_an_image(live_sdk, tmp_path) -> None:
    result = ra.vlm.generate(
        ImageInput.file(_tiny_png(tmp_path)),
        "What is in this image?",
        LlmOptions(model=VLM_ID, max_output_tokens=32),
    )
    assert isinstance(result.text, str) and result.text.strip()


@requires_rag
def test_rag_answers_from_an_ingested_document(live_sdk) -> None:
    with ra.rag.open(ModelRef(EMBEDDER_ID), ModelRef(LLM_ID)) as session:
        session.ingest(RagDocument("Paris is the capital of France."))
        stats = session.stats()
        assert stats.document_count >= 1
        matches = session.search("capital of France", top_k=1)
        assert matches and "Paris" in matches[0].text
        result = session.query("What is the capital of France?", LlmOptions(max_output_tokens=48))
        assert isinstance(result.answer, str)
        assert result.sources


# --------------------------------------------------------------------------- one voice turn
_VOICE_MODELS = (STT_ID, LLM_ID, TTS_ID)

requires_voice = pytest.mark.skipif(
    not (_NATIVE_AVAILABLE and all(model_ready(m) for m in _VOICE_MODELS)),
    reason=f"voice turn needs {' + '.join(_VOICE_MODELS)} cached",
)


@requires_voice
def test_one_voice_turn_composes_the_namespaces(live_sdk) -> None:
    """``voice.create_session`` needs the unbound native agent, so a turn is composed here."""
    transcript = ra.stt.transcribe(_silence(1.0), SttOptions(model=STT_ID)).text
    answer = ra.llm.generate(
        transcript or "Say hello.", LlmOptions(model=LLM_ID, max_output_tokens=32)
    ).text
    audio = ra.tts.synthesize(answer or "Hello.", TtsOptions(model=TTS_ID))
    assert audio.sample_rate > 0 and len(audio.data) > 0


@requires_native
def test_voice_sessions_are_reported_as_unavailable(live_sdk) -> None:
    with pytest.raises(SDKException):
        ra.voice.create_session(ModelRef(STT_ID), ModelRef(LLM_ID), ModelRef(TTS_ID))
