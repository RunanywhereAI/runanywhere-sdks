"""Commons-typed thinking deltas — host ThinkingSplitter is deleted."""

from __future__ import annotations

from runanywhere._generation import StreamDelta, run
from runanywhere.results import TokenKind


def test_typed_thinking_deltas_do_not_parse_tags() -> None:
    events = list(
        run(
            [
                StreamDelta("reason", is_thinking=True),
                StreamDelta("answer", is_thinking=False),
            ],
            model="m",
            request_id="r1",
            include_thoughts=True,
        )
    )
    assert "".join(e.text for e in events if e.token_kind == TokenKind.THOUGHT) == "reason"
    assert "".join(e.text for e in events if e.is_token and not e.is_thought) == "answer"
