"""Tests for options dataclass defaults + generate_kwargs, and results value types."""

from __future__ import annotations

import numpy as np

from runanywhere.options import (
    ChatOptions,
    DownloadOptions,
    GenerateOptions,
    InitOptions,
    LoadOptions,
    VadOptions,
    generate_kwargs,
)
from runanywhere.results import (
    DownloadProgress,
    LLMGenerationResult,
    LLMStreamEvent,
    ModelStatus,
    ResolvedModel,
    Synthesis,
    VoiceTurn,
)


# --- generate_kwargs -------------------------------------------------------


def test_generate_kwargs_drops_none() -> None:
    assert generate_kwargs() == {}
    assert generate_kwargs(max_tokens=None, temperature=None) == {}


def test_generate_kwargs_keeps_set_keys() -> None:
    out = generate_kwargs(max_tokens=64, temperature=0.7, grammar="root ::= x")
    assert out == {"max_tokens": 64, "temperature": 0.7, "grammar": "root ::= x"}


def test_generate_kwargs_mixed_none_and_set() -> None:
    out = generate_kwargs(
        max_tokens=32,
        temperature=None,
        top_p=0.9,
        top_k=None,
        system_prompt="be terse",
        grammar=None,
    )
    assert out == {"max_tokens": 32, "top_p": 0.9, "system_prompt": "be terse"}


def test_generate_kwargs_all_keys() -> None:
    out = generate_kwargs(
        max_tokens=1,
        temperature=0.0,
        top_p=0.1,
        top_k=5,
        system_prompt="s",
        grammar="g",
    )
    assert out == {
        "max_tokens": 1,
        "temperature": 0.0,
        "top_p": 0.1,
        "top_k": 5,
        "system_prompt": "s",
        "grammar": "g",
    }


def test_generate_kwargs_ignores_unknown_keys() -> None:
    out = generate_kwargs(max_tokens=8, unknown="x", schema={"type": "object"})
    assert out == {"max_tokens": 8}


def test_generate_kwargs_keeps_falsy_non_none() -> None:
    # Zero / empty-string are set values, not "unset" — only None is dropped.
    out = generate_kwargs(temperature=0.0, top_k=0, system_prompt="")
    assert out == {"temperature": 0.0, "top_k": 0, "system_prompt": ""}


def test_generate_options_dataclass_feeds_generate_kwargs() -> None:
    opts = GenerateOptions(max_tokens=16, temperature=0.5)
    out = generate_kwargs(**vars(opts))
    assert out == {"max_tokens": 16, "temperature": 0.5}


# --- options dataclass defaults --------------------------------------------


def test_init_options_defaults() -> None:
    o = InitOptions()
    assert o.secure_dir is None
    assert o.base_dir is None
    assert o.api_key is None
    assert o.base_url is None
    assert o.environment == "production"


def test_generate_options_defaults() -> None:
    o = GenerateOptions()
    assert (o.max_tokens, o.temperature, o.top_p, o.top_k) == (None, None, None, None)
    assert o.system_prompt is None
    assert o.grammar is None


def test_load_download_vad_chat_options_defaults() -> None:
    assert LoadOptions() == LoadOptions(id=None, name=None)
    d = DownloadOptions()
    assert d.dir is None and d.on_progress is None
    assert VadOptions().threshold is None
    assert ChatOptions().system is None


# --- results value types ---------------------------------------------------


def test_llm_generation_result_and_stream_event() -> None:
    r = LLMGenerationResult(
        text="hi",
        token_count=1,
        time_to_first_token_ms=1.0,
        tokens_per_second=2.0,
        total_time_ms=3.0,
    )
    ev = LLMStreamEvent(token="hi", is_final=False)
    assert ev.result is None
    final = LLMStreamEvent(token="", is_final=True, result=r)
    assert final.result is r


def test_synthesis_is_named_tuple() -> None:
    samples = np.zeros(4, dtype=np.float32)
    s = Synthesis(samples=samples, sample_rate=24000)
    # NamedTuple: positional unpacking + field access both work.
    got_samples, got_rate = s
    assert got_rate == 24000
    assert s.sample_rate == 24000
    assert np.array_equal(s.samples, got_samples)


def test_voice_turn_carries_synthesis() -> None:
    audio = Synthesis(samples=np.ones(2, dtype=np.float32), sample_rate=16000)
    turn = VoiceTurn(transcript="hello", response="hi", audio=audio)
    assert turn.audio.sample_rate == 16000


def test_resolved_model_and_status_and_progress() -> None:
    rm = ResolvedModel(id="m", type="llm", dir="/d", primary="/d/m.gguf")
    assert rm.mmproj is None
    rm2 = ResolvedModel(id="m", type="vlm", dir="/d", primary="/d/m.gguf", mmproj="/d/mm.gguf")
    assert rm2.mmproj == "/d/mm.gguf"
    assert ModelStatus(downloaded=True, size_bytes=10).size_bytes == 10
    p = DownloadProgress(file="m.gguf", received=5, total=10, percent=50)
    assert p.percent == 50
