"""The speech, vision, embedding and not-yet-bridged namespaces."""

from __future__ import annotations

import asyncio
import os
import sys

_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import numpy as np  # noqa: E402
import pytest  # noqa: E402

import runanywhere as ra  # noqa: E402
from runanywhere import (  # noqa: E402
    AudioFormat,
    AudioInput,
    DiarizationOptions,
    EmbedOptions,
    ErrorCode,
    ImageInput,
    ImageOptions,
    LlmOptions,
    ModelRef,
    NormalizeMode,
    PoolingMode,
    SDKException,
    SegmentationOptions,
    SttOptions,
    TtsOptions,
    VadOptions,
)
from runanywhere.audio import encode_wav  # noqa: E402
from runanywhere.results import ResolvedModel  # noqa: E402


@pytest.fixture()
def sherpa_dir(tmp_path) -> str:
    """A local directory path standing in for an unpacked sherpa model."""
    directory = tmp_path / "sherpa-model"
    directory.mkdir()
    return str(directory)


def _wav(seconds: float = 1.0, rate: int = 16000, amplitude: float = 0.0) -> AudioInput:
    samples = np.full(int(rate * seconds), amplitude, dtype=np.float32)
    return AudioInput.wav(encode_wav(samples, rate))


# --------------------------------------------------------------------------- stt
def test_transcribe_returns_text_and_duration(sdk, sherpa_dir) -> None:
    result = ra.stt.transcribe(_wav(0.5), SttOptions(model=sherpa_dir))
    assert result.text == "hello there"
    assert 400 <= result.duration_ms <= 600
    assert result.words == []  # the bridge returns text only


def test_transcribe_accepts_pcm16_and_float32_inputs(sdk, sherpa_dir) -> None:
    pcm = AudioInput.pcm16(b"\x00\x00" * 1600, sample_rate=16000)
    assert ra.stt.transcribe(pcm, SttOptions(model=sherpa_dir)).text == "hello there"
    floats = AudioInput.float32(np.zeros(1600, dtype=np.float32), 16000)
    assert ra.stt.transcribe(floats, SttOptions(model=sherpa_dir)).text == "hello there"


def test_transcribe_resamples_to_16k(sdk, sherpa_dir) -> None:
    ra.stt.transcribe(_wav(1.0, rate=32000), SttOptions(model=sherpa_dir))
    _handle, byte_count = sdk.args_of("transcribe")
    assert byte_count == 16000 * 2  # one second of 16 kHz mono PCM16


def test_atranscribe(sdk, sherpa_dir) -> None:
    result = asyncio.run(ra.stt.atranscribe(_wav(0.2), SttOptions(model=sherpa_dir)))
    assert result.text == "hello there"


def test_stt_state_reports_readiness(sdk, sherpa_dir) -> None:
    assert ra.stt.state().is_ready is False
    ra.stt.transcribe(_wav(0.2), SttOptions(model=sherpa_dir))
    state = ra.stt.state()
    assert state.is_ready is True and state.model_id == sherpa_dir
    assert state.supports_streaming is False


@pytest.mark.parametrize(
    "options",
    [
        SttOptions(language="fr-FR"),
        SttOptions(punctuation=False),
        SttOptions(diarization=True),
        SttOptions(max_speakers=2),
        SttOptions(translate_to_english=True),
    ],
)
def test_unsupported_stt_options_raise(sdk, options) -> None:
    with pytest.raises(SDKException) as error:
        ra.stt.transcribe(_wav(0.1), options)
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED
    assert "rac_stt" in str(error.value)


def test_transcribe_stream_is_reported_as_a_gap(sdk) -> None:
    with pytest.raises(SDKException) as error:
        ra.stt.transcribe_stream([_wav(0.1)])
    assert "rac_stt_component_transcribe_stream_proto" in str(error.value)


# --------------------------------------------------------------------------- tts
def test_synthesize_returns_pcm_by_default(sdk, sherpa_dir) -> None:
    audio = ra.tts.synthesize("hello", TtsOptions(model=sherpa_dir))
    assert audio.format == AudioFormat.PCM
    assert audio.sample_rate == 22050
    assert len(audio.data) == 2048 * 2  # 16-bit samples
    assert audio.duration_ms > 0


def test_synthesize_can_return_wav(sdk, sherpa_dir) -> None:
    audio = ra.tts.synthesize("hello", TtsOptions(model=sherpa_dir, format=AudioFormat.WAV))
    assert audio.data[:4] == b"RIFF"
    assert audio.samples().shape[0] == 2048


def test_synthesize_downsamples_when_asked(sdk, sherpa_dir) -> None:
    audio = ra.tts.synthesize("hello", TtsOptions(model=sherpa_dir, sample_rate=16000))
    assert audio.sample_rate == 16000


def test_synthesize_stream_yields_one_final_chunk(sdk, sherpa_dir) -> None:
    chunks = list(ra.tts.synthesize_stream("hello", TtsOptions(model=sherpa_dir)))
    assert len(chunks) == 1
    assert chunks[0].is_final is True and chunks[0].index == 0


def test_asynthesize(sdk, sherpa_dir) -> None:
    audio = asyncio.run(ra.tts.asynthesize("hello", TtsOptions(model=sherpa_dir)))
    assert audio.sample_rate == 22050


@pytest.mark.parametrize("options", [TtsOptions(speed=1.5), TtsOptions(pitch=0.5)])
def test_unsupported_tts_options_raise(sdk, options) -> None:
    with pytest.raises(SDKException) as error:
        ra.tts.synthesize("hi", options)
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED
    assert "rac_tts_options_t" in str(error.value)


def test_speak_and_stop_are_reported_as_gaps(sdk) -> None:
    with pytest.raises(SDKException) as speak_error:
        ra.tts.speak("hi")
    assert "no audio output device" in str(speak_error.value)
    with pytest.raises(SDKException) as stop_error:
        ra.tts.stop()
    assert "rac_tts_component_stop" in str(stop_error.value)


def test_voices_lists_loadable_banks(fake_core) -> None:
    voices = ra.tts.voices()
    assert voices and all(voice.id for voice in voices)


# --------------------------------------------------------------------------- vad
def test_detect_finds_speech_segments(sdk) -> None:
    # 16 frames of 512 samples: silence, then speech, then silence.
    sdk.vad_decisions = [False] * 4 + [True] * 6 + [False] * 20
    result = ra.vad.detect(_wav(0.6), VadOptions(min_speech_ms=32, min_silence_ms=64))
    assert result.is_speech is True
    assert result.probability == 1.0
    assert result.segments and result.segments[0].start_ms >= 0
    assert result.segments[0].end_ms > result.segments[0].start_ms


def test_detect_reports_silence(sdk) -> None:
    sdk.vad_decisions = [False]
    result = ra.vad.detect(_wav(0.3))
    assert result.is_speech is False and result.segments == []
    assert result.probability == 0.0


def test_activation_threshold_reaches_the_detector(sdk) -> None:
    ra.vad.detect(_wav(0.1), VadOptions(activation_threshold=0.7))
    assert sdk.args_of("create_vad") == (0.7,)


def test_prefix_padding_moves_the_segment_start_earlier(sdk) -> None:
    sdk.vad_decisions = [False] * 4 + [True] * 8 + [False] * 20
    plain = ra.vad.detect(_wav(0.6), VadOptions(min_speech_ms=32, min_silence_ms=64))
    padded = ra.vad.detect(
        _wav(0.6), VadOptions(min_speech_ms=32, min_silence_ms=64, prefix_padding_ms=64)
    )
    assert padded.segments[0].start_ms < plain.segments[0].start_ms


def test_adetect(sdk) -> None:
    sdk.vad_decisions = [False] * 4 + [True] * 6 + [False] * 20
    result = asyncio.run(ra.vad.adetect(_wav(0.6), VadOptions(min_speech_ms=32, min_silence_ms=64)))
    assert result.is_speech is True and result.segments


def test_detect_stream_emits_boundaries(sdk) -> None:
    sdk.vad_decisions = [False] * 2 + [True] * 6 + [False] * 20
    events = list(
        ra.vad.detect_stream(
            [_wav(0.3), _wav(0.3)], VadOptions(min_speech_ms=32, min_silence_ms=64)
        )
    )
    kinds = [event.kind.name for event in events]
    assert "SPEECH_STARTED" in kinds and "SPEECH_ENDED" in kinds


# --------------------------------------------------------------------------- embeddings
def test_embed_returns_vectors_in_input_order(sdk, sherpa_dir) -> None:
    vectors = ra.embeddings.embed(["a", "b"], EmbedOptions(model=sherpa_dir))
    assert [v.index for v in vectors] == [0, 1]
    assert vectors[0].vector.shape == (4,)


def test_embed_rejects_an_empty_batch(sdk, sherpa_dir) -> None:
    with pytest.raises(SDKException) as error:
        ra.embeddings.embed([], EmbedOptions(model=sherpa_dir))
    assert error.value.code == ErrorCode.INVALID_INPUT


def test_aembed(sdk, sherpa_dir) -> None:
    vectors = asyncio.run(ra.embeddings.aembed(["a"], EmbedOptions(model=sherpa_dir)))
    assert len(vectors) == 1


@pytest.mark.parametrize(
    "options",
    [EmbedOptions(normalize=NormalizeMode.NONE), EmbedOptions(pooling=PoolingMode.CLS)],
)
def test_unsupported_embed_options_raise(sdk, options) -> None:
    with pytest.raises(SDKException) as error:
        ra.embeddings.embed(["a"], options)
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED
    assert "rac_embeddings_options_t" in str(error.value)


# --------------------------------------------------------------------------- vlm
def test_vlm_generate_passes_the_image_path(sdk, monkeypatch, tmp_path) -> None:
    weights = tmp_path / "vlm.gguf"
    weights.write_bytes(b"gguf")
    mmproj = tmp_path / "mmproj.gguf"
    mmproj.write_bytes(b"gguf")
    image = tmp_path / "cat.png"
    image.write_bytes(b"\x89PNG")

    from runanywhere._runtime import runtime

    monkeypatch.setattr(
        runtime,
        "resolve",
        lambda model_id, on_progress=None: ResolvedModel(
            id=model_id, type="vlm", dir=str(tmp_path), primary=str(weights), mmproj=str(mmproj)
        ),
    )
    result = ra.vlm.generate(
        ImageInput.file(str(image)), "What is this?", LlmOptions(model="fake-vlm")
    )
    assert result.text == "Paris"
    _handle, image_path, prompt = sdk.args_of("generate_vlm")
    assert image_path == str(image) and prompt == "What is this?"


def test_vlm_rejects_structured_output(sdk, tmp_path) -> None:
    from runanywhere import StructuredOutput

    image = tmp_path / "cat.png"
    image.write_bytes(b"\x89PNG")
    options = LlmOptions(model="fake-vlm", structured_output=StructuredOutput(schema={}))
    with pytest.raises(SDKException) as error:
        ra.vlm.generate(ImageInput.file(str(image)), "hi", options)
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED


# --------------------------------------------------------------------------- not-yet-bridged
def test_rerank_reports_the_missing_symbols(sdk) -> None:
    with pytest.raises(SDKException) as error:
        ra.rerank.rerank("q", ["a", "b"], top_n=1)
    assert "rac_rerank_component_rerank_proto" in str(error.value)


def test_images_report_the_missing_symbols(sdk) -> None:
    with pytest.raises(SDKException) as error:
        ra.images.generate("a cat", ImageOptions())
    assert "rac_diffusion_generate_proto" in str(error.value)
    with pytest.raises(SDKException):
        ra.images.generate_stream("a cat")


def test_diarization_reports_the_missing_symbols(sdk) -> None:
    with pytest.raises(SDKException) as error:
        ra.diarization.diarize(_wav(0.1), DiarizationOptions())
    assert "rac_diarization_component_diarize_proto" in str(error.value)


def test_segmentation_reports_the_missing_symbols(sdk, tmp_path) -> None:
    image = tmp_path / "x.png"
    image.write_bytes(b"\x89PNG")
    with pytest.raises(SDKException) as error:
        ra.segmentation.segment(ImageInput.file(str(image)), SegmentationOptions())
    assert "rac_segmentation_component_segment_proto" in str(error.value)


def test_lora_reports_the_missing_symbols(sdk) -> None:
    for call in (lambda: ra.lora.apply("a"), lambda: ra.lora.remove(), lambda: ra.lora.list()):
        with pytest.raises(SDKException) as error:
            call()
        assert "rac_lora_apply_proto" in str(error.value)


def test_voice_session_reports_the_missing_symbols(sdk) -> None:
    with pytest.raises(SDKException) as error:
        ra.voice.create_session(ModelRef("stt"), ModelRef("llm"), ModelRef("tts"))
    assert "rac_voice_agent_initialize_proto" in str(error.value)
    assert "microphone" in str(error.value)
