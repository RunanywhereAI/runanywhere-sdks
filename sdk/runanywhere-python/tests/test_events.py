"""Tests for the EventBus pub/sub bus (events.py)."""
from __future__ import annotations

import os
import sys

# Ensure the package parent (sdk/runanywhere-python) is importable regardless of
# the pytest invocation cwd. The `runanywhere` package resolves as a namespace
# package even before its __init__.py is authored in parallel.
_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

from runanywhere.events import (  # noqa: E402
    EventBus,
    GenerationEvent,
    InitializedEvent,
    ModelLoadedEvent,
    ModelUnloadedEvent,
    ServicesReadyEvent,
    ShutdownEvent,
    bus,
)


def test_events_are_frozen_dataclasses() -> None:
    ml = ModelLoadedEvent(modality="llm", id="m1")
    assert ml.modality == "llm"
    assert ml.id == "m1"
    with pytest.raises(Exception):
        ml.id = "changed"  # type: ignore[misc]

    mu = ModelUnloadedEvent(modality="vlm")
    assert mu.modality == "vlm"

    # Lifecycle events construct with no args; equality by value.
    assert InitializedEvent() == InitializedEvent()
    assert ServicesReadyEvent() == ServicesReadyEvent()
    assert ShutdownEvent() == ShutdownEvent()

    gen = GenerationEvent(result="dummy-result")  # type: ignore[arg-type]
    assert gen.result == "dummy-result"


def test_module_singleton_is_eventbus() -> None:
    assert isinstance(bus, EventBus)


def test_on_receives_events_and_returns_unsubscribe() -> None:
    b = EventBus()
    received: list[object] = []
    unsub = b.on(received.append)
    assert callable(unsub)
    assert b.listener_count == 1

    ev = InitializedEvent()
    b.emit(ev)
    assert received == [ev]

    # Unsubscribe stops further delivery.
    unsub()
    assert b.listener_count == 0
    b.emit(ServicesReadyEvent())
    assert received == [ev]


def test_off_removes_listener() -> None:
    b = EventBus()
    received: list[object] = []
    b.on(received.append)
    b.off(received.append)
    assert b.listener_count == 0
    b.emit(ShutdownEvent())
    assert received == []


def test_off_unknown_listener_is_noop() -> None:
    b = EventBus()
    # Removing something that was never added must not raise.
    b.off(lambda _e: None)
    assert b.listener_count == 0


def test_once_fires_exactly_once() -> None:
    b = EventBus()
    received: list[object] = []
    b.once(received.append)
    assert b.listener_count == 1

    e1 = InitializedEvent()
    e2 = ServicesReadyEvent()
    b.emit(e1)
    b.emit(e2)

    assert received == [e1]
    assert b.listener_count == 0


def test_once_returns_working_unsubscribe() -> None:
    b = EventBus()
    received: list[object] = []
    unsub = b.once(received.append)
    unsub()
    assert b.listener_count == 0
    b.emit(InitializedEvent())
    assert received == []


def test_emit_calls_all_listeners() -> None:
    b = EventBus()
    a_calls: list[object] = []
    b_calls: list[object] = []
    b.on(a_calls.append)
    b.on(b_calls.append)

    ev = ModelLoadedEvent(modality="stt", id="whisper")
    b.emit(ev)

    assert a_calls == [ev]
    assert b_calls == [ev]


def test_throwing_listener_does_not_break_emit() -> None:
    b = EventBus()
    order: list[str] = []

    def bad(_e: object) -> None:
        order.append("bad")
        raise RuntimeError("boom")

    def good(_e: object) -> None:
        order.append("good")

    b.on(bad)
    b.on(good)

    # emit itself must not raise, and the good listener must still run.
    b.emit(GenerationEvent(result="r"))  # type: ignore[arg-type]
    assert order == ["bad", "good"]

    # A second emit still reaches both (a throwing listener is not removed).
    order.clear()
    b.emit(GenerationEvent(result="r2"))  # type: ignore[arg-type]
    assert order == ["bad", "good"]


def test_listener_unsubscribing_during_emit_is_safe() -> None:
    b = EventBus()
    calls: list[str] = []

    def self_removing(_e: object) -> None:
        calls.append("self_removing")
        unsub()

    def other(_e: object) -> None:
        calls.append("other")

    unsub = b.on(self_removing)
    b.on(other)

    # Mutating the listener set during iteration must not raise (snapshot copy).
    b.emit(InitializedEvent())
    assert calls == ["self_removing", "other"]
    assert b.listener_count == 1  # only `other` remains


def test_remove_all_clears_listeners() -> None:
    b = EventBus()
    received: list[object] = []
    b.on(received.append)
    b.once(received.append)
    assert b.listener_count == 2

    b.remove_all()
    assert b.listener_count == 0
    b.emit(ShutdownEvent())
    assert received == []


def test_listener_count_tracks_registrations() -> None:
    b = EventBus()
    assert b.listener_count == 0
    u1 = b.on(lambda _e: None)
    assert b.listener_count == 1
    b.on(lambda _e: None)
    assert b.listener_count == 2
    u1()
    assert b.listener_count == 1


def test_same_callable_registered_once() -> None:
    # Set semantics: adding the identical callable twice keeps a single entry.
    b = EventBus()

    def listener(_e: object) -> None:
        pass

    b.on(listener)
    b.on(listener)
    assert b.listener_count == 1
