"""Event types for every stream, plus the SDK-level event bus.

One grammar everywhere: a stream emits ``started``, then deltas, then ``completed`` — or
raises into the consumer. Each event family is a single dataclass carrying a ``kind`` so a
consumer can switch on it without isinstance chains.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Callable, Dict, List, Optional

from .inputs import ModelCategory
from .results import (
    GenerationResult,
    ImageResult,
    Match,
    ModelInfo,
    RagResult,
    TokenKind,
    ToolCall,
    Transcription,
)

__all__ = [
    "DownloadEvent",
    "DownloadEventKind",
    "EventBus",
    "GenerationEvent",
    "GenerationEventKind",
    "ImageEvent",
    "ImageEventKind",
    "RagEvent",
    "RagEventKind",
    "SdkEvent",
    "SdkEventKind",
    "TranscriptionEvent",
    "TranscriptionEventKind",
    "VadEvent",
    "VadEventKind",
    "VoiceAgentState",
    "VoiceEvent",
    "VoiceEventKind",
    "bus",
]


class GenerationEventKind(IntEnum):
    """Stages of a generation stream."""

    STARTED = 0
    TOKEN = 1
    TOOL_CALL = 2
    COMPLETED = 3


@dataclass
class GenerationEvent:
    """One event of an ``llm``/``vlm`` stream."""

    kind: GenerationEventKind
    request_id: str = ""
    text: str = ""
    token_kind: TokenKind = TokenKind.TEXT
    tool_call: Optional[ToolCall] = None
    result: Optional[GenerationResult] = None

    @property
    def is_token(self) -> bool:
        """True for a token delta."""
        return self.kind == GenerationEventKind.TOKEN

    @property
    def is_completed(self) -> bool:
        """True for the terminal event, whose ``result`` carries the metrics."""
        return self.kind == GenerationEventKind.COMPLETED

    @property
    def is_thought(self) -> bool:
        """True when this token is the model's thinking rather than its answer."""
        return self.kind == GenerationEventKind.TOKEN and self.token_kind == TokenKind.THOUGHT


class TranscriptionEventKind(IntEnum):
    """Stages of a transcription stream."""

    STARTED = 0
    PARTIAL = 1
    FINAL = 2


@dataclass
class TranscriptionEvent:
    """One event of an ``stt`` stream."""

    kind: TranscriptionEventKind
    text: str = ""
    result: Optional[Transcription] = None


class VadEventKind(IntEnum):
    """Stages of a speech-detection stream."""

    SPEECH_STARTED = 0
    SPEECH_ENDED = 1


@dataclass
class VadEvent:
    """One speech boundary detected in an audio stream."""

    kind: VadEventKind
    timestamp_ms: int = 0


class VoiceAgentState(IntEnum):
    """What a voice session's agent is doing."""

    LISTENING = 0
    THINKING = 1
    SPEAKING = 2


class VoiceEventKind(IntEnum):
    """Kinds of voice-session event."""

    USER_TRANSCRIBED = 0
    AGENT_STATE_CHANGED = 1
    AGENT_RESPONSE = 2
    SPEECH_STARTED = 3
    SPEECH_ENDED = 4
    ERROR = 5


@dataclass
class VoiceEvent:
    """One event emitted by a voice session."""

    kind: VoiceEventKind
    text: str = ""
    is_final: bool = False
    state: Optional[VoiceAgentState] = None
    message: str = ""
    recoverable: bool = True


class RagEventKind(IntEnum):
    """Stages of a RAG query stream."""

    RETRIEVED = 0
    TOKEN = 1
    COMPLETED = 2


@dataclass
class RagEvent:
    """One event of a ``RagSession.query_stream``."""

    kind: RagEventKind
    matches: List[Match] = field(default_factory=list)
    text: str = ""
    token_kind: TokenKind = TokenKind.TEXT
    result: Optional[RagResult] = None

    @property
    def is_token(self) -> bool:
        """True for an answer-token delta."""
        return self.kind == RagEventKind.TOKEN

    @property
    def is_completed(self) -> bool:
        """True for the terminal event, whose ``result`` carries the answer."""
        return self.kind == RagEventKind.COMPLETED


class ImageEventKind(IntEnum):
    """Stages of an image generation stream."""

    STARTED = 0
    PROGRESS = 1
    COMPLETED = 2


@dataclass
class ImageEvent:
    """One event of an ``images`` stream."""

    kind: ImageEventKind
    step: int = 0
    total_steps: int = 0
    partial_image: Optional[bytes] = None
    result: Optional[ImageResult] = None


class DownloadEventKind(IntEnum):
    """Stages of a model download."""

    PROGRESS = 0
    EXTRACTING = 1
    COMPLETED = 2


@dataclass
class DownloadEvent:
    """One event of ``models.download``."""

    kind: DownloadEventKind
    file: str = ""
    bytes_done: int = 0
    bytes_total: int = 0
    percent: int = 0
    model: Optional[ModelInfo] = None


class SdkEventKind(IntEnum):
    """Kinds of SDK-level breadcrumb."""

    READY = 0
    MODEL_LOADED = 1
    MODEL_UNLOADED = 2
    ERROR = 3


@dataclass(frozen=True)
class SdkEvent:
    """A lifecycle, model or error breadcrumb published on :data:`bus`."""

    kind: SdkEventKind
    model_id: Optional[str] = None
    category: Optional[ModelCategory] = None
    message: str = ""
    recoverable: bool = True


EventListener = Callable[[SdkEvent], None]


class EventBus:
    """Pub/sub bus for :class:`SdkEvent` where a throwing listener never breaks an emit."""

    def __init__(self) -> None:
        # dict preserves insertion order and gives set-like membership; the value is unused.
        self._listeners: Dict[EventListener, None] = {}

    def on(self, listener: EventListener) -> Callable[[], None]:
        """Subscribe to all events; returns the unsubscribe function."""
        self._listeners[listener] = None

        def off() -> None:
            self._listeners.pop(listener, None)

        return off

    def once(self, listener: EventListener) -> Callable[[], None]:
        """Subscribe to the next event only; returns the unsubscribe function."""

        def wrapper(event: SdkEvent) -> None:
            off()
            listener(event)

        off = self.on(wrapper)
        return off

    def off(self, listener: EventListener) -> None:
        """Unsubscribe a listener (no-op if it was never registered)."""
        self._listeners.pop(listener, None)

    def emit(self, event: SdkEvent) -> None:
        """Publish an event to every listener."""
        for listener in list(self._listeners):
            try:
                listener(event)
            except Exception:  # noqa: BLE001
                # A misbehaving listener must not disrupt the others. Catch Exception (NOT
                # BaseException) so KeyboardInterrupt / SystemExit / CancelledError still
                # propagate. Log the traceback only — never the event payload.
                logging.getLogger(__name__).exception("EventBus listener failed")

    def remove_all(self) -> None:
        """Drop every registered listener."""
        self._listeners.clear()

    @property
    def listener_count(self) -> int:
        """Number of currently registered listeners."""
        return len(self._listeners)


#: The process-wide bus exposed as ``runanywhere.events``.
bus = EventBus()
