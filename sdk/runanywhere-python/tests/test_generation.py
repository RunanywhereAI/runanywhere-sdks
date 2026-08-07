"""The generation pipeline: event grammar, metrics, thinking split and stop sequences."""

from __future__ import annotations

import asyncio

from runanywhere import _generation
from runanywhere._generation import StopSequences
from runanywhere.events import GenerationEventKind
from runanywhere.results import FinishReason, TokenKind


def _run(tokens, **kwargs):
    return list(
        _generation.run(
            iter(tokens), model="m", request_id="r1", now=lambda: 0.0, **kwargs
        )
    )


# --------------------------------------------------------------------------- grammar
def test_stream_starts_and_completes() -> None:
    events = _run(["Hello", " world"])
    assert events[0].kind == GenerationEventKind.STARTED
    assert events[-1].kind == GenerationEventKind.COMPLETED
    assert "".join(e.text for e in events if e.is_token) == "Hello world"
    assert events[-1].result.text == "Hello world"


def test_result_carries_the_metrics_block() -> None:
    result = _generation.collect(
        _generation.run(iter(["a", "b"]), model="m", request_id="r1")
    )
    assert result.output_tokens == 2
    assert result.input_tokens == 0  # the bridge reports no prompt-token count
    assert result.request_id == "r1" and result.model == "m"
    assert result.tokens_per_second >= 0.0
    assert result.time_to_first_token_ms >= 0.0


def test_max_output_tokens_reached_reports_length() -> None:
    events = _run(["a", "b"], max_output_tokens=2)
    assert events[-1].result.finish_reason == FinishReason.LENGTH


def test_empty_stream_still_completes() -> None:
    events = _run([])
    assert [e.kind for e in events] == [
        GenerationEventKind.STARTED,
        GenerationEventKind.COMPLETED,
    ]
    assert events[-1].result.text == ""


# --------------------------------------------------------------------------- thinking
def test_thoughts_are_tagged_and_kept_out_of_the_answer() -> None:
    events = _run(["<think>", "why", "</think>", "Paris"], include_thoughts=True)
    assert "".join(e.text for e in events if e.token_kind == TokenKind.THOUGHT) == "why"
    assert "".join(e.text for e in events if e.is_token and not e.is_thought) == "Paris"
    assert events[-1].result.text == "Paris"
    assert events[-1].result.thinking_text == "why"
    assert events[-1].result.output_tokens == 4  # throughput counts raw source tokens


def test_thoughts_are_stripped_by_default() -> None:
    events = _run(["<think>", "why", "</think>", "Paris"])
    assert all(not e.is_thought for e in events)
    assert events[-1].result.text == "Paris"
    assert events[-1].result.thinking_text is None


# --------------------------------------------------------------------------- stop sequences
def test_stop_sequence_truncates_and_ends_the_stream() -> None:
    events = _run(["Hello", " world", "\nUser:", " more"], stop_sequences=["\nUser:"])
    assert "".join(e.text for e in events if e.is_token) == "Hello world"
    assert events[-1].result.finish_reason == FinishReason.STOP


def test_stop_sequence_split_across_tokens() -> None:
    events = _run(["ab", "ST", "OP", "cd"], stop_sequences=["STOP"])
    assert "".join(e.text for e in events if e.is_token) == "ab"


def test_no_stop_sequences_emits_everything() -> None:
    events = _run(["a", "b", "c"])
    assert "".join(e.text for e in events if e.is_token) == "abc"


def test_stop_buffer_holds_back_partial_matches() -> None:
    stops = StopSequences(["END"])
    assert stops.push("hello E") == "hello"
    assert stops.push("N") == " "  # the space can no longer be part of "END"
    assert stops.push("D tail") == ""
    assert stops.stopped is True
    assert stops.flush() == ""


def test_stop_buffer_flushes_unmatched_tail() -> None:
    stops = StopSequences(["END"])
    assert stops.push("abcE") == "ab"
    assert stops.flush() == "cE"


# --------------------------------------------------------------------------- async
def test_async_run_matches_the_sync_pipeline() -> None:
    async def source():
        for token in ["Par", "is"]:
            yield token

    async def go():
        return [
            event
            async for event in _generation.arun(source(), model="m", request_id="r1")
        ]

    events = asyncio.run(go())
    assert events[-1].result.text == "Paris"
    assert events[0].kind == GenerationEventKind.STARTED


def test_acollect_returns_the_terminal_result() -> None:
    async def source():
        yield "hi"

    async def go():
        return await _generation.acollect(
            _generation.arun(source(), model="m", request_id="r1")
        )

    assert asyncio.run(go()).text == "hi"
