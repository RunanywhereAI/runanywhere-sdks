from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
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
    __slots__ = ("prompt", "max_tokens", "temperature", "top_p", "top_k", "system_prompt", "emit_thoughts", "repetition_penalty", "stop_sequences", "streaming_enabled", "preferred_framework", "json_schema", "execution_target")
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    EMIT_THOUGHTS_FIELD_NUMBER: _ClassVar[int]
    REPETITION_PENALTY_FIELD_NUMBER: _ClassVar[int]
    STOP_SEQUENCES_FIELD_NUMBER: _ClassVar[int]
    STREAMING_ENABLED_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    EXECUTION_TARGET_FIELD_NUMBER: _ClassVar[int]
    prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    system_prompt: str
    emit_thoughts: bool
    repetition_penalty: float
    stop_sequences: _containers.RepeatedScalarFieldContainer[str]
    streaming_enabled: bool
    preferred_framework: str
    json_schema: str
    execution_target: str
    def __init__(self, prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., system_prompt: _Optional[str] = ..., emit_thoughts: _Optional[bool] = ..., repetition_penalty: _Optional[float] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., preferred_framework: _Optional[str] = ..., json_schema: _Optional[str] = ..., execution_target: _Optional[str] = ...) -> None: ...

class LLMStreamFinalResult(_message.Message):
    __slots__ = ("text", "thinking_content", "prompt_tokens", "completion_tokens", "total_tokens", "total_time_ms", "time_to_first_token_ms", "tokens_per_second", "finish_reason")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    THINKING_CONTENT_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TIME_TO_FIRST_TOKEN_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    FINISH_REASON_FIELD_NUMBER: _ClassVar[int]
    text: str
    thinking_content: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    total_time_ms: int
    time_to_first_token_ms: int
    tokens_per_second: float
    finish_reason: str
    def __init__(self, text: _Optional[str] = ..., thinking_content: _Optional[str] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ..., total_tokens: _Optional[int] = ..., total_time_ms: _Optional[int] = ..., time_to_first_token_ms: _Optional[int] = ..., tokens_per_second: _Optional[float] = ..., finish_reason: _Optional[str] = ...) -> None: ...

class LLMStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "token", "is_final", "kind", "token_id", "logprob", "finish_reason", "error_message", "result", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TOKEN_ID_FIELD_NUMBER: _ClassVar[int]
    LOGPROB_FIELD_NUMBER: _ClassVar[int]
    FINISH_REASON_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    token: str
    is_final: bool
    kind: LLMTokenKind
    token_id: int
    logprob: float
    finish_reason: str
    error_message: str
    result: LLMStreamFinalResult
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., token: _Optional[str] = ..., is_final: _Optional[bool] = ..., kind: _Optional[_Union[LLMTokenKind, str]] = ..., token_id: _Optional[int] = ..., logprob: _Optional[float] = ..., finish_reason: _Optional[str] = ..., error_message: _Optional[str] = ..., result: _Optional[_Union[LLMStreamFinalResult, _Mapping]] = ..., error_code: _Optional[int] = ...) -> None: ...
