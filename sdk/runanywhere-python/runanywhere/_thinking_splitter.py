"""Split a token stream into 'thinking' vs 'answer' segments, host-side.

Thinking models emit their reasoning inline inside ``<think>…</think>`` (or ``<thinking>…</thinking>``)
tags, mixed into the same token stream as the answer. This is a small streaming state machine that
separates the two — correctly even when a tag is split across token boundaries (e.g. ``"…<thi"`` then
``"nk>…"``). It mirrors what commons' ``rac_llm_extract_thinking`` does internally, but stays purely
in Python so the SDK never depends on the (thread-local) native parser.
"""
from __future__ import annotations

_OPEN = ("<think>", "<thinking>")
_CLOSE = ("</think>", "</thinking>")
_MAX_OPEN = max(len(t) for t in _OPEN)
_MAX_CLOSE = max(len(t) for t in _CLOSE)


def _earliest_tag(buf: str, tags: tuple[str, ...]) -> tuple[int, str] | None:
    """The earliest complete occurrence of any tag in ``buf`` (by start index), or None."""
    best: tuple[int, str] | None = None
    for tag in tags:
        i = buf.find(tag)
        if i != -1 and (best is None or i < best[0]):
            best = (i, tag)
    return best


def _held_prefix_len(buf: str, tags: tuple[str, ...], max_len: int) -> int:
    """Length of the longest suffix of ``buf`` that is a (partial) prefix of some tag.

    That suffix might be the start of a tag whose remainder arrives in the next token, so we hold
    it back rather than emit it as text.
    """
    for length in range(min(len(buf), max_len), 0, -1):
        suffix = buf[-length:]
        if any(tag.startswith(suffix) for tag in tags):
            return length
    return 0


class ThinkingSplitter:
    """Feed tokens in with :meth:`push`; get back ``(text, is_thinking)`` segments. Call :meth:`flush`
    at end-of-stream to drain any buffered tail (an unclosed ``<think>`` is treated as thinking,
    matching the native extractor)."""

    def __init__(self) -> None:
        self._buf = ""
        self._thinking = False

    def push(self, token: str) -> list[tuple[str, bool]]:
        """Absorb ``token`` and return zero or more ``(text, is_thinking)`` segments ready to emit."""
        self._buf += token
        out: list[tuple[str, bool]] = []
        while True:
            tags = _CLOSE if self._thinking else _OPEN
            hit = _earliest_tag(self._buf, tags)
            if hit is not None:
                idx, tag = hit
                if idx > 0:
                    out.append((self._buf[:idx], self._thinking))
                self._buf = self._buf[idx + len(tag):]
                self._thinking = not self._thinking
                continue
            # No complete tag: emit everything except a suffix that could still become one.
            hold = _held_prefix_len(self._buf, tags, _MAX_CLOSE if self._thinking else _MAX_OPEN)
            emit = self._buf[: len(self._buf) - hold]
            if emit:
                out.append((emit, self._thinking))
            self._buf = self._buf[len(self._buf) - hold:]
            return out

    def flush(self) -> list[tuple[str, bool]]:
        """Emit any remaining buffered text at end-of-stream."""
        if not self._buf:
            return []
        out = [(self._buf, self._thinking)]
        self._buf = ""
        return out
