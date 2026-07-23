"""A small typed event bus for lifecycle + telemetry (port of electron events.ts)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Callable, Union

if TYPE_CHECKING:
    # Lazy type-only import so events.py has no runtime dependency on results.py,
    # avoiding a hard import cycle (results <-> events).
    from .results import LLMGenerationResult


@dataclass(frozen=True)
class InitializedEvent:
    """Emitted once the native SDK has been initialized."""


@dataclass(frozen=True)
class ServicesReadyEvent:
    """Emitted when background services are ready."""


@dataclass(frozen=True)
class ShutdownEvent:
    """Emitted when the native SDK has been shut down."""


@dataclass(frozen=True)
class ModelLoadedEvent:
    """Emitted after a model of the given modality is loaded."""

    modality: str
    id: str


@dataclass(frozen=True)
class ModelUnloadedEvent:
    """Emitted after a model of the given modality is unloaded."""

    modality: str


@dataclass(frozen=True)
class GenerationEvent:
    """Emitted after a generateStream completes; carries timing/throughput metrics."""

    result: "LLMGenerationResult"


RunAnywhereEvent = Union[
    InitializedEvent,
    ServicesReadyEvent,
    ShutdownEvent,
    ModelLoadedEvent,
    ModelUnloadedEvent,
    GenerationEvent,
]

EventListener = Callable[[RunAnywhereEvent], None]


class EventBus:
    """Pub/sub bus where a throwing listener never breaks an emit."""

    def __init__(self) -> None:
        # dict preserves insertion order and gives set-like membership; the value
        # is unused (only the key identity matters), mirroring the electron Set.
        self._listeners: dict[EventListener, None] = {}

    def on(self, listener: EventListener) -> Callable[[], None]:
        """Subscribe to all events; returns an unsubscribe function."""
        self._listeners[listener] = None

        def off() -> None:
            self._listeners.pop(listener, None)

        return off

    def once(self, listener: EventListener) -> Callable[[], None]:
        """Subscribe to the next event only; returns an unsubscribe function."""

        def wrapper(event: RunAnywhereEvent) -> None:
            off()
            listener(event)

        off = self.on(wrapper)
        return off

    def off(self, listener: EventListener) -> None:
        """Unsubscribe a previously registered listener (no-op if absent)."""
        self._listeners.pop(listener, None)

    def emit(self, event: RunAnywhereEvent) -> None:
        """Emit an event to all listeners; a throwing listener never breaks the emit."""
        for listener in list(self._listeners):
            try:
                listener(event)
            except Exception:
                # A misbehaving listener must not disrupt the others. Catch Exception
                # (NOT BaseException) so control-flow signals — KeyboardInterrupt,
                # SystemExit, asyncio.CancelledError (a BaseException since 3.8) — still
                # propagate to the caller instead of being silently swallowed here.
                pass

    def remove_all(self) -> None:
        """Drop every registered listener."""
        self._listeners.clear()

    @property
    def listener_count(self) -> int:
        """Number of currently registered listeners."""
        return len(self._listeners)


# Process-wide singleton exposed as RunAnywhere.events.
bus = EventBus()
