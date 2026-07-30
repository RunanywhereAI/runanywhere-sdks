"""Option defaults and result shapes, pinned against the v3 public API spec."""

from __future__ import annotations

import numpy as np
import pytest

from runanywhere.errors import ErrorCode, SDKException
from runanywhere.inputs import (
    AudioEncoding,
    AudioFormat,
    AudioInput,
    ChatMessage,
    ImageInput,
    ModelCategory,
    ModelRef,
    RagDocument,
    Role,
    ToolDefinition,
)
from runanywhere.options import (
    DiarizationOptions,
    EmbedOptions,
    Endpointing,
    Environment,
    ImageMode,
    ImageModeKind,
    ImageOptions,
    Interruption,
    LlmOptions,
    LoadOptions,
    NormalizeMode,
    PoolingMode,
    RagConfig,
    ReasoningMode,
    ReasoningOptions,
    SegmentationOptions,
    StructuredOutput,
    SttOptions,
    ToolChoice,
    ToolChoiceMode,
    TtsOptions,
    TurnHandlingOptions,
    VadOptions,
)
from runanywhere.results import (
    Audio,
    AudioChunk,
    Embedding,
    FinishReason,
    GenerationResult,
    Match,
    ModelInfo,
    ModelsState,
    RagResult,
    RagStats,
    RankedResult,
    Segment,
    SttState,
    StructuredResult,
    TokenKind,
    ToolCall,
    Transcription,
    VadResult,
    Word,
)
from runanywhere._options_bridge import llm_kwargs, wants_thoughts


# --------------------------------------------------------------------------- option defaults
def test_llm_option_defaults_match_the_spec() -> None:
    options = LlmOptions()
    assert options.model is None
    assert options.max_output_tokens == 512
    assert options.temperature == 0.7
    assert options.top_p == 1.0
    assert options.top_k is None
    assert options.min_p is None
    assert options.frequency_penalty is None
    assert options.presence_penalty is None
    assert options.repetition_penalty is None
    assert options.seed is None
    assert options.stop_sequences == []
    assert options.system_prompt is None
    assert options.reasoning is None
    assert options.structured_output is None
    assert options.tools == []
    assert options.tool_choice.mode == ToolChoiceMode.AUTO
    assert options.max_tool_calls == 5


def test_reasoning_defaults() -> None:
    reasoning = ReasoningOptions()
    assert reasoning.mode == ReasoningMode.ON
    assert reasoning.include_in_output is False
    assert reasoning.pattern is None


def test_stt_option_defaults() -> None:
    options = SttOptions()
    assert options.language is None
    assert options.punctuation is True
    assert options.word_timestamps is True
    assert options.diarization is False
    assert options.max_speakers is None
    assert options.translate_to_english is False


def test_tts_option_defaults() -> None:
    options = TtsOptions()
    assert options.voice is None
    assert options.language == "en-US"
    assert options.speed == 1.0
    assert options.pitch == 1.0
    assert options.format == AudioFormat.PCM
    assert options.sample_rate == 22050


def test_vad_option_defaults() -> None:
    options = VadOptions()
    assert options.activation_threshold is None
    assert options.min_speech_ms == 100
    assert options.min_silence_ms == 300
    assert options.prefix_padding_ms == 0


def test_embed_option_defaults() -> None:
    options = EmbedOptions()
    assert options.normalize == NormalizeMode.L2
    assert options.pooling == PoolingMode.MEAN


def test_image_option_defaults() -> None:
    options = ImageOptions()
    assert options.negative_prompt is None
    assert (options.width, options.height, options.steps) == (None, None, None)
    assert options.guidance_scale is None and options.seed is None
    assert options.mode.kind == ImageModeKind.GENERATE
    assert options.report_partials is False


def test_inpaint_mode_carries_the_image_and_mask(tmp_path) -> None:
    source = ImageInput.bytes(b"img")
    mask = ImageInput.bytes(b"mask")
    mode = ImageMode.inpaint(source, mask)
    assert mode.kind == ImageModeKind.INPAINT
    assert mode.input is source and mode.mask is mask


def test_remaining_option_defaults() -> None:
    assert DiarizationOptions().threshold is None
    assert SegmentationOptions().include_diagnostic_image is False
    assert StructuredOutput(schema={"type": "object"}).strict is True
    turns = TurnHandlingOptions()
    assert turns.endpointing == Endpointing(min_delay_ms=500, max_delay_ms=3000)
    assert turns.interruption == Interruption(enabled=True, min_duration_ms=500)
    config = RagConfig()
    assert (config.top_k, config.chunk_size, config.chunk_overlap) == (5, 512, 64)
    assert config.similarity_threshold is None and config.persist_path is None
    load = LoadOptions()
    assert (load.framework, load.context_length, load.threads, load.use_gpu) == (
        None, None, None, None
    )


def test_tool_choice_variants() -> None:
    assert ToolChoice().mode == ToolChoiceMode.AUTO
    assert ToolChoice(ToolChoiceMode.NONE).mode == ToolChoiceMode.NONE
    forced = ToolChoice.forced("get_weather")
    assert forced.mode == ToolChoiceMode.FORCED and forced.name == "get_weather"


def test_environment_values_mirror_the_idl() -> None:
    assert int(Environment.DEVELOPMENT) == 1
    assert int(Environment.PRODUCTION) == 3


# --------------------------------------------------------------------------- bridge mapping
def test_llm_kwargs_carries_the_supported_knobs() -> None:
    kwargs = llm_kwargs(LlmOptions(max_output_tokens=16, temperature=0.5, top_p=0.9, top_k=40))
    assert kwargs == {"max_tokens": 16, "temperature": 0.5, "top_p": 0.9, "top_k": 40}


def test_llm_kwargs_defaults_are_explicit() -> None:
    assert llm_kwargs(None) == {"max_tokens": 512, "temperature": 0.7, "top_p": 1.0}


def test_llm_kwargs_maps_reasoning_off() -> None:
    kwargs = llm_kwargs(LlmOptions(reasoning=ReasoningOptions(mode=ReasoningMode.OFF)))
    assert kwargs["disable_thinking"] is True
    on = llm_kwargs(LlmOptions(reasoning=ReasoningOptions(mode=ReasoningMode.ON)))
    assert "disable_thinking" not in on


def test_llm_kwargs_builds_a_grammar_for_structured_output() -> None:
    kwargs = llm_kwargs(
        LlmOptions(structured_output=StructuredOutput(schema={"type": "object"}))
    )
    assert "root" in kwargs["grammar"]


def test_llm_kwargs_rejects_a_thinking_pattern() -> None:
    with pytest.raises(SDKException) as error:
        llm_kwargs(LlmOptions(reasoning=ReasoningOptions(pattern="<t>")))
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED


def test_wants_thoughts_follows_reasoning() -> None:
    assert wants_thoughts(None) is False
    assert wants_thoughts(LlmOptions()) is False
    assert wants_thoughts(LlmOptions(reasoning=ReasoningOptions())) is False
    assert (
        wants_thoughts(LlmOptions(reasoning=ReasoningOptions(include_in_output=True))) is True
    )


# --------------------------------------------------------------------------- inputs
def test_audio_input_constructors_normalize_to_16k_pcm() -> None:
    pcm = AudioInput.pcm16(b"\x00\x00" * 800, sample_rate=8000)
    assert pcm.format.encoding == AudioEncoding.PCM16
    assert len(pcm.to_pcm16()) == 1600 * 2  # 800 samples at 8 kHz -> 1600 at 16 kHz
    floats = AudioInput.float32(np.zeros(1600, dtype=np.float32), 16000)
    assert floats.duration_ms() == 100
    assert floats.samples().dtype == np.float32


def test_audio_input_file_reports_a_missing_file(tmp_path) -> None:
    with pytest.raises(SDKException) as error:
        AudioInput.file(str(tmp_path / "nope.wav"))
    assert error.value.code == ErrorCode.STORAGE_ERROR


def test_image_input_bytes_are_materialized_and_released() -> None:
    image = ImageInput.bytes(b"\x89PNG")
    path = image.resolve_path()
    import os

    assert os.path.exists(path)
    image.release()
    assert not os.path.exists(path)


def test_image_input_raw_rgb_writes_a_bmp() -> None:
    image = ImageInput.raw_rgb(bytes([255, 0, 0, 0, 255, 0]), width=2, height=1)
    assert image.data[:2] == b"BM"
    assert len(image.data) == 54 + 8  # header + one padded scanline


def test_image_input_raw_rgb_validates_its_size() -> None:
    with pytest.raises(SDKException) as error:
        ImageInput.raw_rgb(b"\x00", width=4, height=4)
    assert error.value.code == ErrorCode.INVALID_INPUT


def test_value_input_types() -> None:
    assert ChatMessage(role=Role.USER, content="hi").tool_call_id is None
    assert ModelRef("piper-amy", voice="amy").voice == "amy"
    assert RagDocument("text").metadata is None
    assert ToolDefinition(name="t").parameters == {"type": "object"}
    assert int(ModelCategory.SPEECH_RECOGNITION) == 1


# --------------------------------------------------------------------------- results
def test_generation_result_metrics_block() -> None:
    result = GenerationResult(
        text="hi",
        thinking_text="why",
        tool_calls=[ToolCall(name="t", arguments={"a": 1})],
        finish_reason=FinishReason.TOOL_CALLS,
        input_tokens=3,
        output_tokens=4,
        time_to_first_token_ms=5.0,
        tokens_per_second=6.0,
        request_id="r",
        model="m",
    )
    assert result.finish_reason == FinishReason.TOOL_CALLS
    assert result.tool_calls[0].arguments == {"a": 1}
    assert (result.input_tokens, result.output_tokens) == (3, 4)


def test_structured_result_carries_metrics() -> None:
    result = StructuredResult(value={"a": 1}, raw='{"a": 1}', valid=True, output_tokens=2)
    assert result.value == {"a": 1} and result.valid is True and result.output_tokens == 2


def test_transcription_and_word() -> None:
    word = Word(text="hi", start_ms=0, end_ms=100, confidence=0.9, speaker_id="s1")
    transcription = Transcription(text="hi", language="en", words=[word], duration_ms=100)
    assert transcription.words[0].speaker_id == "s1"


def test_audio_and_chunk() -> None:
    audio = Audio(data=b"\x00\x00", sample_rate=16000, format=AudioFormat.PCM, duration_ms=1)
    assert audio.samples().shape == (1,)
    chunk = AudioChunk(data=b"", index=2, is_final=True)
    assert (chunk.index, chunk.is_final) == (2, True)


def test_retrieval_and_ranking_results() -> None:
    assert VadResult(is_speech=True, probability=1.0, segments=[Segment(0, 10)]).segments[0].end_ms == 10
    assert Embedding(index=1, vector=np.zeros(2, dtype=np.float32)).index == 1
    assert RankedResult(index=0, relevance_score=0.5).relevance_score == 0.5
    assert Match(text="t", score=0.5, metadata={"k": "v"}).metadata == {"k": "v"}
    rag = RagResult(answer="a", sources=[Match(text="t")], output_tokens=1)
    assert rag.sources[0].text == "t"
    assert RagStats(document_count=1, chunk_count=2, index_size_bytes=3).chunk_count == 2


def test_state_results() -> None:
    assert SttState().is_ready is False
    info = ModelInfo(id="m", category=ModelCategory.LANGUAGE, downloaded=True)
    state = ModelsState(loaded={ModelCategory.LANGUAGE: info}, storage_used_bytes=1)
    assert state.loaded[ModelCategory.LANGUAGE].id == "m"


def test_token_kinds() -> None:
    assert int(TokenKind.TEXT) == 0 and int(TokenKind.THOUGHT) == 1
