from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class EmbeddingsConfiguration(_message.Message):
    __slots__ = ("model_id", "embedding_dimension", "max_sequence_length", "normalize")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    EMBEDDING_DIMENSION_FIELD_NUMBER: _ClassVar[int]
    MAX_SEQUENCE_LENGTH_FIELD_NUMBER: _ClassVar[int]
    NORMALIZE_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    embedding_dimension: int
    max_sequence_length: int
    normalize: bool
    def __init__(self, model_id: _Optional[str] = ..., embedding_dimension: _Optional[int] = ..., max_sequence_length: _Optional[int] = ..., normalize: _Optional[bool] = ...) -> None: ...

class EmbeddingsOptions(_message.Message):
    __slots__ = ("normalize", "truncate", "batch_size")
    NORMALIZE_FIELD_NUMBER: _ClassVar[int]
    TRUNCATE_FIELD_NUMBER: _ClassVar[int]
    BATCH_SIZE_FIELD_NUMBER: _ClassVar[int]
    normalize: bool
    truncate: bool
    batch_size: int
    def __init__(self, normalize: _Optional[bool] = ..., truncate: _Optional[bool] = ..., batch_size: _Optional[int] = ...) -> None: ...

class EmbeddingVector(_message.Message):
    __slots__ = ("values", "norm", "text")
    VALUES_FIELD_NUMBER: _ClassVar[int]
    NORM_FIELD_NUMBER: _ClassVar[int]
    TEXT_FIELD_NUMBER: _ClassVar[int]
    values: _containers.RepeatedScalarFieldContainer[float]
    norm: float
    text: str
    def __init__(self, values: _Optional[_Iterable[float]] = ..., norm: _Optional[float] = ..., text: _Optional[str] = ...) -> None: ...

class EmbeddingsResult(_message.Message):
    __slots__ = ("vectors", "dimension", "processing_time_ms", "tokens_used")
    VECTORS_FIELD_NUMBER: _ClassVar[int]
    DIMENSION_FIELD_NUMBER: _ClassVar[int]
    PROCESSING_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_USED_FIELD_NUMBER: _ClassVar[int]
    vectors: _containers.RepeatedCompositeFieldContainer[EmbeddingVector]
    dimension: int
    processing_time_ms: int
    tokens_used: int
    def __init__(self, vectors: _Optional[_Iterable[_Union[EmbeddingVector, _Mapping]]] = ..., dimension: _Optional[int] = ..., processing_time_ms: _Optional[int] = ..., tokens_used: _Optional[int] = ...) -> None: ...
