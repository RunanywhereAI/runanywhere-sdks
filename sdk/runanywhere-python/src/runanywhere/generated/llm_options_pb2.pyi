import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class LLMGenerationOptions(_message.Message):
    __slots__ = ("max_tokens", "temperature", "top_p", "top_k", "repetition_penalty", "stop_sequences", "streaming_enabled", "preferred_framework", "system_prompt", "json_schema")
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    REPETITION_PENALTY_FIELD_NUMBER: _ClassVar[int]
    STOP_SEQUENCES_FIELD_NUMBER: _ClassVar[int]
    STREAMING_ENABLED_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    repetition_penalty: float
    stop_sequences: _containers.RepeatedScalarFieldContainer[str]
    streaming_enabled: bool
    preferred_framework: _model_types_pb2.InferenceFramework
    system_prompt: str
    json_schema: str
    def __init__(self, max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., repetition_penalty: _Optional[float] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ..., system_prompt: _Optional[str] = ..., json_schema: _Optional[str] = ...) -> None: ...

class LLMGenerationResult(_message.Message):
    __slots__ = ("text", "thinking_content", "input_tokens", "tokens_generated", "model_used", "generation_time_ms", "ttft_ms", "tokens_per_second", "framework", "finish_reason", "thinking_tokens", "response_tokens", "json_output")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    THINKING_CONTENT_FIELD_NUMBER: _ClassVar[int]
    INPUT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_GENERATED_FIELD_NUMBER: _ClassVar[int]
    MODEL_USED_FIELD_NUMBER: _ClassVar[int]
    GENERATION_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TTFT_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    FINISH_REASON_FIELD_NUMBER: _ClassVar[int]
    THINKING_TOKENS_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_TOKENS_FIELD_NUMBER: _ClassVar[int]
    JSON_OUTPUT_FIELD_NUMBER: _ClassVar[int]
    text: str
    thinking_content: str
    input_tokens: int
    tokens_generated: int
    model_used: str
    generation_time_ms: float
    ttft_ms: float
    tokens_per_second: float
    framework: str
    finish_reason: str
    thinking_tokens: int
    response_tokens: int
    json_output: str
    def __init__(self, text: _Optional[str] = ..., thinking_content: _Optional[str] = ..., input_tokens: _Optional[int] = ..., tokens_generated: _Optional[int] = ..., model_used: _Optional[str] = ..., generation_time_ms: _Optional[float] = ..., ttft_ms: _Optional[float] = ..., tokens_per_second: _Optional[float] = ..., framework: _Optional[str] = ..., finish_reason: _Optional[str] = ..., thinking_tokens: _Optional[int] = ..., response_tokens: _Optional[int] = ..., json_output: _Optional[str] = ...) -> None: ...
