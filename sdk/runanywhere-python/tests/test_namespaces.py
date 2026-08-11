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


@pytest.fixture()
def sortformer_dir(tmp_path) -> str:
    """A local directory path standing in for an unpacked ONNX diarization model."""
    directory = tmp_path / "sortformer-model"
    directory.mkdir()
    return str(directory)


def _wav(seconds: float = 1.0, rate: int = 16000, amplitude: float = 0.0) -> AudioInput:
    samples = np.full(int(rate * seconds), amplitude, dtype=np.float32)
    return AudioInput.wav(encode_wav(samples, rate))


# --------------------------------------------------------------------------- stt
def test_transcribe_returns_text_and_duration(sdk, sherpa_dir) -> None:
    result = ra.stt.transcribe(_wav(0.5), SttOptions(model=sherpa_dir))
    assert result.text == "hello there"
    # Text-only bridge does not carry STTOutput.duration_ms; do not invent from input length.
    assert result.duration_ms == 0
    assert result.words == []  # the bridge returns text only
    # Input length remains available on AudioInput for request formatting only.
    assert 400 <= _wav(0.5).duration_ms() <= 600


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
    [EmbedOptions(normalize=False), EmbedOptions(pooling=PoolingMode.CLS)],
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


# --------------------------------------------------------------------------- images
# native/module.cpp exports load_diffusion_model only when RAC_HAVE_BACKEND_NEURT;
# the fake core simulates a CoreML-enabled build so generate() smokes the real shape.
def test_images_generate_returns_rgba(sdk, tmp_path) -> None:
    model_dir = tmp_path / "sd-model"
    model_dir.mkdir()
    result = ra.images.generate(
        "a cat", ImageOptions(model=str(model_dir), width=32, height=32, seed=7)
    )
    assert len(result.images) == 1
    assert result.images[0].width == 32 and result.images[0].height == 32
    assert len(result.images[0].data) == 32 * 32 * 4
    assert result.seed == 7


def test_images_generate_stream_still_unsupported(sdk) -> None:
    with pytest.raises(SDKException) as error:
        next(ra.images.generate_stream("a cat"))
    assert "generate_stream" in str(error.value)


def test_images_report_unavailable_when_symbols_missing(sdk, monkeypatch, tmp_path) -> None:
    monkeypatch.delattr(type(sdk), "load_diffusion_model")
    model_dir = tmp_path / "sd-model"
    model_dir.mkdir()
    with pytest.raises(SDKException) as error:
        ra.images.generate("a cat", ImageOptions(model=str(model_dir)))
    assert "RAC_HAVE_BACKEND_NEURT" in str(error.value) or "diffusion" in str(error.value).lower()


# --------------------------------------------------------------------------- segmentation
# native/module.cpp binds load_segmentation_model/segment (rac_segmentation_create/
# initialize/segment) — same smoke-vs-stub split as diarization.
def test_segmentation_returns_mask_and_classes(sdk, tmp_path) -> None:
    model_dir = tmp_path / "seg-model"
    model_dir.mkdir()
    pixels = bytes([255, 0, 0]) * (8 * 8)
    result = ra.segmentation.segment(
        ImageInput.raw_rgb(pixels, 8, 8),
        SegmentationOptions(model=str(model_dir)),
    )
    assert result.width == 8 and result.height == 8
    assert len(result.class_mask) == 8 * 8 * 2  # uint16 LE
    assert [c.label for c in result.classes] == ["bg", "fg"]


def test_segmentation_requires_raw_rgb(sdk, tmp_path) -> None:
    model_dir = tmp_path / "seg-model"
    model_dir.mkdir()
    image = tmp_path / "x.png"
    image.write_bytes(b"\x89PNG")
    with pytest.raises(SDKException) as error:
        ra.segmentation.segment(
            ImageInput.file(str(image)), SegmentationOptions(model=str(model_dir))
        )
    assert "raw RGB" in str(error.value)


def test_segmentation_report_unavailable_when_symbols_missing(
    sdk, monkeypatch, tmp_path
) -> None:
    monkeypatch.delattr(type(sdk), "load_segmentation_model")
    model_dir = tmp_path / "seg-model"
    model_dir.mkdir()
    pixels = bytes([0, 0, 0]) * 4
    with pytest.raises(SDKException) as error:
        ra.segmentation.segment(
            ImageInput.raw_rgb(pixels, 2, 2), SegmentationOptions(model=str(model_dir))
        )
    assert "rebuild the native extension" in str(error.value)


# --------------------------------------------------------------------------- diarization
# native/module.cpp binds load_diarization_model/diarize (rac_diarization_create/
# initialize/diarize) — the fake core simulates a "bound" build, so these smoke the real
# call shapes rather than the capability gap.
def test_diarize_returns_segments_and_speaker_count(sdk, sortformer_dir) -> None:
    result = ra.diarization.diarize(_wav(1.0), DiarizationOptions(model=sortformer_dir))
    assert result.speaker_count == 2
    assert [s.speaker_id for s in result.segments] == ["speaker_0", "speaker_1"]
    assert result.segments[0].start_ms == 0 and result.segments[0].end_ms == 500


def test_diarize_requires_a_model_the_first_time(sdk) -> None:
    with pytest.raises(SDKException):
        ra.diarization.diarize(_wav(0.1))


def test_diarize_passes_options_through(sdk, sortformer_dir) -> None:
    ra.diarization.diarize(
        _wav(0.2),
        DiarizationOptions(
            model=sortformer_dir, threshold=0.7, minimum_duration_ms=250, merge_gap_ms=100
        ),
    )
    _handle, _n, sample_rate_hz, threshold, min_dur, merge_gap = sdk.args_of("diarize")
    assert sample_rate_hz == 16000
    assert threshold == 0.7 and min_dur == 250 and merge_gap == 100


# --------------------------------------------------------------------------- lora
# native/module.cpp binds lora_*_proto (rac_lora_*_proto). Commons owns optional
# scale resolution — unset scale is forwarded without coercing to 1.0.
def test_lora_apply_remove_and_list_round_trip(sdk, gguf) -> None:
    ra.llm.generate("hi", LlmOptions(model=gguf))  # a resident LLM is required
    assert ra.lora.list().applied == []

    ra.lora.apply("adapter.gguf", scale=0.5)
    state = ra.lora.list()
    assert len(state.applied) == 1
    assert state.applied[0].id == "adapter.gguf" and state.applied[0].scale == 0.5
    _nbytes, recorded, keep_existing = sdk.args_of("lora_apply_proto")
    assert keep_existing is True
    assert recorded == (("adapter.gguf", "adapter.gguf", True, 0.5),)

    ra.lora.remove("adapter.gguf")
    assert ra.lora.list().applied == []
    _nbytes, adapter_ids, clear_all = sdk.args_of("lora_remove_proto")
    assert adapter_ids == ["adapter.gguf"] and clear_all is False

    ra.lora.apply("a.gguf")
    ra.lora.apply("b.gguf")
    # Unset scale must reach commons without a host-side 1.0 default.
    _nbytes, recorded, _keep = [
        args for name, args in sdk.calls if name == "lora_apply_proto"
    ][-1]
    assert recorded == (("b.gguf", "b.gguf", False, None),)
    ra.lora.remove_all()
    assert ra.lora.list().applied == []
    assert any(
        name == "lora_remove_proto" and args[2] is True for name, args in sdk.calls
    )


def test_lora_list_is_empty_without_a_resident_llm(sdk) -> None:
    assert ra.lora.list().applied == []


def test_lora_apply_requires_a_resident_llm(sdk) -> None:
    with pytest.raises(SDKException):
        ra.lora.apply("adapter.gguf")


# --------------------------------------------------------------------------- voice
# native/module.cpp binds create_voice_agent / initialize_voice_agent /
# process_voice_turn (file-PCM STT→LLM→TTS — no mic).
def test_voice_session_process_turn(sdk, sherpa_dir, gguf, tmp_path) -> None:
    tts_dir = tmp_path / "tts-model"
    tts_dir.mkdir()
    session = ra.voice.create_session(
        ModelRef(sherpa_dir), ModelRef(gguf), ModelRef(str(tts_dir))
    )
    try:
        result = session.process_turn(_wav(0.2))
        assert result.transcription == "hello there"
        assert result.response == "hi from the agent"
        assert result.speech_detected is True
        assert result.audio.data[:4] == b"RIFF"
        assert sdk.count("process_voice_turn") == 1
    finally:
        session.close()
    assert sdk.count("destroy_voice_agent") == 1


def test_voice_session_reports_unavailable_when_symbols_missing(sdk, monkeypatch) -> None:
    monkeypatch.delattr(type(sdk), "create_voice_agent")
    with pytest.raises(SDKException) as error:
        ra.voice.create_session(ModelRef("stt"), ModelRef("llm"), ModelRef("tts"))
    assert "rebuild the native extension" in str(error.value)
