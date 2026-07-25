"""Tests for structured-output / tool-calling helpers."""
from __future__ import annotations

import pytest

from runanywhere.errors import ErrorCode, SDKException
from runanywhere.structured import (
    ToolCall,
    ToolRun,
    ToolSpec,
    object_grammar,
    parse_structured,
    tool_call_prompt,
    tool_call_schema,
)


def _weather_tool() -> ToolSpec:
    return ToolSpec(
        name="get_weather",
        description="Look up the weather",
        parameters={
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
    )


def _time_tool() -> ToolSpec:
    return ToolSpec(
        name="get_time",
        parameters={"type": "object", "properties": {}},
    )


# --- tool_call_schema shape ------------------------------------------------

def test_tool_call_schema_shape():
    tools = [_weather_tool(), _time_tool()]
    schema = tool_call_schema(tools)

    assert set(schema.keys()) == {"anyOf"}
    branches = schema["anyOf"]
    assert len(branches) == 2

    first = branches[0]
    assert first["type"] == "object"
    assert first["required"] == ["name", "arguments"]
    # name is pinned to a const of the tool name
    assert first["properties"]["name"] == {"const": "get_weather"}
    # arguments is the tool's own parameter schema (same object, by identity)
    assert first["properties"]["arguments"] is tools[0].parameters

    second = branches[1]
    assert second["properties"]["name"] == {"const": "get_time"}
    assert second["properties"]["arguments"] is tools[1].parameters


def test_tool_call_schema_empty():
    assert tool_call_schema([]) == {"anyOf": []}


# --- tool_call_prompt content ---------------------------------------------

def test_tool_call_prompt_content():
    tools = [_weather_tool(), _time_tool()]
    out = tool_call_prompt("What is the weather?", tools)

    assert out.startswith("What is the weather?\n\nAvailable tools:\n")
    # tool with a description gets "- name: description"
    assert "- get_weather: Look up the weather" in out
    # tool without a description gets just "- name"
    assert "- get_time\n" in out
    assert "- get_time:" not in out
    assert out.endswith("Reply with a single JSON tool call.")


def test_tool_call_prompt_single_no_description():
    out = tool_call_prompt("Hi", [_time_tool()])
    assert out == (
        "Hi\n\nAvailable tools:\n- get_time\n\nReply with a single JSON tool call."
    )


# --- parse_structured happy path ------------------------------------------

def test_parse_structured_happy():
    assert parse_structured('{"a": 1, "b": [2, 3]}') == {"a": 1, "b": [2, 3]}


def test_parse_structured_trims_whitespace():
    assert parse_structured('   {"name": "x"}  \n') == {"name": "x"}


def test_parse_structured_non_object_json():
    # Any valid JSON value is returned, not just objects.
    assert parse_structured("[1, 2, 3]") == [1, 2, 3]
    assert parse_structured("42") == 42


# --- parse_structured error path ------------------------------------------

def test_parse_structured_bad_json_raises_sdk_exception():
    with pytest.raises(SDKException) as excinfo:
        parse_structured("not json at all")
    err = excinfo.value
    assert err.code == ErrorCode.GENERATION_FAILED
    # the offending text is surfaced in the message
    assert "not json at all" in str(err)


def test_parse_structured_empty_raises():
    with pytest.raises(SDKException):
        parse_structured("")


# --- object_grammar delegation --------------------------------------------

def test_object_grammar_delegates():
    schema = {"type": "object", "properties": {"x": {"type": "string"}}, "required": ["x"]}
    grammar = object_grammar(schema)
    assert isinstance(grammar, str)
    assert grammar  # non-empty grammar text


# --- dataclass smoke ------------------------------------------------------

def test_tool_dataclasses():
    call = ToolCall(name="get_time", arguments={})
    assert call.name == "get_time"
    assert call.arguments == {}

    run = ToolRun(name="get_time", arguments={}, result=123)
    assert run.result == 123
    # result defaults to None
    assert ToolRun(name="x", arguments={}).result is None

    spec = ToolSpec(name="x", parameters={"type": "object"})
    assert spec.description is None
    assert spec.execute is None
