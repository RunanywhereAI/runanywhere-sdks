import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class RAGConfiguration(_message.Message):
    __slots__ = ("embedding_model_path", "llm_model_path", "embedding_dimension", "top_k", "similarity_threshold", "chunk_size", "chunk_overlap", "max_context_tokens", "prompt_template", "embedding_config_json", "llm_config_json")
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
    def __init__(self, embedding_model_path: _Optional[str] = ..., llm_model_path: _Optional[str] = ..., embedding_dimension: _Optional[int] = ..., top_k: _Optional[int] = ..., similarity_threshold: _Optional[float] = ..., chunk_size: _Optional[int] = ..., chunk_overlap: _Optional[int] = ..., max_context_tokens: _Optional[int] = ..., prompt_template: _Optional[str] = ..., embedding_config_json: _Optional[str] = ..., llm_config_json: _Optional[str] = ...) -> None: ...

class RAGDocument(_message.Message):
    __slots__ = ("id", "text", "metadata_json", "metadata")
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
    id: str
    text: str
    metadata_json: str
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, id: _Optional[str] = ..., text: _Optional[str] = ..., metadata_json: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class RAGQueryOptions(_message.Message):
    __slots__ = ("question", "system_prompt", "max_tokens", "temperature", "top_p", "top_k")
    QUESTION_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    question: str
    system_prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    def __init__(self, question: _Optional[str] = ..., system_prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ...) -> None: ...

class RAGSearchResult(_message.Message):
    __slots__ = ("chunk_id", "text", "similarity_score", "source_document", "metadata", "metadata_json")
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
    chunk_id: str
    text: str
    similarity_score: float
    source_document: str
    metadata: _containers.ScalarMap[str, str]
    metadata_json: str
    def __init__(self, chunk_id: _Optional[str] = ..., text: _Optional[str] = ..., similarity_score: _Optional[float] = ..., source_document: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ..., metadata_json: _Optional[str] = ...) -> None: ...

class RAGResult(_message.Message):
    __slots__ = ("answer", "retrieved_chunks", "context_used", "retrieval_time_ms", "generation_time_ms", "total_time_ms")
    ANSWER_FIELD_NUMBER: _ClassVar[int]
    RETRIEVED_CHUNKS_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_USED_FIELD_NUMBER: _ClassVar[int]
    RETRIEVAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    GENERATION_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    answer: str
    retrieved_chunks: _containers.RepeatedCompositeFieldContainer[RAGSearchResult]
    context_used: str
    retrieval_time_ms: int
    generation_time_ms: int
    total_time_ms: int
    def __init__(self, answer: _Optional[str] = ..., retrieved_chunks: _Optional[_Iterable[_Union[RAGSearchResult, _Mapping]]] = ..., context_used: _Optional[str] = ..., retrieval_time_ms: _Optional[int] = ..., generation_time_ms: _Optional[int] = ..., total_time_ms: _Optional[int] = ...) -> None: ...

class RAGStatistics(_message.Message):
    __slots__ = ("indexed_documents", "indexed_chunks", "total_tokens_indexed", "last_updated_ms", "index_path", "stats_json", "vector_store_size_bytes")
    INDEXED_DOCUMENTS_FIELD_NUMBER: _ClassVar[int]
    INDEXED_CHUNKS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_INDEXED_FIELD_NUMBER: _ClassVar[int]
    LAST_UPDATED_MS_FIELD_NUMBER: _ClassVar[int]
    INDEX_PATH_FIELD_NUMBER: _ClassVar[int]
    STATS_JSON_FIELD_NUMBER: _ClassVar[int]
    VECTOR_STORE_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    indexed_documents: int
    indexed_chunks: int
    total_tokens_indexed: int
    last_updated_ms: int
    index_path: str
    stats_json: str
    vector_store_size_bytes: int
    def __init__(self, indexed_documents: _Optional[int] = ..., indexed_chunks: _Optional[int] = ..., total_tokens_indexed: _Optional[int] = ..., last_updated_ms: _Optional[int] = ..., index_path: _Optional[str] = ..., stats_json: _Optional[str] = ..., vector_store_size_bytes: _Optional[int] = ...) -> None: ...
