"""The SDK event bus and the event value types."""
from __future__ import annotations

import os
import sys

_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

import runanywhere as ra  # noqa: E402
from runanywhere.events import (  # noqa: E402
    DownloadEvent,
    DownloadEventKind,
    EventBus,
    GenerationEvent,
    GenerationEventKind,
    ImageEvent,
    ImageEventKind,
    RagEvent,
    RagEventKind,
    SdkEvent,
    SdkEventKind,
    TranscriptionEvent,
    TranscriptionEventKind,
    VadEvent,
    VadEventKind,
    VoiceAgentState,
    VoiceEvent,
    VoiceEventKind,
    bus,
)
from runanywhere.inputs import ModelCategory  # noqa: E402
from runanywhere.results import TokenKind  # noqa: E402


# --------------------------------------------------------------------------- value types
def test_sdk_events_are_frozen() -> None:
    event = SdkEvent(kind=SdkEventKind.MODEL_LOADED, model_id="m1", category=ModelCategory.LANGUAGE)
    assert event.model_id == "m1"
    with pytest.raises(Exception):
        event.model_id = "changed"  # type: ignore[misc]
    assert SdkEvent(kind=SdkEventKind.READY) == SdkEvent(kind=SdkEventKind.READY)


def test_stream_event_families_expose_their_kind() -> None:
    token = GenerationEvent(kind=GenerationEventKind.TOKEN, text="hi")
    assert token.is_token and not token.is_completed and not token.is_thought
    thought = GenerationEvent(
        kind=GenerationEventKind.TOKEN, text="why", token_kind=TokenKind.THOUGHT
    )
    assert thought.is_thought

    assert TranscriptionEvent(kind=TranscriptionEventKind.PARTIAL, text="he").text == "he"
    assert VadEvent(kind=VadEventKind.SPEECH_STARTED, timestamp_ms=20).timestamp_ms == 20
    voice = VoiceEvent(kind=VoiceEventKind.AGENT_STATE_CHANGED, state=VoiceAgentState.THINKING)
    assert voice.state == VoiceAgentState.THINKING
    rag = RagEvent(kind=RagEventKind.TOKEN, text="a")
    assert rag.is_token and not rag.is_completed
    assert ImageEvent(kind=ImageEventKind.PROGRESS, step=2, total_steps=4).total_steps == 4
    assert DownloadEvent(kind=DownloadEventKind.PROGRESS, percent=50).percent == 50


def test_module_singleton_is_the_bus() -> None:
    assert isinstance(bus, EventBus)
    assert ra.events is bus


# --------------------------------------------------------------------------- bus behaviour
def test_on_receives_events_and_returns_unsubscribe() -> None:
    local = EventBus()
    received: list = []
    unsubscribe = local.on(received.append)
    assert local.listener_count == 1

    event = SdkEvent(kind=SdkEventKind.READY)
    local.emit(event)
    assert received == [event]

    unsubscribe()
    assert local.listener_count == 0
    local.emit(SdkEvent(kind=SdkEventKind.MODEL_UNLOADED))
    assert received == [event]


def test_off_removes_a_listener_and_ignores_unknown_ones() -> None:
    local = EventBus()
    received: list = []
    local.on(received.append)
    local.off(received.append)
    local.off(lambda _e: None)
    local.emit(SdkEvent(kind=SdkEventKind.READY))
    assert received == []


def test_once_fires_exactly_once() -> None:
    local = EventBus()
    received: list = []
    local.once(received.append)
    first = SdkEvent(kind=SdkEventKind.READY)
    local.emit(first)
    local.emit(SdkEvent(kind=SdkEventKind.MODEL_LOADED))
    assert received == [first]
    assert local.listener_count == 0


def test_once_returns_a_working_unsubscribe() -> None:
    local = EventBus()
    received: list = []
    unsubscribe = local.once(received.append)
    unsubscribe()
    local.emit(SdkEvent(kind=SdkEventKind.READY))
    assert received == []


def test_emit_reaches_every_listener() -> None:
    local = EventBus()
    first: list = []
    second: list = []
    local.on(first.append)
    local.on(second.append)
    event = SdkEvent(kind=SdkEventKind.MODEL_LOADED, model_id="whisper")
    local.emit(event)
    assert first == [event] and second == [event]


def test_throwing_listener_does_not_break_emit() -> None:
    local = EventBus()
    order: list = []

    def bad(_event) -> None:
        order.append("bad")
        raise RuntimeError("boom")

    local.on(bad)
    local.on(lambda _event: order.append("good"))
    local.emit(SdkEvent(kind=SdkEventKind.READY))
    assert order == ["bad", "good"]

    order.clear()
    local.emit(SdkEvent(kind=SdkEventKind.READY))
    assert order == ["bad", "good"]  # a throwing listener is not removed


def test_base_exception_from_a_listener_propagates() -> None:
    class Boom(BaseException):
        pass

    def raises_base(_event) -> None:
        raise Boom()

    local = EventBus()
    local.on(raises_base)
    with pytest.raises(Boom):
        local.emit(SdkEvent(kind=SdkEventKind.READY))


def test_listener_unsubscribing_during_emit_is_safe() -> None:
    local = EventBus()
    calls: list = []

    def self_removing(_event) -> None:
        calls.append("self_removing")
        unsubscribe()

    unsubscribe = local.on(self_removing)
    local.on(lambda _event: calls.append("other"))
    local.emit(SdkEvent(kind=SdkEventKind.READY))
    assert calls == ["self_removing", "other"]
    assert local.listener_count == 1


def test_remove_all_and_counting() -> None:
    local = EventBus()
    local.on(lambda _e: None)
    local.once(lambda _e: None)
    assert local.listener_count == 2
    local.remove_all()
    assert local.listener_count == 0


def test_same_callable_registered_once() -> None:
    local = EventBus()

    def listener(_event) -> None:
        pass

    local.on(listener)
    local.on(listener)
    assert local.listener_count == 1


# --------------------------------------------------------------------------- lifecycle breadcrumbs
def test_initialize_and_loads_publish_breadcrumbs(fake_core, monkeypatch, tmp_path, gguf) -> None:
    monkeypatch.setenv("RUNANYWHERE_HOME", str(tmp_path / "home"))
    seen: list = []
    ra.events.on(seen.append)
    ra.initialize()
    try:
        ra.models.load(gguf)
        ra.models.unload_all(ModelCategory.LANGUAGE)
    finally:
        ra.reset()
    kinds = [event.kind for event in seen]
    assert SdkEventKind.READY in kinds
    assert SdkEventKind.MODEL_LOADED in kinds
    assert SdkEventKind.MODEL_UNLOADED in kinds
