from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class LLMStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    LLM_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_STARTED: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_TOKEN: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_THINKING: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_TOOL_CALL: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_PROGRESS: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_COMPLETED: _ClassVar[LLMStreamEventKind]
    LLM_STREAM_EVENT_KIND_ERROR: _ClassVar[LLMStreamEventKind]

class LLMTokenKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    LLM_TOKEN_KIND_UNSPECIFIED: _ClassVar[LLMTokenKind]
    LLM_TOKEN_KIND_ANSWER: _ClassVar[LLMTokenKind]
    LLM_TOKEN_KIND_THOUGHT: _ClassVar[LLMTokenKind]
    LLM_TOKEN_KIND_TOOL_CALL: _ClassVar[LLMTokenKind]
LLM_STREAM_EVENT_KIND_UNSPECIFIED: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_STARTED: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_TOKEN: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_THINKING: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_TOOL_CALL: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_PROGRESS: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_COMPLETED: LLMStreamEventKind
LLM_STREAM_EVENT_KIND_ERROR: LLMStreamEventKind
LLM_TOKEN_KIND_UNSPECIFIED: LLMTokenKind
LLM_TOKEN_KIND_ANSWER: LLMTokenKind
LLM_TOKEN_KIND_THOUGHT: LLMTokenKind
LLM_TOKEN_KIND_TOOL_CALL: LLMTokenKind

class LLMGenerateRequest(_message.Message):
    __slots__ = ("prompt", "max_tokens", "temperature", "top_p", "top_k", "system_prompt", "emit_thoughts", "repetition_penalty", "stop_sequences", "streaming_enabled", "preferred_framework", "json_schema", "execution_target", "request_id", "model_id", "conversation_id", "seed", "frequency_penalty", "presence_penalty", "min_p", "grammar", "response_format", "echo_prompt", "n_threads", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
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
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    SEED_FIELD_NUMBER: _ClassVar[int]
    FREQUENCY_PENALTY_FIELD_NUMBER: _ClassVar[int]
    PRESENCE_PENALTY_FIELD_NUMBER: _ClassVar[int]
    MIN_P_FIELD_NUMBER: _ClassVar[int]
    GRAMMAR_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_FORMAT_FIELD_NUMBER: _ClassVar[int]
    ECHO_PROMPT_FIELD_NUMBER: _ClassVar[int]
    N_THREADS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
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
    request_id: str
    model_id: str
    conversation_id: str
    seed: int
    frequency_penalty: float
    presence_penalty: float
    min_p: float
    grammar: str
    response_format: str
    echo_prompt: bool
    n_threads: int
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., system_prompt: _Optional[str] = ..., emit_thoughts: _Optional[bool] = ..., repetition_penalty: _Optional[float] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., preferred_framework: _Optional[str] = ..., json_schema: _Optional[str] = ..., execution_target: _Optional[str] = ..., request_id: _Optional[str] = ..., model_id: _Optional[str] = ..., conversation_id: _Optional[str] = ..., seed: _Optional[int] = ..., frequency_penalty: _Optional[float] = ..., presence_penalty: _Optional[float] = ..., min_p: _Optional[float] = ..., grammar: _Optional[str] = ..., response_format: _Optional[str] = ..., echo_prompt: _Optional[bool] = ..., n_threads: _Optional[int] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class LLMStreamFinalResult(_message.Message):
    __slots__ = ("text", "thinking_content", "prompt_tokens", "completion_tokens", "total_tokens", "total_time_ms", "time_to_first_token_ms", "tokens_per_second", "finish_reason", "error_code", "error_message", "prompt_eval_time_ms", "decode_time_ms")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    THINKING_CONTENT_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TIME_TO_FIRST_TOKEN_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    FINISH_REASON_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    PROMPT_EVAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    DECODE_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    text: str
    thinking_content: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    total_time_ms: int
    time_to_first_token_ms: int
    tokens_per_second: float
    finish_reason: str
    error_code: int
    error_message: str
    prompt_eval_time_ms: int
    decode_time_ms: int
    def __init__(self, text: _Optional[str] = ..., thinking_content: _Optional[str] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ..., total_tokens: _Optional[int] = ..., total_time_ms: _Optional[int] = ..., time_to_first_token_ms: _Optional[int] = ..., tokens_per_second: _Optional[float] = ..., finish_reason: _Optional[str] = ..., error_code: _Optional[int] = ..., error_message: _Optional[str] = ..., prompt_eval_time_ms: _Optional[int] = ..., decode_time_ms: _Optional[int] = ...) -> None: ...

class LLMStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "token", "is_final", "kind", "token_id", "logprob", "finish_reason", "error_message", "result", "error_code", "event_kind", "request_id", "conversation_id", "prompt_tokens_processed", "completion_tokens_generated", "elapsed_ms")
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
    EVENT_KIND_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_PROCESSED_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_GENERATED_FIELD_NUMBER: _ClassVar[int]
    ELAPSED_MS_FIELD_NUMBER: _ClassVar[int]
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
    event_kind: LLMStreamEventKind
    request_id: str
    conversation_id: str
    prompt_tokens_processed: int
    completion_tokens_generated: int
    elapsed_ms: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., token: _Optional[str] = ..., is_final: _Optional[bool] = ..., kind: _Optional[_Union[LLMTokenKind, str]] = ..., token_id: _Optional[int] = ..., logprob: _Optional[float] = ..., finish_reason: _Optional[str] = ..., error_message: _Optional[str] = ..., result: _Optional[_Union[LLMStreamFinalResult, _Mapping]] = ..., error_code: _Optional[int] = ..., event_kind: _Optional[_Union[LLMStreamEventKind, str]] = ..., request_id: _Optional[str] = ..., conversation_id: _Optional[str] = ..., prompt_tokens_processed: _Optional[int] = ..., completion_tokens_generated: _Optional[int] = ..., elapsed_ms: _Optional[int] = ...) -> None: ...
