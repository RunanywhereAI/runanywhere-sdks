"""Pydantic request models for the OpenAI-compatible server (pure — needs the [server] extra).

Only the fields the server acts on are modelled; unknown OpenAI fields (``n``, ``seed``,
``presence_penalty``, ``stream_options``, …) are ignored rather than rejected, so real OpenAI
clients work unchanged. Out-of-range sampling params are rejected (a clean 400) rather than
forwarded to the backend where e.g. ``max_tokens=0`` is undefined.

Note: these use ``Optional``/``Union`` (not the SDK's usual ``X | None``) on purpose — pydantic and
FastAPI evaluate these annotations at runtime, and PEP-604 string-form unions are not reliably
evaluable on the declared floor (Python 3.9). ``Optional`` is safe on every supported version.
"""
from __future__ import annotations

from typing import Any, Optional, Union

from pydantic import BaseModel, ConfigDict, Field


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="ignore")

    role: str
    # OpenAI content is a string or a list of typed parts (text + image_url for vision).
    content: Union[str, list[dict[str, Any]], None] = None
    name: Optional[str] = None
    tool_call_id: Optional[str] = None
    tool_calls: Optional[list[dict[str, Any]]] = None


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: Optional[str] = None
    messages: list[ChatMessage]
    stream: bool = False
    max_tokens: Optional[int] = Field(default=None, ge=1)
    max_completion_tokens: Optional[int] = Field(default=None, ge=1)
    temperature: Optional[float] = Field(default=None, ge=0)
    top_p: Optional[float] = Field(default=None, ge=0, le=1)
    top_k: Optional[int] = Field(default=None, ge=1)
    stop: Union[str, list[str], None] = None
    response_format: Optional[dict[str, Any]] = None
    tools: Optional[list[dict[str, Any]]] = None
    tool_choice: Union[str, dict[str, Any], None] = None


class CompletionRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: Optional[str] = None
    prompt: Union[str, list[str]]
    stream: bool = False
    max_tokens: Optional[int] = Field(default=None, ge=1)
    temperature: Optional[float] = Field(default=None, ge=0)
    top_p: Optional[float] = Field(default=None, ge=0, le=1)
    top_k: Optional[int] = Field(default=None, ge=1)
    stop: Union[str, list[str], None] = None


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
