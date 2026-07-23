"""Tests for host-side thinking/answer separation (ThinkingSplitter + stream_with_metrics)."""
from __future__ import annotations

from runanywhere._thinking_splitter import ThinkingSplitter
from runanywhere.stream_metrics import stream_with_metrics


def _split(tokens: list[str]) -> tuple[str, str]:
    """Run tokens through a splitter and return (answer, thinking) concatenations."""
    sp = ThinkingSplitter()
    answer = thinking = ""
    for tok in tokens:
        for text, is_thinking in sp.push(tok):
            if is_thinking:
                thinking += text
            else:
                answer += text
    for text, is_thinking in sp.flush():
        if is_thinking:
            thinking += text
        else:
            answer += text
    return answer, thinking


# --------------------------------------------------------------------------- splitter
def test_plain_text_is_all_answer():
    assert _split(["Hello", " world"]) == ("Hello world", "")


def test_single_think_block():
    assert _split(["<think>reason</think>answer"]) == ("answer", "reason")


def test_thinking_tag_variant():
    assert _split(["<thinking>r</thinking>a"]) == ("a", "r")


def test_think_block_at_start_streamed_char_by_char():
    tokens = list("<think>because</think>Paris")
    assert _split(tokens) == ("Paris", "because")


def test_partial_tag_split_across_token_boundaries():
    # The opening tag is split "<thi" | "nk>", and the close is split too.
    assert _split(["hi <thi", "nk>reason</thi", "nk> bye"]) == ("hi  bye", "reason")


def test_unclosed_think_is_treated_as_thinking():
    # No closing tag -> everything after <think> is thinking (matches the native extractor).
    assert _split(["<think>still going"]) == ("", "still going")


def test_text_with_lone_angle_bracket_is_preserved():
    # A '<' that never becomes a tag must survive intact.
    assert _split(["a<", "b c"]) == ("a<b c", "")


def test_answer_before_and_after_thinking():
    assert _split(["pre <think>mid</think> post"]) == ("pre  post", "mid")


# --------------------------------------------------------------------------- stream_with_metrics
def _tokens(*t):
    yield from t


def test_stream_metrics_splits_thinking_into_result():
    events = list(stream_with_metrics(_tokens("<think>", "why", "</think>", "Paris"), now=lambda: 0.0))
    body = [e for e in events if not e.is_final]
    final = events[-1]
    # answer tokens vs thinking tokens are tagged
    assert "".join(e.token for e in body if not e.is_thinking) == "Paris"
    assert "".join(e.token for e in body if e.is_thinking) == "why"
    # final result carries the clean answer + the reasoning
    assert final.result.text == "Paris"
    assert final.result.thinking_content == "why"
    # throughput still counts the raw source tokens (4)
    assert final.result.token_count == 4


def test_stream_metrics_plain_is_unchanged():
    events = list(stream_with_metrics(_tokens("Hello", " world"), now=lambda: 0.0))
    body = [e for e in events if not e.is_final]
    assert "".join(e.token for e in body) == "Hello world"
    assert all(not e.is_thinking for e in body)
    assert events[-1].result.text == "Hello world"
    assert events[-1].result.thinking_content is None
