"""Host-side thinking/answer separation (ThinkingSplitter)."""
from __future__ import annotations

from runanywhere._thinking_splitter import ThinkingSplitter


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
