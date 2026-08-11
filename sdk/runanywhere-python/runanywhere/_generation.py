"""Turn commons-typed stream deltas into the spec's generation events and result.

Thinking vs answer content and the terminal finish reason arrive already
classified by commons (``LLMStreamEvent`` / ``LLMGenerationResult``). This
module accumulates transport text and forwards commons usage — it never
parses ``<think>`` tags and never invents STOP/LENGTH/TOOL_CALLS from
token counts or tool-call presence.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import (
    AsyncIterable,
    AsyncIterator,
    Iterable,
    Iterator,
    List,
    Mapping,
    Optional,
    Union,
)

from .events import GenerationEvent, GenerationEventKind
from .results import FinishReason, GenerationResult, TokenKind

__all__ = [
    "StreamDelta",
    "StopSequences",
    "UsageMetrics",
    "acollect",
    "arun",
    "collect",
    "run",
]

#: Mapping carrying commons TokenUsage fields for the terminal result.
UsageMetrics = Mapping[str, Union[int, float]]


@dataclass(frozen=True)
class StreamDelta:
    """One commons-typed stream piece, or a terminal marker with commons fields."""

    text: str = ""
    is_thinking: bool = False
    is_terminal: bool = False
    finish_reason: Optional[FinishReason] = None
    usage: Optional[UsageMetrics] = None
    final_text: Optional[str] = None
    final_thinking: Optional[str] = None


def _usage_number(usage: Optional[UsageMetrics], *keys: str, default: float = 0.0) -> float:
    if usage is None:
        return default
    for key in keys:
        if key in usage and usage[key] is not None:
            return float(usage[key])
    return default


def _map_finish_reason(value: Optional[Union[FinishReason, int]]) -> FinishReason:
    """Map a commons FinishReason wire value; unspecified stays unspecified."""
    if value is None:
        return FinishReason.UNSPECIFIED
    try:
        return FinishReason(int(value))
    except ValueError:
        return FinishReason.UNSPECIFIED


class StopSequences:
    """Truncates answer text at the first stop sequence, holding back partial matches.

    Prefer engine-enforced ``stop_sequences`` on the commons options path. This
    buffer remains for callers that still pass host-side sequences when the
    bridge has not yet forwarded them.
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
    """Shared state of one generation: text and thinking accumulation only."""

    def __init__(
        self,
        *,
        model: str,
        request_id: str,
        include_thoughts: bool,
        stop_sequences: Optional[List[str]],
        usage: Optional[UsageMetrics] = None,
        finish_reason: Optional[Union[FinishReason, int]] = None,
        final_text: Optional[str] = None,
        final_thinking: Optional[str] = None,
    ) -> None:
        self.model = model
        self.request_id = request_id
        self.include_thoughts = include_thoughts
        self.usage = usage
        self.finish_reason = _map_finish_reason(finish_reason)
        self.final_text = final_text
        self.final_thinking = final_thinking
        self.stops = StopSequences(stop_sequences)
        self.answer = ""
        self.thinking = ""

    def push(self, delta: StreamDelta) -> Iterator[GenerationEvent]:
        """Consume one commons-typed delta, yielding the events it produces."""
        if delta.is_terminal:
            if delta.finish_reason is not None:
                self.finish_reason = _map_finish_reason(delta.finish_reason)
            if delta.usage is not None:
                self.usage = delta.usage
            if delta.final_text is not None:
                self.final_text = delta.final_text
            if delta.final_thinking is not None:
                self.final_thinking = delta.final_thinking
            return
        yield from self._piece(delta.text, delta.is_thinking)

    def flush(self) -> Iterator[GenerationEvent]:
        """Drain the stop-sequence buffer."""
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
        if not text:
            return
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

    def result(self, tool_calls=None, usage: Optional[UsageMetrics] = None) -> GenerationResult:
        """Build the terminal result from commons fields only."""
        metrics = usage if usage is not None else self.usage
        text = self.final_text if self.final_text is not None else self.answer
        thinking = self.final_thinking if self.final_thinking is not None else self.thinking
        return GenerationResult(
            text=text,
            thinking_text=(thinking or None) if self.include_thoughts else None,
            tool_calls=list(tool_calls or []),
            finish_reason=self.finish_reason,
            input_tokens=int(_usage_number(metrics, "input_tokens", default=0.0)),
            output_tokens=int(_usage_number(metrics, "output_tokens", default=0.0)),
            time_to_first_token_ms=_usage_number(
                metrics, "time_to_first_token_ms", "ttft_ms", default=0.0
            ),
            tokens_per_second=_usage_number(
                metrics, "tokens_per_second", "decode_tokens_per_second", default=0.0
            ),
            request_id=self.request_id,
            model=self.model,
        )


def _as_delta(item: Union[StreamDelta, str]) -> StreamDelta:
    """Accept typed deltas; bare strings are answer transport bytes (never tag-parsed)."""
    if isinstance(item, StreamDelta):
        return item
    return StreamDelta(text=item, is_thinking=False)


def run(
    deltas: Iterable[Union[StreamDelta, str]],
    *,
    model: str,
    request_id: str,
    include_thoughts: bool = False,
    stop_sequences: Optional[List[str]] = None,
    usage: Optional[UsageMetrics] = None,
    finish_reason: Optional[Union[FinishReason, int]] = None,
    final_text: Optional[str] = None,
    final_thinking: Optional[str] = None,
) -> Iterator[GenerationEvent]:
    """Stream ``started``, token deltas, then ``completed`` over commons-typed pieces."""
    acc = _Accumulator(
        model=model,
        request_id=request_id,
        include_thoughts=include_thoughts,
        stop_sequences=stop_sequences,
        usage=usage,
        finish_reason=finish_reason,
        final_text=final_text,
        final_thinking=final_thinking,
    )
    yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id=request_id)
    iterator = iter(deltas)
    try:
        for item in iterator:
            for event in acc.push(_as_delta(item)):
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
    deltas: AsyncIterable[Union[StreamDelta, str]],
    *,
    model: str,
    request_id: str,
    include_thoughts: bool = False,
    stop_sequences: Optional[List[str]] = None,
    usage: Optional[UsageMetrics] = None,
    finish_reason: Optional[Union[FinishReason, int]] = None,
    final_text: Optional[str] = None,
    final_thinking: Optional[str] = None,
) -> AsyncIterator[GenerationEvent]:
    """Async twin of :func:`run`."""
    acc = _Accumulator(
        model=model,
        request_id=request_id,
        include_thoughts=include_thoughts,
        stop_sequences=stop_sequences,
        usage=usage,
        finish_reason=finish_reason,
        final_text=final_text,
        final_thinking=final_thinking,
    )
    yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id=request_id)
    iterator = deltas.__aiter__()
    try:
        while True:
            try:
                item = await iterator.__anext__()
            except StopAsyncIteration:
                break
            for event in acc.push(_as_delta(item)):
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
