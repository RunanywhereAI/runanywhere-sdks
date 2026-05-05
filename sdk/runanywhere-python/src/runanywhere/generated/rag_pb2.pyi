import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class RAGStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    RAG_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[RAGStreamEventKind]
    RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED: _ClassVar[RAGStreamEventKind]
    RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED: _ClassVar[RAGStreamEventKind]
    RAG_STREAM_EVENT_KIND_CONTEXT_READY: _ClassVar[RAGStreamEventKind]
    RAG_STREAM_EVENT_KIND_TOKEN: _ClassVar[RAGStreamEventKind]
    RAG_STREAM_EVENT_KIND_COMPLETED: _ClassVar[RAGStreamEventKind]
    RAG_STREAM_EVENT_KIND_ERROR: _ClassVar[RAGStreamEventKind]
RAG_STREAM_EVENT_KIND_UNSPECIFIED: RAGStreamEventKind
RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED: RAGStreamEventKind
RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED: RAGStreamEventKind
RAG_STREAM_EVENT_KIND_CONTEXT_READY: RAGStreamEventKind
RAG_STREAM_EVENT_KIND_TOKEN: RAGStreamEventKind
RAG_STREAM_EVENT_KIND_COMPLETED: RAGStreamEventKind
RAG_STREAM_EVENT_KIND_ERROR: RAGStreamEventKind

class RAGConfiguration(_message.Message):
    __slots__ = ("embedding_model_path", "llm_model_path", "embedding_dimension", "top_k", "similarity_threshold", "chunk_size", "chunk_overlap", "max_context_tokens", "prompt_template", "embedding_config_json", "llm_config_json", "index_path", "persist_index", "rerank_results", "reranker_model_path")
    EMBEDDING_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    LLM_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    EMBEDDING_DIMENSION_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    SIMILARITY_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    CHUNK_SIZE_FIELD_NUMBER: _ClassVar[int]
    CHUNK_OVERLAP_FIELD_NUMBER: _ClassVar[int]
    MAX_CONTEXT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TEMPLATE_FIELD_NUMBER: _ClassVar[int]
    EMBEDDING_CONFIG_JSON_FIELD_NUMBER: _ClassVar[int]
    LLM_CONFIG_JSON_FIELD_NUMBER: _ClassVar[int]
    INDEX_PATH_FIELD_NUMBER: _ClassVar[int]
    PERSIST_INDEX_FIELD_NUMBER: _ClassVar[int]
    RERANK_RESULTS_FIELD_NUMBER: _ClassVar[int]
    RERANKER_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    embedding_model_path: str
    llm_model_path: str
    embedding_dimension: int
    top_k: int
    similarity_threshold: float
    chunk_size: int
    chunk_overlap: int
    max_context_tokens: int
    prompt_template: str
    embedding_config_json: str
    llm_config_json: str
    index_path: str
    persist_index: bool
    rerank_results: bool
    reranker_model_path: str
    def __init__(self, embedding_model_path: _Optional[str] = ..., llm_model_path: _Optional[str] = ..., embedding_dimension: _Optional[int] = ..., top_k: _Optional[int] = ..., similarity_threshold: _Optional[float] = ..., chunk_size: _Optional[int] = ..., chunk_overlap: _Optional[int] = ..., max_context_tokens: _Optional[int] = ..., prompt_template: _Optional[str] = ..., embedding_config_json: _Optional[str] = ..., llm_config_json: _Optional[str] = ..., index_path: _Optional[str] = ..., persist_index: _Optional[bool] = ..., rerank_results: _Optional[bool] = ..., reranker_model_path: _Optional[str] = ...) -> None: ...

class RAGDocument(_message.Message):
    __slots__ = ("id", "text", "metadata_json", "metadata", "source_uri", "adapter_handle", "media_type", "size_bytes")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    ID_FIELD_NUMBER: _ClassVar[int]
    TEXT_FIELD_NUMBER: _ClassVar[int]
    METADATA_JSON_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    SOURCE_URI_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_HANDLE_FIELD_NUMBER: _ClassVar[int]
    MEDIA_TYPE_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    id: str
    text: str
    metadata_json: str
    metadata: _containers.ScalarMap[str, str]
    source_uri: str
    adapter_handle: str
    media_type: str
    size_bytes: int
    def __init__(self, id: _Optional[str] = ..., text: _Optional[str] = ..., metadata_json: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ..., source_uri: _Optional[str] = ..., adapter_handle: _Optional[str] = ..., media_type: _Optional[str] = ..., size_bytes: _Optional[int] = ...) -> None: ...

class RAGIngestRequest(_message.Message):
    __slots__ = ("request_id", "documents", "replace_existing", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    DOCUMENTS_FIELD_NUMBER: _ClassVar[int]
    REPLACE_EXISTING_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    documents: _containers.RepeatedCompositeFieldContainer[RAGDocument]
    replace_existing: bool
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., documents: _Optional[_Iterable[_Union[RAGDocument, _Mapping]]] = ..., replace_existing: _Optional[bool] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class RAGQueryOptions(_message.Message):
    __slots__ = ("question", "system_prompt", "max_tokens", "temperature", "top_p", "top_k", "retrieval_top_k", "similarity_threshold", "stream")
    QUESTION_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    RETRIEVAL_TOP_K_FIELD_NUMBER: _ClassVar[int]
    SIMILARITY_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    STREAM_FIELD_NUMBER: _ClassVar[int]
    question: str
    system_prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    retrieval_top_k: int
    similarity_threshold: float
    stream: bool
    def __init__(self, question: _Optional[str] = ..., system_prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., retrieval_top_k: _Optional[int] = ..., similarity_threshold: _Optional[float] = ..., stream: _Optional[bool] = ...) -> None: ...

class RAGQueryRequest(_message.Message):
    __slots__ = ("request_id", "options", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    options: RAGQueryOptions
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., options: _Optional[_Union[RAGQueryOptions, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class RAGSearchResult(_message.Message):
    __slots__ = ("chunk_id", "text", "similarity_score", "source_document", "metadata", "metadata_json", "rank", "start_offset", "end_offset", "token_count")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    CHUNK_ID_FIELD_NUMBER: _ClassVar[int]
    TEXT_FIELD_NUMBER: _ClassVar[int]
    SIMILARITY_SCORE_FIELD_NUMBER: _ClassVar[int]
    SOURCE_DOCUMENT_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    METADATA_JSON_FIELD_NUMBER: _ClassVar[int]
    RANK_FIELD_NUMBER: _ClassVar[int]
    START_OFFSET_FIELD_NUMBER: _ClassVar[int]
    END_OFFSET_FIELD_NUMBER: _ClassVar[int]
    TOKEN_COUNT_FIELD_NUMBER: _ClassVar[int]
    chunk_id: str
    text: str
    similarity_score: float
    source_document: str
    metadata: _containers.ScalarMap[str, str]
    metadata_json: str
    rank: int
    start_offset: int
    end_offset: int
    token_count: int
    def __init__(self, chunk_id: _Optional[str] = ..., text: _Optional[str] = ..., similarity_score: _Optional[float] = ..., source_document: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ..., metadata_json: _Optional[str] = ..., rank: _Optional[int] = ..., start_offset: _Optional[int] = ..., end_offset: _Optional[int] = ..., token_count: _Optional[int] = ...) -> None: ...

class RAGResult(_message.Message):
    __slots__ = ("answer", "retrieved_chunks", "context_used", "retrieval_time_ms", "generation_time_ms", "total_time_ms", "prompt_tokens", "completion_tokens", "total_tokens", "error_message", "error_code", "request_id")
    ANSWER_FIELD_NUMBER: _ClassVar[int]
    RETRIEVED_CHUNKS_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_USED_FIELD_NUMBER: _ClassVar[int]
    RETRIEVAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    GENERATION_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    answer: str
    retrieved_chunks: _containers.RepeatedCompositeFieldContainer[RAGSearchResult]
    context_used: str
    retrieval_time_ms: int
    generation_time_ms: int
    total_time_ms: int
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    error_message: str
    error_code: int
    request_id: str
    def __init__(self, answer: _Optional[str] = ..., retrieved_chunks: _Optional[_Iterable[_Union[RAGSearchResult, _Mapping]]] = ..., context_used: _Optional[str] = ..., retrieval_time_ms: _Optional[int] = ..., generation_time_ms: _Optional[int] = ..., total_time_ms: _Optional[int] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ..., total_tokens: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ..., request_id: _Optional[str] = ...) -> None: ...

class RAGStatistics(_message.Message):
    __slots__ = ("indexed_documents", "indexed_chunks", "total_tokens_indexed", "last_updated_ms", "index_path", "stats_json", "vector_store_size_bytes", "is_persistent", "last_query_ms", "error_message", "error_code")
    INDEXED_DOCUMENTS_FIELD_NUMBER: _ClassVar[int]
    INDEXED_CHUNKS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_INDEXED_FIELD_NUMBER: _ClassVar[int]
    LAST_UPDATED_MS_FIELD_NUMBER: _ClassVar[int]
    INDEX_PATH_FIELD_NUMBER: _ClassVar[int]
    STATS_JSON_FIELD_NUMBER: _ClassVar[int]
    VECTOR_STORE_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    IS_PERSISTENT_FIELD_NUMBER: _ClassVar[int]
    LAST_QUERY_MS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    indexed_documents: int
    indexed_chunks: int
    total_tokens_indexed: int
    last_updated_ms: int
    index_path: str
    stats_json: str
    vector_store_size_bytes: int
    is_persistent: bool
    last_query_ms: int
    error_message: str
    error_code: int
    def __init__(self, indexed_documents: _Optional[int] = ..., indexed_chunks: _Optional[int] = ..., total_tokens_indexed: _Optional[int] = ..., last_updated_ms: _Optional[int] = ..., index_path: _Optional[str] = ..., stats_json: _Optional[str] = ..., vector_store_size_bytes: _Optional[int] = ..., is_persistent: _Optional[bool] = ..., last_query_ms: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class RAGIngestResult(_message.Message):
    __slots__ = ("request_id", "documents_ingested", "chunks_ingested", "statistics", "error_message", "error_code")
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    DOCUMENTS_INGESTED_FIELD_NUMBER: _ClassVar[int]
    CHUNKS_INGESTED_FIELD_NUMBER: _ClassVar[int]
    STATISTICS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    documents_ingested: int
    chunks_ingested: int
    statistics: RAGStatistics
    error_message: str
    error_code: int
    def __init__(self, request_id: _Optional[str] = ..., documents_ingested: _Optional[int] = ..., chunks_ingested: _Optional[int] = ..., statistics: _Optional[_Union[RAGStatistics, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class RAGStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "request_id", "kind", "chunk", "token", "result", "error_message", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    CHUNK_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    request_id: str
    kind: RAGStreamEventKind
    chunk: RAGSearchResult
    token: str
    result: RAGResult
    error_message: str
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., request_id: _Optional[str] = ..., kind: _Optional[_Union[RAGStreamEventKind, str]] = ..., chunk: _Optional[_Union[RAGSearchResult, _Mapping]] = ..., token: _Optional[str] = ..., result: _Optional[_Union[RAGResult, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class RAGServiceState(_message.Message):
    __slots__ = ("is_ready", "statistics", "is_indexing", "is_querying", "active_request_id", "error_message", "error_code")
    IS_READY_FIELD_NUMBER: _ClassVar[int]
    STATISTICS_FIELD_NUMBER: _ClassVar[int]
    IS_INDEXING_FIELD_NUMBER: _ClassVar[int]
    IS_QUERYING_FIELD_NUMBER: _ClassVar[int]
    ACTIVE_REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_ready: bool
    statistics: RAGStatistics
    is_indexing: bool
    is_querying: bool
    active_request_id: str
    error_message: str
    error_code: int
    def __init__(self, is_ready: _Optional[bool] = ..., statistics: _Optional[_Union[RAGStatistics, _Mapping]] = ..., is_indexing: _Optional[bool] = ..., is_querying: _Optional[bool] = ..., active_request_id: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...
