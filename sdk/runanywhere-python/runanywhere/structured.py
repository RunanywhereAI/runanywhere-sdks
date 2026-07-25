"""Shared building blocks for schema-constrained generation and tool calling."""
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Callable, Optional

from .errors import SDKException
from .grammar import json_schema_to_grammar

__all__ = [
    "object_grammar",
    "parse_structured",
    "ToolSpec",
    "ToolCall",
    "ToolRun",
    "tool_call_schema",
    "tool_call_prompt",
]


@dataclass
class ToolSpec:
    """A tool the model may be asked to call."""

    name: str
    #: JSON-schema (object) describing the call arguments.
    parameters: dict
    description: Optional[str] = None
    #: Optional executor — when present, generate_with_tools runs it on the chosen call.
    execute: Optional[Callable[[dict], Any]] = None


@dataclass
class ToolCall:
    """A parsed tool call chosen by the model."""

    name: str
    arguments: dict


@dataclass
class ToolRun:
    """The outcome of generate_with_tools: the chosen call plus its executor result."""

    name: str
    arguments: dict
    #: Present when the chosen tool had an ``execute`` function.
    result: Any = None


def object_grammar(schema: dict) -> str:
    """GBNF grammar constraining output to JSON matching ``schema``."""
    return json_schema_to_grammar(schema)


def tool_call_schema(tools: list[ToolSpec]) -> dict:
    """Schema whose value is one well-formed ``{ name, arguments }`` call for a tool."""
    return {
        "anyOf": [
            {
                "type": "object",
                "properties": {"name": {"const": t.name}, "arguments": t.parameters},
                "required": ["name", "arguments"],
            }
            for t in tools
        ]
    }


def tool_call_prompt(prompt: str, tools: list[ToolSpec]) -> str:
    """Prompt that lists the tools so the model can choose one."""
    doc = "\n".join(
        f"- {t.name}{': ' + t.description if t.description else ''}" for t in tools
    )
    return f"{prompt}\n\nAvailable tools:\n{doc}\n\nReply with a single JSON tool call."


def parse_structured(text: str) -> Any:
    """Parse constrained output as JSON, with a clear error if it somehow isn't."""
    trimmed = text.strip()
    try:
        return json.loads(trimmed)
    except (ValueError, TypeError) as exc:
        raise SDKException.generation_failed(
            f"model did not return valid JSON: {trimmed}", cause=exc
        )
