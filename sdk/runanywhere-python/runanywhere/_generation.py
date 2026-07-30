"""Turn the bridge's raw token stream into the spec's generation events and result.

One place owns everything that sits between ``_core.generate`` and a caller: the
thinking/answer split, host-side stop sequences, the metrics block, and the terminal
``completed`` event. Both the sync and async paths run the same rules.
"""

from __future__ import annotations

import time
from typing import AsyncIterable, AsyncIterator, Callable, Iterable, Iterator, List, Optional

from ._thinking_splitter import ThinkingSplitter
from .events import GenerationEvent, GenerationEventKind
from .results import FinishReason, GenerationResult, TokenKind

__all__ = ["StopSequences", "acollect", "arun", "collect", "run"]


def _now_ms() -> float:
    return time.monotonic() * 1000.0


class StopSequences:
    """Truncates answer text at the first stop sequence, holding back partial matches.

    The bridge has no stop-sequence parameter, so the SDK enforces them: text that could
    still turn out to be the start of a stop sequence is buffered rather than emitted, so a
    caller never sees output from beyond the stop point.
    """

    def __init__(self, sequences: Optional[List[str]] = None) -> None:
        self._sequences = [s for s in (sequences or []) if s]
        self._buffer = ""
        self._hold = max((len(s) for s in self._sequences), default=1) - 1
        self.stopped = False

    def push(self, text: str) -> str:
        """Feed answer text; return the part that is safe to emit."""
        if not self._sequences or self.stopped:
            return "" if self.stopped else text
        self._buffer += text
        cut = min(
            (i for i in (self._buffer.find(s) for s in self._sequences) if i >= 0), default=-1
        )
        if cut >= 0:
            self.stopped = True
            out, self._buffer = self._buffer[:cut], ""
            return out
        keep = min(self._hold, len(self._buffer))
        if keep <= 0:
            out, self._buffer = self._buffer, ""
            return out
        out = self._buffer[:-keep]
        self._buffer = self._buffer[-keep:]
        return out

    def flush(self) -> str:
        """Return whatever is still buffered once the stream ends."""
        if self.stopped:
            return ""
        out, self._buffer = self._buffer, ""
        return out


class _Accumulator:
    """Shared state of one generation: text, thinking, counts and timings."""

    def __init__(
        self,
        *,
        model: str,
        request_id: str,
        include_thoughts: bool,
        stop_sequences: Optional[List[str]],
        max_output_tokens: Optional[int],
        now: Callable[[], float],
    ) -> None:
        self.model = model
        self.request_id = request_id
        self.include_thoughts = include_thoughts
        self.max_output_tokens = max_output_tokens
        self.now = now
        self.splitter = ThinkingSplitter()
        self.stops = StopSequences(stop_sequences)
        self.answer = ""
        self.thinking = ""
        self.count = 0
        self.start = now()
        self.first_at = -1.0

    def push(self, token: str) -> Iterator[GenerationEvent]:
        """Consume one raw token, yielding the events it produces."""
        if self.first_at < 0:
            self.first_at = self.now()
        self.count += 1
        for text, is_thinking in self.splitter.push(token):
            yield from self._piece(text, is_thinking)

    def flush(self) -> Iterator[GenerationEvent]:
        """Drain the thinking splitter and the stop-sequence buffer."""
        for text, is_thinking in self.splitter.flush():
            yield from self._piece(text, is_thinking)
        tail = self.stops.flush()
        if tail:
            self.answer += tail
            yield GenerationEvent(
                kind=GenerationEventKind.TOKEN,
                request_id=self.request_id,
                text=tail,
                token_kind=TokenKind.TEXT,
            )

    def _piece(self, text: str, is_thinking: bool) -> Iterator[GenerationEvent]:
        if is_thinking:
            self.thinking += text
            if self.include_thoughts:
                yield GenerationEvent(
                    kind=GenerationEventKind.TOKEN,
                    request_id=self.request_id,
                    text=text,
                    token_kind=TokenKind.THOUGHT,
                )
            return
        emit = self.stops.push(text)
        self.answer += emit
        if emit:
            yield GenerationEvent(
                kind=GenerationEventKind.TOKEN,
                request_id=self.request_id,
                text=emit,
                token_kind=TokenKind.TEXT,
            )

    @property
    def done(self) -> bool:
        """True once a stop sequence has been hit and the stream can be abandoned."""
        return self.stops.stopped

    def result(self, tool_calls=None) -> GenerationResult:
        """Build the terminal result with its metrics block."""
        end = self.now()
        gen_ms = 0.0 if self.first_at < 0 else end - self.first_at
        if tool_calls:
            reason = FinishReason.TOOL_CALLS
        elif self.max_output_tokens and self.count >= self.max_output_tokens:
            reason = FinishReason.LENGTH
        else:
            reason = FinishReason.STOP
        return GenerationResult(
            text=self.answer,
            thinking_text=(self.thinking or None) if self.include_thoughts else None,
            tool_calls=list(tool_calls or []),
            finish_reason=reason,
            # The bridge reports no prompt-token count, so input_tokens stays 0.
            input_tokens=0,
            output_tokens=self.count,
            time_to_first_token_ms=0.0 if self.first_at < 0 else self.first_at - self.start,
            tokens_per_second=(self.count / (gen_ms / 1000.0)) if gen_ms > 0 else 0.0,
            request_id=self.request_id,
            model=self.model,
        )


def run(
    tokens: Iterable[str],
    *,
    model: str,
    request_id: str,
    include_thoughts: bool = False,
    stop_sequences: Optional[List[str]] = None,
    max_output_tokens: Optional[int] = None,
    now: Callable[[], float] = _now_ms,
) -> Iterator[GenerationEvent]:
    """Stream ``started``, token deltas, then ``completed`` over a raw token iterable."""
    acc = _Accumulator(
        model=model,
        request_id=request_id,
        include_thoughts=include_thoughts,
        stop_sequences=stop_sequences,
        max_output_tokens=max_output_tokens,
        now=now,
    )
    yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id=request_id)
    iterator = iter(tokens)
    try:
        for token in iterator:
            for event in acc.push(token):
                yield event
            if acc.done:
                break
    finally:
        close = getattr(iterator, "close", None)
        if close is not None:
            close()
    for event in acc.flush():
        yield event
    yield GenerationEvent(
        kind=GenerationEventKind.COMPLETED, request_id=request_id, result=acc.result()
    )


async def arun(
    tokens: AsyncIterable[str],
    *,
    model: str,
    request_id: str,
    include_thoughts: bool = False,
    stop_sequences: Optional[List[str]] = None,
    max_output_tokens: Optional[int] = None,
    now: Callable[[], float] = _now_ms,
) -> AsyncIterator[GenerationEvent]:
    """Async twin of :func:`run`."""
    acc = _Accumulator(
        model=model,
        request_id=request_id,
        include_thoughts=include_thoughts,
        stop_sequences=stop_sequences,
        max_output_tokens=max_output_tokens,
        now=now,
    )
    yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id=request_id)
    iterator = tokens.__aiter__()
    try:
        while True:
            try:
                token = await iterator.__anext__()
            except StopAsyncIteration:
                break
            for event in acc.push(token):
                yield event
            if acc.done:
                break
    finally:
        aclose = getattr(iterator, "aclose", None)
        if aclose is not None:
            await aclose()
    for event in acc.flush():
        yield event
    yield GenerationEvent(
        kind=GenerationEventKind.COMPLETED, request_id=request_id, result=acc.result()
    )


def collect(events: Iterable[GenerationEvent]) -> GenerationResult:
    """Drain a generation stream and return its terminal result."""
    result: Optional[GenerationResult] = None
    for event in events:
        if event.kind == GenerationEventKind.COMPLETED and event.result is not None:
            result = event.result
    return result if result is not None else GenerationResult()


async def acollect(events: AsyncIterable[GenerationEvent]) -> GenerationResult:
    """Async twin of :func:`collect`."""
    result: Optional[GenerationResult] = None
    async for event in events:
        if event.kind == GenerationEventKind.COMPLETED and event.result is not None:
            result = event.result
    return result if result is not None else GenerationResult()
