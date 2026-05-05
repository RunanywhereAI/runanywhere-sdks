import model_types_pb2 as _model_types_pb2
import structured_output_pb2 as _structured_output_pb2
import tool_calling_pb2 as _tool_calling_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class LLMGenerationState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    LLM_GENERATION_STATE_UNSPECIFIED: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_QUEUED: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_PREFILLING: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_DECODING: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_TOOL_CALLING: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_COMPLETED: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_CANCELLED: _ClassVar[LLMGenerationState]
    LLM_GENERATION_STATE_FAILED: _ClassVar[LLMGenerationState]

class ExecutionTarget(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    EXECUTION_TARGET_UNSPECIFIED: _ClassVar[ExecutionTarget]
    EXECUTION_TARGET_ON_DEVICE: _ClassVar[ExecutionTarget]
    EXECUTION_TARGET_CLOUD: _ClassVar[ExecutionTarget]
    EXECUTION_TARGET_AUTO: _ClassVar[ExecutionTarget]
LLM_GENERATION_STATE_UNSPECIFIED: LLMGenerationState
LLM_GENERATION_STATE_QUEUED: LLMGenerationState
LLM_GENERATION_STATE_PREFILLING: LLMGenerationState
LLM_GENERATION_STATE_DECODING: LLMGenerationState
LLM_GENERATION_STATE_TOOL_CALLING: LLMGenerationState
LLM_GENERATION_STATE_COMPLETED: LLMGenerationState
LLM_GENERATION_STATE_CANCELLED: LLMGenerationState
LLM_GENERATION_STATE_FAILED: LLMGenerationState
EXECUTION_TARGET_UNSPECIFIED: ExecutionTarget
EXECUTION_TARGET_ON_DEVICE: ExecutionTarget
EXECUTION_TARGET_CLOUD: ExecutionTarget
EXECUTION_TARGET_AUTO: ExecutionTarget

class LLMGenerationOptions(_message.Message):
    __slots__ = ("max_tokens", "temperature", "top_p", "top_k", "repetition_penalty", "stop_sequences", "streaming_enabled", "preferred_framework", "system_prompt", "json_schema", "thinking_pattern", "execution_target", "structured_output", "enable_real_time_tracking", "seed", "frequency_penalty", "presence_penalty", "repeat_last_n", "min_p", "grammar", "response_format", "echo_prompt", "n_threads", "tool_calling")
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
    ENABLE_REAL_TIME_TRACKING_FIELD_NUMBER: _ClassVar[int]
    SEED_FIELD_NUMBER: _ClassVar[int]
    FREQUENCY_PENALTY_FIELD_NUMBER: _ClassVar[int]
    PRESENCE_PENALTY_FIELD_NUMBER: _ClassVar[int]
    REPEAT_LAST_N_FIELD_NUMBER: _ClassVar[int]
    MIN_P_FIELD_NUMBER: _ClassVar[int]
    GRAMMAR_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_FORMAT_FIELD_NUMBER: _ClassVar[int]
    ECHO_PROMPT_FIELD_NUMBER: _ClassVar[int]
    N_THREADS_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLING_FIELD_NUMBER: _ClassVar[int]
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
    enable_real_time_tracking: bool
    seed: int
    frequency_penalty: float
    presence_penalty: float
    repeat_last_n: int
    min_p: float
    grammar: str
    response_format: str
    echo_prompt: bool
    n_threads: int
    tool_calling: _tool_calling_pb2.ToolCallingOptions
    def __init__(self, max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., repetition_penalty: _Optional[float] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ..., system_prompt: _Optional[str] = ..., json_schema: _Optional[str] = ..., thinking_pattern: _Optional[_Union[ThinkingTagPattern, _Mapping]] = ..., execution_target: _Optional[_Union[ExecutionTarget, str]] = ..., structured_output: _Optional[_Union[_structured_output_pb2.StructuredOutputOptions, _Mapping]] = ..., enable_real_time_tracking: _Optional[bool] = ..., seed: _Optional[int] = ..., frequency_penalty: _Optional[float] = ..., presence_penalty: _Optional[float] = ..., repeat_last_n: _Optional[int] = ..., min_p: _Optional[float] = ..., grammar: _Optional[str] = ..., response_format: _Optional[str] = ..., echo_prompt: _Optional[bool] = ..., n_threads: _Optional[int] = ..., tool_calling: _Optional[_Union[_tool_calling_pb2.ToolCallingOptions, _Mapping]] = ...) -> None: ...

class LLMGenerationResult(_message.Message):
    __slots__ = ("text", "thinking_content", "input_tokens", "tokens_generated", "model_used", "generation_time_ms", "ttft_ms", "tokens_per_second", "framework", "finish_reason", "thinking_tokens", "response_tokens", "json_output", "performance", "executed_on", "structured_output_validation", "total_tokens", "error_message", "error_code", "cached_prompt_tokens", "prompt_eval_time_ms", "decode_time_ms", "tool_calls", "tool_results")
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
    STRUCTURED_OUTPUT_VALIDATION_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    CACHED_PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    PROMPT_EVAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    DECODE_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULTS_FIELD_NUMBER: _ClassVar[int]
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
    structured_output_validation: _structured_output_pb2.StructuredOutputValidation
    total_tokens: int
    error_message: str
    error_code: int
    cached_prompt_tokens: int
    prompt_eval_time_ms: int
    decode_time_ms: int
    tool_calls: _containers.RepeatedCompositeFieldContainer[_tool_calling_pb2.ToolCall]
    tool_results: _containers.RepeatedCompositeFieldContainer[_tool_calling_pb2.ToolResult]
    def __init__(self, text: _Optional[str] = ..., thinking_content: _Optional[str] = ..., input_tokens: _Optional[int] = ..., tokens_generated: _Optional[int] = ..., model_used: _Optional[str] = ..., generation_time_ms: _Optional[float] = ..., ttft_ms: _Optional[float] = ..., tokens_per_second: _Optional[float] = ..., framework: _Optional[str] = ..., finish_reason: _Optional[str] = ..., thinking_tokens: _Optional[int] = ..., response_tokens: _Optional[int] = ..., json_output: _Optional[str] = ..., performance: _Optional[_Union[PerformanceMetrics, _Mapping]] = ..., executed_on: _Optional[_Union[ExecutionTarget, str]] = ..., structured_output_validation: _Optional[_Union[_structured_output_pb2.StructuredOutputValidation, _Mapping]] = ..., total_tokens: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ..., cached_prompt_tokens: _Optional[int] = ..., prompt_eval_time_ms: _Optional[int] = ..., decode_time_ms: _Optional[int] = ..., tool_calls: _Optional[_Iterable[_Union[_tool_calling_pb2.ToolCall, _Mapping]]] = ..., tool_results: _Optional[_Iterable[_Union[_tool_calling_pb2.ToolResult, _Mapping]]] = ...) -> None: ...

class LLMGenerationRequest(_message.Message):
    __slots__ = ("request_id", "model_id", "prompt", "options", "context_chunks", "metadata", "conversation_id")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_CHUNKS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    model_id: str
    prompt: str
    options: LLMGenerationOptions
    context_chunks: _containers.RepeatedScalarFieldContainer[str]
    metadata: _containers.ScalarMap[str, str]
    conversation_id: str
    def __init__(self, request_id: _Optional[str] = ..., model_id: _Optional[str] = ..., prompt: _Optional[str] = ..., options: _Optional[_Union[LLMGenerationOptions, _Mapping]] = ..., context_chunks: _Optional[_Iterable[str]] = ..., metadata: _Optional[_Mapping[str, str]] = ..., conversation_id: _Optional[str] = ...) -> None: ...

class LLMGenerationStatus(_message.Message):
    __slots__ = ("request_id", "state", "prompt_tokens_processed", "completion_tokens_generated", "progress", "elapsed_ms", "message", "error_message", "error_code")
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_PROCESSED_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_GENERATED_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    ELAPSED_MS_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    state: LLMGenerationState
    prompt_tokens_processed: int
    completion_tokens_generated: int
    progress: float
    elapsed_ms: int
    message: str
    error_message: str
    error_code: int
    def __init__(self, request_id: _Optional[str] = ..., state: _Optional[_Union[LLMGenerationState, str]] = ..., prompt_tokens_processed: _Optional[int] = ..., completion_tokens_generated: _Optional[int] = ..., progress: _Optional[float] = ..., elapsed_ms: _Optional[int] = ..., message: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class LLMConfiguration(_message.Message):
    __slots__ = ("context_length", "temperature", "max_tokens", "system_prompt", "streaming", "model_id", "preferred_framework")
    CONTEXT_LENGTH_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    STREAMING_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    context_length: int
    temperature: float
    max_tokens: int
    system_prompt: str
    streaming: bool
    model_id: str
    preferred_framework: _model_types_pb2.InferenceFramework
    def __init__(self, context_length: _Optional[int] = ..., temperature: _Optional[float] = ..., max_tokens: _Optional[int] = ..., system_prompt: _Optional[str] = ..., streaming: _Optional[bool] = ..., model_id: _Optional[str] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ...) -> None: ...

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
