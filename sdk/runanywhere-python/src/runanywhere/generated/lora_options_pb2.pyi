from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class LoRAAdapterConfig(_message.Message):
    __slots__ = ("adapter_path", "scale", "adapter_id", "metadata", "target_modules")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    ADAPTER_PATH_FIELD_NUMBER: _ClassVar[int]
    SCALE_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    TARGET_MODULES_FIELD_NUMBER: _ClassVar[int]
    adapter_path: str
    scale: float
    adapter_id: str
    metadata: _containers.ScalarMap[str, str]
    target_modules: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, adapter_path: _Optional[str] = ..., scale: _Optional[float] = ..., adapter_id: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ..., target_modules: _Optional[_Iterable[str]] = ...) -> None: ...

class LoRAAdapterInfo(_message.Message):
    __slots__ = ("adapter_id", "adapter_path", "scale", "applied", "error_message", "error_code", "loaded_at_ms")
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_PATH_FIELD_NUMBER: _ClassVar[int]
    SCALE_FIELD_NUMBER: _ClassVar[int]
    APPLIED_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    LOADED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    adapter_id: str
    adapter_path: str
    scale: float
    applied: bool
    error_message: str
    error_code: int
    loaded_at_ms: int
    def __init__(self, adapter_id: _Optional[str] = ..., adapter_path: _Optional[str] = ..., scale: _Optional[float] = ..., applied: _Optional[bool] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ..., loaded_at_ms: _Optional[int] = ...) -> None: ...

class LoraAdapterCatalogEntry(_message.Message):
    __slots__ = ("id", "name", "description", "url", "filename", "compatible_models", "size_bytes", "author", "default_scale", "checksum_sha256", "license", "tags", "metadata", "local_path", "is_downloaded", "downloaded_at_unix_ms", "is_imported", "status_message")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
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
    LICENSE_FIELD_NUMBER: _ClassVar[int]
    TAGS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    IS_DOWNLOADED_FIELD_NUMBER: _ClassVar[int]
    DOWNLOADED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    IS_IMPORTED_FIELD_NUMBER: _ClassVar[int]
    STATUS_MESSAGE_FIELD_NUMBER: _ClassVar[int]
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
    license: str
    tags: _containers.RepeatedScalarFieldContainer[str]
    metadata: _containers.ScalarMap[str, str]
    local_path: str
    is_downloaded: bool
    downloaded_at_unix_ms: int
    is_imported: bool
    status_message: str
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., description: _Optional[str] = ..., url: _Optional[str] = ..., filename: _Optional[str] = ..., compatible_models: _Optional[_Iterable[str]] = ..., size_bytes: _Optional[int] = ..., author: _Optional[str] = ..., default_scale: _Optional[float] = ..., checksum_sha256: _Optional[str] = ..., license: _Optional[str] = ..., tags: _Optional[_Iterable[str]] = ..., metadata: _Optional[_Mapping[str, str]] = ..., local_path: _Optional[str] = ..., is_downloaded: _Optional[bool] = ..., downloaded_at_unix_ms: _Optional[int] = ..., is_imported: _Optional[bool] = ..., status_message: _Optional[str] = ...) -> None: ...

class LoraAdapterCatalogQuery(_message.Message):
    __slots__ = ("adapter_id", "model_id", "downloaded_only", "search_query", "tags")
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    DOWNLOADED_ONLY_FIELD_NUMBER: _ClassVar[int]
    SEARCH_QUERY_FIELD_NUMBER: _ClassVar[int]
    TAGS_FIELD_NUMBER: _ClassVar[int]
    adapter_id: str
    model_id: str
    downloaded_only: bool
    search_query: str
    tags: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, adapter_id: _Optional[str] = ..., model_id: _Optional[str] = ..., downloaded_only: _Optional[bool] = ..., search_query: _Optional[str] = ..., tags: _Optional[_Iterable[str]] = ...) -> None: ...

class LoraAdapterCatalogListRequest(_message.Message):
    __slots__ = ("query", "include_counts")
    QUERY_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_COUNTS_FIELD_NUMBER: _ClassVar[int]
    query: LoraAdapterCatalogQuery
    include_counts: bool
    def __init__(self, query: _Optional[_Union[LoraAdapterCatalogQuery, _Mapping]] = ..., include_counts: _Optional[bool] = ...) -> None: ...

class LoraAdapterCatalogListResult(_message.Message):
    __slots__ = ("success", "entries", "error_message", "total_count", "filtered_count", "downloaded_count")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    TOTAL_COUNT_FIELD_NUMBER: _ClassVar[int]
    FILTERED_COUNT_FIELD_NUMBER: _ClassVar[int]
    DOWNLOADED_COUNT_FIELD_NUMBER: _ClassVar[int]
    success: bool
    entries: _containers.RepeatedCompositeFieldContainer[LoraAdapterCatalogEntry]
    error_message: str
    total_count: int
    filtered_count: int
    downloaded_count: int
    def __init__(self, success: _Optional[bool] = ..., entries: _Optional[_Iterable[_Union[LoraAdapterCatalogEntry, _Mapping]]] = ..., error_message: _Optional[str] = ..., total_count: _Optional[int] = ..., filtered_count: _Optional[int] = ..., downloaded_count: _Optional[int] = ...) -> None: ...

class LoraAdapterCatalogGetRequest(_message.Message):
    __slots__ = ("adapter_id",)
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    adapter_id: str
    def __init__(self, adapter_id: _Optional[str] = ...) -> None: ...

class LoraAdapterCatalogGetResult(_message.Message):
    __slots__ = ("found", "entry", "error_message")
    FOUND_FIELD_NUMBER: _ClassVar[int]
    ENTRY_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    found: bool
    entry: LoraAdapterCatalogEntry
    error_message: str
    def __init__(self, found: _Optional[bool] = ..., entry: _Optional[_Union[LoraAdapterCatalogEntry, _Mapping]] = ..., error_message: _Optional[str] = ...) -> None: ...

class LoraAdapterDownloadCompletedRequest(_message.Message):
    __slots__ = ("adapter_id", "local_path", "size_bytes", "checksum_sha256", "completed_at_unix_ms", "imported", "status_message")
    ADAPTER_ID_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    CHECKSUM_SHA256_FIELD_NUMBER: _ClassVar[int]
    COMPLETED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    IMPORTED_FIELD_NUMBER: _ClassVar[int]
    STATUS_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    adapter_id: str
    local_path: str
    size_bytes: int
    checksum_sha256: str
    completed_at_unix_ms: int
    imported: bool
    status_message: str
    def __init__(self, adapter_id: _Optional[str] = ..., local_path: _Optional[str] = ..., size_bytes: _Optional[int] = ..., checksum_sha256: _Optional[str] = ..., completed_at_unix_ms: _Optional[int] = ..., imported: _Optional[bool] = ..., status_message: _Optional[str] = ...) -> None: ...

class LoraAdapterDownloadCompletedResult(_message.Message):
    __slots__ = ("success", "entry", "error_message", "persisted")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    ENTRY_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    PERSISTED_FIELD_NUMBER: _ClassVar[int]
    success: bool
    entry: LoraAdapterCatalogEntry
    error_message: str
    persisted: bool
    def __init__(self, success: _Optional[bool] = ..., entry: _Optional[_Union[LoraAdapterCatalogEntry, _Mapping]] = ..., error_message: _Optional[str] = ..., persisted: _Optional[bool] = ...) -> None: ...

class LoraCompatibilityResult(_message.Message):
    __slots__ = ("is_compatible", "error_message", "base_model_required", "warnings", "error_code")
    IS_COMPATIBLE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    BASE_MODEL_REQUIRED_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_compatible: bool
    error_message: str
    base_model_required: str
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_code: int
    def __init__(self, is_compatible: _Optional[bool] = ..., error_message: _Optional[str] = ..., base_model_required: _Optional[str] = ..., warnings: _Optional[_Iterable[str]] = ..., error_code: _Optional[int] = ...) -> None: ...

class LoRAApplyRequest(_message.Message):
    __slots__ = ("request_id", "adapters", "replace_existing")
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    ADAPTERS_FIELD_NUMBER: _ClassVar[int]
    REPLACE_EXISTING_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    adapters: _containers.RepeatedCompositeFieldContainer[LoRAAdapterConfig]
    replace_existing: bool
    def __init__(self, request_id: _Optional[str] = ..., adapters: _Optional[_Iterable[_Union[LoRAAdapterConfig, _Mapping]]] = ..., replace_existing: _Optional[bool] = ...) -> None: ...

class LoRAApplyResult(_message.Message):
    __slots__ = ("request_id", "adapters", "success", "error_message", "error_code")
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    ADAPTERS_FIELD_NUMBER: _ClassVar[int]
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    adapters: _containers.RepeatedCompositeFieldContainer[LoRAAdapterInfo]
    success: bool
    error_message: str
    error_code: int
    def __init__(self, request_id: _Optional[str] = ..., adapters: _Optional[_Iterable[_Union[LoRAAdapterInfo, _Mapping]]] = ..., success: _Optional[bool] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class LoRARemoveRequest(_message.Message):
    __slots__ = ("request_id", "adapter_ids", "adapter_paths", "clear_all")
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_IDS_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_PATHS_FIELD_NUMBER: _ClassVar[int]
    CLEAR_ALL_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    adapter_ids: _containers.RepeatedScalarFieldContainer[str]
    adapter_paths: _containers.RepeatedScalarFieldContainer[str]
    clear_all: bool
    def __init__(self, request_id: _Optional[str] = ..., adapter_ids: _Optional[_Iterable[str]] = ..., adapter_paths: _Optional[_Iterable[str]] = ..., clear_all: _Optional[bool] = ...) -> None: ...

class LoRAState(_message.Message):
    __slots__ = ("loaded_adapters", "has_active_adapters", "base_model_id", "error_message", "error_code")
    LOADED_ADAPTERS_FIELD_NUMBER: _ClassVar[int]
    HAS_ACTIVE_ADAPTERS_FIELD_NUMBER: _ClassVar[int]
    BASE_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    loaded_adapters: _containers.RepeatedCompositeFieldContainer[LoRAAdapterInfo]
    has_active_adapters: bool
    base_model_id: str
    error_message: str
    error_code: int
    def __init__(self, loaded_adapters: _Optional[_Iterable[_Union[LoRAAdapterInfo, _Mapping]]] = ..., has_active_adapters: _Optional[bool] = ..., base_model_id: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...
