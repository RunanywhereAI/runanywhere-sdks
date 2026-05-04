from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SolutionType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SOLUTION_TYPE_UNSPECIFIED: _ClassVar[SolutionType]
    SOLUTION_TYPE_VOICE_AGENT: _ClassVar[SolutionType]
    SOLUTION_TYPE_RAG: _ClassVar[SolutionType]
    SOLUTION_TYPE_WAKEWORD: _ClassVar[SolutionType]
    SOLUTION_TYPE_TIME_SERIES: _ClassVar[SolutionType]
    SOLUTION_TYPE_AGENT_LOOP: _ClassVar[SolutionType]

class AudioSource(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    AUDIO_SOURCE_UNSPECIFIED: _ClassVar[AudioSource]
    AUDIO_SOURCE_MICROPHONE: _ClassVar[AudioSource]
    AUDIO_SOURCE_FILE: _ClassVar[AudioSource]
    AUDIO_SOURCE_CALLBACK: _ClassVar[AudioSource]

class VectorStore(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VECTOR_STORE_UNSPECIFIED: _ClassVar[VectorStore]
    VECTOR_STORE_USEARCH: _ClassVar[VectorStore]
    VECTOR_STORE_PGVECTOR: _ClassVar[VectorStore]
SOLUTION_TYPE_UNSPECIFIED: SolutionType
SOLUTION_TYPE_VOICE_AGENT: SolutionType
SOLUTION_TYPE_RAG: SolutionType
SOLUTION_TYPE_WAKEWORD: SolutionType
SOLUTION_TYPE_TIME_SERIES: SolutionType
SOLUTION_TYPE_AGENT_LOOP: SolutionType
AUDIO_SOURCE_UNSPECIFIED: AudioSource
AUDIO_SOURCE_MICROPHONE: AudioSource
AUDIO_SOURCE_FILE: AudioSource
AUDIO_SOURCE_CALLBACK: AudioSource
VECTOR_STORE_UNSPECIFIED: VectorStore
VECTOR_STORE_USEARCH: VectorStore
VECTOR_STORE_PGVECTOR: VectorStore

class SolutionConfig(_message.Message):
    __slots__ = ("voice_agent", "rag", "wake_word", "agent_loop", "time_series")
    VOICE_AGENT_FIELD_NUMBER: _ClassVar[int]
    RAG_FIELD_NUMBER: _ClassVar[int]
    WAKE_WORD_FIELD_NUMBER: _ClassVar[int]
    AGENT_LOOP_FIELD_NUMBER: _ClassVar[int]
    TIME_SERIES_FIELD_NUMBER: _ClassVar[int]
    voice_agent: VoiceAgentConfig
    rag: RAGConfig
    wake_word: WakeWordConfig
    agent_loop: AgentLoopConfig
    time_series: TimeSeriesConfig
    def __init__(self, voice_agent: _Optional[_Union[VoiceAgentConfig, _Mapping]] = ..., rag: _Optional[_Union[RAGConfig, _Mapping]] = ..., wake_word: _Optional[_Union[WakeWordConfig, _Mapping]] = ..., agent_loop: _Optional[_Union[AgentLoopConfig, _Mapping]] = ..., time_series: _Optional[_Union[TimeSeriesConfig, _Mapping]] = ...) -> None: ...

class SolutionHandle(_message.Message):
    __slots__ = ("handle_id", "solution_type", "created_at_ms", "state")
    HANDLE_ID_FIELD_NUMBER: _ClassVar[int]
    SOLUTION_TYPE_FIELD_NUMBER: _ClassVar[int]
    CREATED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    handle_id: str
    solution_type: str
    created_at_ms: int
    state: str
    def __init__(self, handle_id: _Optional[str] = ..., solution_type: _Optional[str] = ..., created_at_ms: _Optional[int] = ..., state: _Optional[str] = ...) -> None: ...

class VoiceAgentConfig(_message.Message):
    __slots__ = ("llm_model_id", "stt_model_id", "tts_model_id", "vad_model_id", "sample_rate_hz", "chunk_ms", "audio_source", "audio_file_path", "enable_barge_in", "barge_in_threshold_ms", "system_prompt", "max_context_tokens", "temperature", "emit_partials", "emit_thoughts", "type_kind")
    LLM_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    STT_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    TTS_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    VAD_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHUNK_MS_FIELD_NUMBER: _ClassVar[int]
    AUDIO_SOURCE_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FILE_PATH_FIELD_NUMBER: _ClassVar[int]
    ENABLE_BARGE_IN_FIELD_NUMBER: _ClassVar[int]
    BARGE_IN_THRESHOLD_MS_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_CONTEXT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    EMIT_PARTIALS_FIELD_NUMBER: _ClassVar[int]
    EMIT_THOUGHTS_FIELD_NUMBER: _ClassVar[int]
    TYPE_KIND_FIELD_NUMBER: _ClassVar[int]
    llm_model_id: str
    stt_model_id: str
    tts_model_id: str
    vad_model_id: str
    sample_rate_hz: int
    chunk_ms: int
    audio_source: AudioSource
    audio_file_path: str
    enable_barge_in: bool
    barge_in_threshold_ms: int
    system_prompt: str
    max_context_tokens: int
    temperature: float
    emit_partials: bool
    emit_thoughts: bool
    type_kind: SolutionType
    def __init__(self, llm_model_id: _Optional[str] = ..., stt_model_id: _Optional[str] = ..., tts_model_id: _Optional[str] = ..., vad_model_id: _Optional[str] = ..., sample_rate_hz: _Optional[int] = ..., chunk_ms: _Optional[int] = ..., audio_source: _Optional[_Union[AudioSource, str]] = ..., audio_file_path: _Optional[str] = ..., enable_barge_in: _Optional[bool] = ..., barge_in_threshold_ms: _Optional[int] = ..., system_prompt: _Optional[str] = ..., max_context_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., emit_partials: _Optional[bool] = ..., emit_thoughts: _Optional[bool] = ..., type_kind: _Optional[_Union[SolutionType, str]] = ...) -> None: ...

class RAGConfig(_message.Message):
    __slots__ = ("embed_model_id", "rerank_model_id", "llm_model_id", "vector_store", "vector_store_path", "retrieve_k", "rerank_top", "bm25_k1", "bm25_b", "rrf_k", "prompt_template", "type_kind")
    EMBED_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    RERANK_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    LLM_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    VECTOR_STORE_FIELD_NUMBER: _ClassVar[int]
    VECTOR_STORE_PATH_FIELD_NUMBER: _ClassVar[int]
    RETRIEVE_K_FIELD_NUMBER: _ClassVar[int]
    RERANK_TOP_FIELD_NUMBER: _ClassVar[int]
    BM25_K1_FIELD_NUMBER: _ClassVar[int]
    BM25_B_FIELD_NUMBER: _ClassVar[int]
    RRF_K_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TEMPLATE_FIELD_NUMBER: _ClassVar[int]
    TYPE_KIND_FIELD_NUMBER: _ClassVar[int]
    embed_model_id: str
    rerank_model_id: str
    llm_model_id: str
    vector_store: VectorStore
    vector_store_path: str
    retrieve_k: int
    rerank_top: int
    bm25_k1: float
    bm25_b: float
    rrf_k: int
    prompt_template: str
    type_kind: SolutionType
    def __init__(self, embed_model_id: _Optional[str] = ..., rerank_model_id: _Optional[str] = ..., llm_model_id: _Optional[str] = ..., vector_store: _Optional[_Union[VectorStore, str]] = ..., vector_store_path: _Optional[str] = ..., retrieve_k: _Optional[int] = ..., rerank_top: _Optional[int] = ..., bm25_k1: _Optional[float] = ..., bm25_b: _Optional[float] = ..., rrf_k: _Optional[int] = ..., prompt_template: _Optional[str] = ..., type_kind: _Optional[_Union[SolutionType, str]] = ...) -> None: ...

class WakeWordConfig(_message.Message):
    __slots__ = ("model_id", "keyword", "threshold", "pre_roll_ms", "sample_rate_hz", "type_kind")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    KEYWORD_FIELD_NUMBER: _ClassVar[int]
    THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    PRE_ROLL_MS_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    TYPE_KIND_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    keyword: str
    threshold: float
    pre_roll_ms: int
    sample_rate_hz: int
    type_kind: SolutionType
    def __init__(self, model_id: _Optional[str] = ..., keyword: _Optional[str] = ..., threshold: _Optional[float] = ..., pre_roll_ms: _Optional[int] = ..., sample_rate_hz: _Optional[int] = ..., type_kind: _Optional[_Union[SolutionType, str]] = ...) -> None: ...

class AgentLoopConfig(_message.Message):
    __slots__ = ("llm_model_id", "system_prompt", "tools", "max_iterations", "max_context_tokens", "type_kind")
    LLM_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    TOOLS_FIELD_NUMBER: _ClassVar[int]
    MAX_ITERATIONS_FIELD_NUMBER: _ClassVar[int]
    MAX_CONTEXT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TYPE_KIND_FIELD_NUMBER: _ClassVar[int]
    llm_model_id: str
    system_prompt: str
    tools: _containers.RepeatedCompositeFieldContainer[ToolSpec]
    max_iterations: int
    max_context_tokens: int
    type_kind: SolutionType
    def __init__(self, llm_model_id: _Optional[str] = ..., system_prompt: _Optional[str] = ..., tools: _Optional[_Iterable[_Union[ToolSpec, _Mapping]]] = ..., max_iterations: _Optional[int] = ..., max_context_tokens: _Optional[int] = ..., type_kind: _Optional[_Union[SolutionType, str]] = ...) -> None: ...

class ToolSpec(_message.Message):
    __slots__ = ("name", "description", "json_schema")
    NAME_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    name: str
    description: str
    json_schema: str
    def __init__(self, name: _Optional[str] = ..., description: _Optional[str] = ..., json_schema: _Optional[str] = ...) -> None: ...

class TimeSeriesConfig(_message.Message):
    __slots__ = ("anomaly_model_id", "llm_model_id", "window_size", "stride", "anomaly_threshold", "type_kind")
    ANOMALY_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    LLM_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    WINDOW_SIZE_FIELD_NUMBER: _ClassVar[int]
    STRIDE_FIELD_NUMBER: _ClassVar[int]
    ANOMALY_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    TYPE_KIND_FIELD_NUMBER: _ClassVar[int]
    anomaly_model_id: str
    llm_model_id: str
    window_size: int
    stride: int
    anomaly_threshold: float
    type_kind: SolutionType
    def __init__(self, anomaly_model_id: _Optional[str] = ..., llm_model_id: _Optional[str] = ..., window_size: _Optional[int] = ..., stride: _Optional[int] = ..., anomaly_threshold: _Optional[float] = ..., type_kind: _Optional[_Union[SolutionType, str]] = ...) -> None: ...
