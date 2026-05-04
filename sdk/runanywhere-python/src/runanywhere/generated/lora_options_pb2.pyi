from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class LoRAAdapterConfig(_message.Message):
    __slots__ = ("adapter_path", "scale", "adapter_id")
    ADAPTER_PATH_FIELD_NUMBER: _ClassVar[int]
    SCALE_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    adapter_path: str
    scale: float
    adapter_id: str
    def __init__(self, adapter_path: _Optional[str] = ..., scale: _Optional[float] = ..., adapter_id: _Optional[str] = ...) -> None: ...

class LoRAAdapterInfo(_message.Message):
    __slots__ = ("adapter_id", "adapter_path", "scale", "applied", "error_message")
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_PATH_FIELD_NUMBER: _ClassVar[int]
    SCALE_FIELD_NUMBER: _ClassVar[int]
    APPLIED_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    adapter_id: str
    adapter_path: str
    scale: float
    applied: bool
    error_message: str
    def __init__(self, adapter_id: _Optional[str] = ..., adapter_path: _Optional[str] = ..., scale: _Optional[float] = ..., applied: _Optional[bool] = ..., error_message: _Optional[str] = ...) -> None: ...

class LoraAdapterCatalogEntry(_message.Message):
    __slots__ = ("id", "name", "description", "url", "filename", "compatible_models", "size_bytes", "author", "default_scale", "checksum_sha256")
    ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    URL_FIELD_NUMBER: _ClassVar[int]
    FILENAME_FIELD_NUMBER: _ClassVar[int]
    COMPATIBLE_MODELS_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    AUTHOR_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_SCALE_FIELD_NUMBER: _ClassVar[int]
    CHECKSUM_SHA256_FIELD_NUMBER: _ClassVar[int]
    id: str
    name: str
    description: str
    url: str
    filename: str
    compatible_models: _containers.RepeatedScalarFieldContainer[str]
    size_bytes: int
    author: str
    default_scale: float
    checksum_sha256: str
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., description: _Optional[str] = ..., url: _Optional[str] = ..., filename: _Optional[str] = ..., compatible_models: _Optional[_Iterable[str]] = ..., size_bytes: _Optional[int] = ..., author: _Optional[str] = ..., default_scale: _Optional[float] = ..., checksum_sha256: _Optional[str] = ...) -> None: ...

class LoraCompatibilityResult(_message.Message):
    __slots__ = ("is_compatible", "error_message", "base_model_required")
    IS_COMPATIBLE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    BASE_MODEL_REQUIRED_FIELD_NUMBER: _ClassVar[int]
    is_compatible: bool
    error_message: str
    base_model_required: str
    def __init__(self, is_compatible: _Optional[bool] = ..., error_message: _Optional[str] = ..., base_model_required: _Optional[str] = ...) -> None: ...
