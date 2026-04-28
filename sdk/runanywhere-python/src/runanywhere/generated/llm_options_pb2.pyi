import model_types_pb2 as _model_types_pb2
import structured_output_pb2 as _structured_output_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ExecutionTarget(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    EXECUTION_TARGET_UNSPECIFIED: _ClassVar[ExecutionTarget]
    EXECUTION_TARGET_ON_DEVICE: _ClassVar[ExecutionTarget]
    EXECUTION_TARGET_CLOUD: _ClassVar[ExecutionTarget]
    EXECUTION_TARGET_AUTO: _ClassVar[ExecutionTarget]
EXECUTION_TARGET_UNSPECIFIED: ExecutionTarget
EXECUTION_TARGET_ON_DEVICE: ExecutionTarget
EXECUTION_TARGET_CLOUD: ExecutionTarget
EXECUTION_TARGET_AUTO: ExecutionTarget

class LLMGenerationOptions(_message.Message):
    __slots__ = ("max_tokens", "temperature", "top_p", "top_k", "repetition_penalty", "stop_sequences", "streaming_enabled", "preferred_framework", "system_prompt", "json_schema", "thinking_pattern", "execution_target", "structured_output")
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
    THINKING_PATTERN_FIELD_NUMBER: _ClassVar[int]
    EXECUTION_TARGET_FIELD_NUMBER: _ClassVar[int]
    STRUCTURED_OUTPUT_FIELD_NUMBER: _ClassVar[int]
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
    thinking_pattern: ThinkingTagPattern
    execution_target: ExecutionTarget
    structured_output: _structured_output_pb2.StructuredOutputOptions
    def __init__(self, max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., repetition_penalty: _Optional[float] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ..., system_prompt: _Optional[str] = ..., json_schema: _Optional[str] = ..., thinking_pattern: _Optional[_Union[ThinkingTagPattern, _Mapping]] = ..., execution_target: _Optional[_Union[ExecutionTarget, str]] = ..., structured_output: _Optional[_Union[_structured_output_pb2.StructuredOutputOptions, _Mapping]] = ...) -> None: ...

class LLMGenerationResult(_message.Message):
    __slots__ = ("text", "thinking_content", "input_tokens", "tokens_generated", "model_used", "generation_time_ms", "ttft_ms", "tokens_per_second", "framework", "finish_reason", "thinking_tokens", "response_tokens", "json_output", "performance", "executed_on")
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
    PERFORMANCE_FIELD_NUMBER: _ClassVar[int]
    EXECUTED_ON_FIELD_NUMBER: _ClassVar[int]
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
    performance: PerformanceMetrics
    executed_on: ExecutionTarget
    def __init__(self, text: _Optional[str] = ..., thinking_content: _Optional[str] = ..., input_tokens: _Optional[int] = ..., tokens_generated: _Optional[int] = ..., model_used: _Optional[str] = ..., generation_time_ms: _Optional[float] = ..., ttft_ms: _Optional[float] = ..., tokens_per_second: _Optional[float] = ..., framework: _Optional[str] = ..., finish_reason: _Optional[str] = ..., thinking_tokens: _Optional[int] = ..., response_tokens: _Optional[int] = ..., json_output: _Optional[str] = ..., performance: _Optional[_Union[PerformanceMetrics, _Mapping]] = ..., executed_on: _Optional[_Union[ExecutionTarget, str]] = ...) -> None: ...

class LLMConfiguration(_message.Message):
    __slots__ = ("context_length", "temperature", "max_tokens", "system_prompt", "streaming")
    CONTEXT_LENGTH_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    STREAMING_FIELD_NUMBER: _ClassVar[int]
    context_length: int
    temperature: float
    max_tokens: int
    system_prompt: str
    streaming: bool
    def __init__(self, context_length: _Optional[int] = ..., temperature: _Optional[float] = ..., max_tokens: _Optional[int] = ..., system_prompt: _Optional[str] = ..., streaming: _Optional[bool] = ...) -> None: ...

class GenerationHints(_message.Message):
    __slots__ = ("temperature", "max_tokens", "system_role")
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_ROLE_FIELD_NUMBER: _ClassVar[int]
    temperature: float
    max_tokens: int
    system_role: str
    def __init__(self, temperature: _Optional[float] = ..., max_tokens: _Optional[int] = ..., system_role: _Optional[str] = ...) -> None: ...

class ThinkingTagPattern(_message.Message):
    __slots__ = ("opening_tag", "closing_tag")
    OPENING_TAG_FIELD_NUMBER: _ClassVar[int]
    CLOSING_TAG_FIELD_NUMBER: _ClassVar[int]
    opening_tag: str
    closing_tag: str
    def __init__(self, opening_tag: _Optional[str] = ..., closing_tag: _Optional[str] = ...) -> None: ...

class StreamToken(_message.Message):
    __slots__ = ("text", "timestamp_ms", "index")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    INDEX_FIELD_NUMBER: _ClassVar[int]
    text: str
    timestamp_ms: int
    index: int
    def __init__(self, text: _Optional[str] = ..., timestamp_ms: _Optional[int] = ..., index: _Optional[int] = ...) -> None: ...

class PerformanceMetrics(_message.Message):
    __slots__ = ("latency_ms", "memory_bytes", "throughput_tokens_per_sec", "prompt_tokens", "completion_tokens")
    LATENCY_MS_FIELD_NUMBER: _ClassVar[int]
    MEMORY_BYTES_FIELD_NUMBER: _ClassVar[int]
    THROUGHPUT_TOKENS_PER_SEC_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_FIELD_NUMBER: _ClassVar[int]
    latency_ms: int
    memory_bytes: int
    throughput_tokens_per_sec: float
    prompt_tokens: int
    completion_tokens: int
    def __init__(self, latency_ms: _Optional[int] = ..., memory_bytes: _Optional[int] = ..., throughput_tokens_per_sec: _Optional[float] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ...) -> None: ...
