from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class LLMTokenKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    LLM_TOKEN_KIND_UNSPECIFIED: _ClassVar[LLMTokenKind]
    LLM_TOKEN_KIND_ANSWER: _ClassVar[LLMTokenKind]
    LLM_TOKEN_KIND_THOUGHT: _ClassVar[LLMTokenKind]
    LLM_TOKEN_KIND_TOOL_CALL: _ClassVar[LLMTokenKind]
LLM_TOKEN_KIND_UNSPECIFIED: LLMTokenKind
LLM_TOKEN_KIND_ANSWER: LLMTokenKind
LLM_TOKEN_KIND_THOUGHT: LLMTokenKind
LLM_TOKEN_KIND_TOOL_CALL: LLMTokenKind

class LLMGenerateRequest(_message.Message):
    __slots__ = ("prompt", "max_tokens", "temperature", "top_p", "top_k", "system_prompt", "emit_thoughts")
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    EMIT_THOUGHTS_FIELD_NUMBER: _ClassVar[int]
    prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    system_prompt: str
    emit_thoughts: bool
    def __init__(self, prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., system_prompt: _Optional[str] = ..., emit_thoughts: _Optional[bool] = ...) -> None: ...

class LLMToken(_message.Message):
    __slots__ = ("text", "is_final", "kind", "logprob", "emit_us")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    LOGPROB_FIELD_NUMBER: _ClassVar[int]
    EMIT_US_FIELD_NUMBER: _ClassVar[int]
    text: str
    is_final: bool
    kind: LLMTokenKind
    logprob: float
    emit_us: int
    def __init__(self, text: _Optional[str] = ..., is_final: _Optional[bool] = ..., kind: _Optional[_Union[LLMTokenKind, str]] = ..., logprob: _Optional[float] = ..., emit_us: _Optional[int] = ...) -> None: ...
