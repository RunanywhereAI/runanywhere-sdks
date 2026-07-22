"""Pydantic request models for the OpenAI-compatible server (pure — needs the [server] extra).

Only the fields the server acts on are modelled; unknown OpenAI fields (``n``, ``seed``,
``presence_penalty``, ``stream_options``, …) are ignored rather than rejected, so real OpenAI
clients work unchanged.
"""
from __future__ import annotations

from typing import Any, Optional, Union

from pydantic import BaseModel, ConfigDict

# OpenAI chat `content` is either a plain string or a list of typed parts (text + image_url
# for vision). We keep it permissive and interpret the parts in the route.
Content = Union[str, list[dict[str, Any]], None]


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="ignore")

    role: str
    content: Content = None
    name: Optional[str] = None
    tool_call_id: Optional[str] = None
    tool_calls: Optional[list[dict[str, Any]]] = None


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: Optional[str] = None
    messages: list[ChatMessage]
    stream: bool = False
    max_tokens: Optional[int] = None
    max_completion_tokens: Optional[int] = None
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    top_k: Optional[int] = None
    stop: Optional[Union[str, list[str]]] = None
    response_format: Optional[dict[str, Any]] = None
    tools: Optional[list[dict[str, Any]]] = None
    tool_choice: Optional[Union[str, dict[str, Any]]] = None


class CompletionRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: Optional[str] = None
    prompt: Union[str, list[str]]
    stream: bool = False
    max_tokens: Optional[int] = None
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    top_k: Optional[int] = None
    stop: Optional[Union[str, list[str]]] = None


class EmbeddingsRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: Optional[str] = None
    input: Union[str, list[str]]
    encoding_format: str = "float"


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: Optional[str] = None
    input: str
    voice: Optional[str] = None
    response_format: str = "wav"
