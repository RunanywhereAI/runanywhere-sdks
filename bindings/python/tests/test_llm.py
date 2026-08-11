"""The ``llm`` namespace: generation, streaming, messages, structured output and tools."""

from __future__ import annotations

import asyncio
import os
import sys
import threading

_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

import runanywhere as ra  # noqa: E402
from runanywhere import (  # noqa: E402
    ChatMessage,
    ErrorCode,
    FinishReason,
    GenerationEventKind,
    LlmOptions,
    ReasoningMode,
    ReasoningOptions,
    Role,
    SDKException,
    TokenKind,
    ToolChoice,
    ToolChoiceMode,
    ToolDefinition,
)


def _opts(gguf: str, **kwargs) -> LlmOptions:
    return LlmOptions(model=gguf, **kwargs)


# --------------------------------------------------------------------------- one-shot
def test_generate_returns_text_and_metrics(sdk, gguf) -> None:
    result = ra.llm.generate("Capital of France?", _opts(gguf))
    assert result.text == "Paris"
    # FakeCore streams tokens only; metrics stay at 0 until terminal commons usage is plumbed.
    assert result.output_tokens == 0
    assert result.finish_reason == FinishReason.UNSPECIFIED
    assert result.model == gguf
    assert result.request_id
    assert result.tokens_per_second == 0.0
    assert result.time_to_first_token_ms == 0.0


def test_generate_auto_loads_the_named_model(sdk, gguf) -> None:
    ra.llm.generate("hi", _opts(gguf))
    assert sdk.count("load_model") == 1
    ra.llm.generate("again", _opts(gguf))
    assert sdk.count("load_model") == 1  # already resident


def test_generate_without_a_model_is_a_clear_error(sdk) -> None:
    with pytest.raises(SDKException) as error:
        ra.llm.generate("hi")
    assert error.value.code == ErrorCode.INVALID_STATE
    assert "options.model" in str(error.value)


def test_empty_prompt_is_rejected(sdk, gguf) -> None:
    with pytest.raises(SDKException) as error:
        ra.llm.generate("", _opts(gguf))
    assert error.value.code == ErrorCode.INVALID_INPUT


# --------------------------------------------------------------------------- options mapping
def test_options_reach_the_bridge(sdk, gguf) -> None:
    ra.llm.generate(
        "hi",
        _opts(
            gguf,
            max_output_tokens=7,
            temperature=0.0,
            top_p=0.5,
            top_k=3,
            system_prompt="be terse",
            reasoning=ReasoningOptions(mode=ReasoningMode.OFF),
        ),
    )
    assert sdk.last_kwargs == {
        "max_tokens": 7,
        "temperature": 0.0,
        "top_p": 0.5,
        "top_k": 3,
        "system_prompt": "be terse",
        "disable_thinking": True,
    }


@pytest.mark.parametrize(
    "field, value",
    [("seed", 7), ("min_p", 0.1), ("frequency_penalty", 0.5), ("presence_penalty", 0.5),
     ("repetition_penalty", 1.1)],
)
def test_unbound_sampling_fields_raise_rather_than_lie(sdk, gguf, field, value) -> None:
    with pytest.raises(SDKException) as error:
        ra.llm.generate("hi", _opts(gguf, **{field: value}))
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED
    assert field in str(error.value)


def test_stop_sequences_truncate_host_side(sdk, gguf) -> None:
    sdk.tokens = ["Hello", " world", "STOP", " ignored"]
    result = ra.llm.generate("hi", _opts(gguf, stop_sequences=["STOP"]))
    assert result.text == "Hello world"


def test_commons_finish_reason_is_forwarded(sdk, gguf) -> None:
    sdk.tokens = ["a", "b", "c"]
    sdk.finish_reason = int(FinishReason.LENGTH)
    result = ra.llm.generate("hi", _opts(gguf, max_output_tokens=3))
    assert result.finish_reason == FinishReason.LENGTH


# --------------------------------------------------------------------------- streaming
def test_generate_stream_follows_the_event_grammar(sdk, gguf) -> None:
    events = list(ra.llm.generate_stream("hi", _opts(gguf)))
    assert events[0].kind == GenerationEventKind.STARTED
    assert events[-1].kind == GenerationEventKind.COMPLETED
    assert "".join(e.text for e in events if e.is_token) == "Paris"
    assert events[-1].result is not None and events[-1].result.text == "Paris"
    assert all(e.request_id == events[0].request_id for e in events)


def test_thoughts_are_only_streamed_when_requested(sdk, gguf) -> None:
    sdk.stream_deltas = [("why", True), ("Paris", False)]
    quiet = list(ra.llm.generate_stream("hi", _opts(gguf)))
    assert all(e.token_kind == TokenKind.TEXT for e in quiet if e.is_token)
    assert quiet[-1].result.text == "Paris"
    assert quiet[-1].result.thinking_text is None

    loud = list(
        ra.llm.generate_stream(
            "hi", _opts(gguf, reasoning=ReasoningOptions(include_in_output=True))
        )
    )
    assert "".join(e.text for e in loud if e.is_thought) == "why"
    assert loud[-1].result.thinking_text == "why"


def test_breaking_a_stream_cancels_and_releases(sdk, gguf) -> None:
    sdk.tokens = [str(i) for i in range(1000)]
    seen = []
    stream = ra.llm.generate_stream("hi", _opts(gguf))
    for event in stream:
        if event.is_token:
            seen.append(event.text)
        if len(seen) == 3:
            break
    stream.close()
    assert seen == ["0", "1", "2"]
    assert sdk.stopped is True
    assert not any(t.name == "ra-stream" and t.is_alive() for t in threading.enumerate())
    # The model is free again.
    assert ra.llm.generate("hi", _opts(gguf)).text


def test_concurrent_generation_on_one_model_raises(sdk, gguf) -> None:
    sdk.tokens = [str(i) for i in range(100)]
    stream = ra.llm.generate_stream("a", _opts(gguf))
    next(stream)
    next(stream)  # first token — the guard is held for the stream's lifetime
    try:
        with pytest.raises(SDKException) as error:
            list(ra.llm.generate_stream("b", _opts(gguf)))
        assert error.value.code == ErrorCode.INVALID_STATE
    finally:
        stream.close()


# --------------------------------------------------------------------------- messages
def test_single_user_message_passes_through_verbatim(sdk, gguf) -> None:
    ra.llm.generate([ChatMessage(role=Role.USER, content="Capital of France?")], _opts(gguf))
    _handle, prompt = sdk.args_of("generate_typed")
    assert prompt == "Capital of France?"


def test_multi_turn_messages_become_a_transcript(sdk, gguf) -> None:
    ra.llm.generate(
        [
            ChatMessage(role=Role.SYSTEM, content="be terse"),
            ChatMessage(role=Role.USER, content="hi"),
            ChatMessage(role=Role.ASSISTANT, content="hello"),
            ChatMessage(role=Role.USER, content="and now?"),
        ],
        _opts(gguf),
    )
    _handle, prompt = sdk.args_of("generate_typed")
    assert prompt == "User: hi\nAssistant: hello\nUser: and now?\nAssistant:"
    assert sdk.last_kwargs["system_prompt"] == "be terse"


def test_messages_must_contain_a_turn(sdk, gguf) -> None:
    with pytest.raises(SDKException):
        ra.llm.generate([ChatMessage(role=Role.SYSTEM, content="only system")], _opts(gguf))


# --------------------------------------------------------------------------- structured output
def test_generate_structured_constrains_and_parses(sdk, gguf) -> None:
    sdk.tokens = ['{"city"', ': "Paris"}']
    schema = {"type": "object", "properties": {"city": {"type": "string"}}}
    result = ra.llm.generate_structured("Where?", schema, _opts(gguf))
    assert result.valid is True
    assert result.value == {"city": "Paris"}
    assert "structured_schema" in sdk.last_kwargs
    assert '"type":"object"' in sdk.last_kwargs["structured_schema"]


def test_generate_structured_reports_invalid_output(sdk, gguf) -> None:
    sdk.tokens = ["not json"]
    result = ra.llm.generate_structured("Where?", {"type": "object"}, _opts(gguf))
    assert result.valid is False and result.value is None and result.raw == "not json"


def test_structured_output_relaxation_is_refused(sdk, gguf) -> None:
    from runanywhere import StructuredOutput

    options = _opts(gguf, structured_output=StructuredOutput(schema={"type": "object"}, strict=False))
    with pytest.raises(SDKException) as error:
        ra.llm.generate("hi", options)
    assert error.value.code == ErrorCode.NOT_IMPLEMENTED


# --------------------------------------------------------------------------- tools
def _weather_tool() -> ToolDefinition:
    return ToolDefinition(
        name="get_weather",
        parameters={"type": "object", "properties": {"city": {"type": "string"}}},
        description="Look up the weather",
    )


def test_registered_tool_is_executed_and_the_loop_continues(sdk, gguf) -> None:
    calls = []

    def executor(arguments):
        calls.append(arguments)
        return {"temp_c": 21}

    ra.llm.tools.register(_weather_tool(), executor)
    try:
        # First reply is a tool call; after the observation the model answers.
        replies = [['{"name": "get_weather", "arguments": {"city": "Paris"}}'], ["21C"], ["21C"]]

        def next_deltas(_handle, prompt, on_delta, **kwargs):
            sdk.calls.append(("generate_typed", (_handle, prompt)))
            sdk.last_kwargs = kwargs
            for token in replies.pop(0) if replies else ["done"]:
                on_delta(token, False)

        sdk.generate_typed = next_deltas  # type: ignore[method-assign]
        result = ra.llm.generate("Weather in Paris?", _opts(gguf))
        assert calls == [{"city": "Paris"}]
        assert result.tool_calls and result.tool_calls[0].result == {"temp_c": 21}
        assert result.text == "21C"
    finally:
        ra.llm.tools.unregister("get_weather")


def test_tool_without_an_executor_finishes_with_tool_calls(sdk, gguf) -> None:
    sdk.tokens = ['{"name": "get_weather", "arguments": {"city": "Paris"}}']
    options = _opts(gguf, tools=[_weather_tool()])
    result = ra.llm.generate("Weather in Paris?", options)
    assert result.finish_reason == FinishReason.TOOL_CALLS
    assert result.tool_calls[0].name == "get_weather"
    assert result.tool_calls[0].arguments == {"city": "Paris"}


def test_tool_choice_none_skips_the_tool_path(sdk, gguf) -> None:
    options = _opts(gguf, tools=[_weather_tool()], tool_choice=ToolChoice(ToolChoiceMode.NONE))
    assert ra.llm.generate("hi", options).text == "Paris"


def test_tool_choice_forced_must_name_a_known_tool(sdk, gguf) -> None:
    options = _opts(gguf, tools=[_weather_tool()], tool_choice=ToolChoice.forced("nope"))
    with pytest.raises(SDKException) as error:
        ra.llm.generate("hi", options)
    assert error.value.code == ErrorCode.INVALID_INPUT


def test_tools_registry_lists_and_unregisters(sdk) -> None:
    ra.llm.tools.register(_weather_tool(), lambda _a: {})
    assert [t.name for t in ra.llm.tools.list()] == ["get_weather"]
    ra.llm.tools.unregister("get_weather")
    assert ra.llm.tools.list() == []
    ra.llm.tools.unregister("get_weather")  # unregistering twice is a no-op


# --------------------------------------------------------------------------- async twins
def test_agenerate_matches_the_sync_form(sdk, gguf) -> None:
    result = asyncio.run(ra.llm.agenerate("hi", _opts(gguf)))
    assert result.text == "Paris"


def test_agenerate_stream_events(sdk, gguf) -> None:
    async def run():
        return [event async for event in ra.llm.agenerate_stream("hi", _opts(gguf))]

    events = asyncio.run(run())
    assert events[0].kind == GenerationEventKind.STARTED
    assert events[-1].result.text == "Paris"


def test_async_early_stop_joins_the_worker_and_frees_the_guard(sdk, gguf) -> None:
    sdk.tokens = [str(i) for i in range(1000)]
    observed = {}

    async def run():
        seen = []
        stream = ra.llm.agenerate_stream("hi", _opts(gguf))
        async for event in stream:
            if event.is_token:
                seen.append(event.text)
            if len(seen) == 3:
                break
        await stream.aclose()
        observed["seen"] = seen
        observed["stopped"] = sdk.stopped
        observed["worker_alive"] = any(
            t.name == "ra-stream" and t.is_alive() for t in threading.enumerate()
        )

    asyncio.run(run())
    assert observed["seen"] == ["0", "1", "2"]
    assert observed["stopped"] is True
    assert observed["worker_alive"] is False


def test_agenerate_structured(sdk, gguf) -> None:
    sdk.tokens = ['{"ok": true}']
    result = asyncio.run(ra.llm.agenerate_structured("x", {"type": "object"}, _opts(gguf)))
    assert result.value == {"ok": True}
