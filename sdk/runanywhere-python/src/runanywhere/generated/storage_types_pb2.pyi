from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class NPUChip(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    NPU_CHIP_UNSPECIFIED: _ClassVar[NPUChip]
    NPU_CHIP_NONE: _ClassVar[NPUChip]
    NPU_CHIP_APPLE_NEURAL_ENGINE: _ClassVar[NPUChip]
    NPU_CHIP_QUALCOMM_HEXAGON: _ClassVar[NPUChip]
    NPU_CHIP_MEDIATEK_APU: _ClassVar[NPUChip]
    NPU_CHIP_GOOGLE_TPU: _ClassVar[NPUChip]
    NPU_CHIP_INTEL_NPU: _ClassVar[NPUChip]
    NPU_CHIP_OTHER: _ClassVar[NPUChip]
NPU_CHIP_UNSPECIFIED: NPUChip
NPU_CHIP_NONE: NPUChip
NPU_CHIP_APPLE_NEURAL_ENGINE: NPUChip
NPU_CHIP_QUALCOMM_HEXAGON: NPUChip
NPU_CHIP_MEDIATEK_APU: NPUChip
NPU_CHIP_GOOGLE_TPU: NPUChip
NPU_CHIP_INTEL_NPU: NPUChip
NPU_CHIP_OTHER: NPUChip

class DeviceStorageInfo(_message.Message):
    __slots__ = ("total_bytes", "free_bytes", "used_bytes", "used_percent")
    TOTAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    FREE_BYTES_FIELD_NUMBER: _ClassVar[int]
    USED_BYTES_FIELD_NUMBER: _ClassVar[int]
    USED_PERCENT_FIELD_NUMBER: _ClassVar[int]
    total_bytes: int
    free_bytes: int
    used_bytes: int
    used_percent: float
    def __init__(self, total_bytes: _Optional[int] = ..., free_bytes: _Optional[int] = ..., used_bytes: _Optional[int] = ..., used_percent: _Optional[float] = ...) -> None: ...

class AppStorageInfo(_message.Message):
    __slots__ = ("documents_bytes", "cache_bytes", "app_support_bytes", "total_bytes")
    DOCUMENTS_BYTES_FIELD_NUMBER: _ClassVar[int]
    CACHE_BYTES_FIELD_NUMBER: _ClassVar[int]
    APP_SUPPORT_BYTES_FIELD_NUMBER: _ClassVar[int]
    TOTAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    documents_bytes: int
    cache_bytes: int
    app_support_bytes: int
    total_bytes: int
    def __init__(self, documents_bytes: _Optional[int] = ..., cache_bytes: _Optional[int] = ..., app_support_bytes: _Optional[int] = ..., total_bytes: _Optional[int] = ...) -> None: ...

class ModelStorageMetrics(_message.Message):
    __slots__ = ("model_id", "size_on_disk_bytes", "last_used_ms")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    SIZE_ON_DISK_BYTES_FIELD_NUMBER: _ClassVar[int]
    LAST_USED_MS_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    size_on_disk_bytes: int
    last_used_ms: int
    def __init__(self, model_id: _Optional[str] = ..., size_on_disk_bytes: _Optional[int] = ..., last_used_ms: _Optional[int] = ...) -> None: ...

class StorageInfo(_message.Message):
    __slots__ = ("app", "device", "models", "total_models", "total_models_bytes")
    APP_FIELD_NUMBER: _ClassVar[int]
    DEVICE_FIELD_NUMBER: _ClassVar[int]
    MODELS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_MODELS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_MODELS_BYTES_FIELD_NUMBER: _ClassVar[int]
    app: AppStorageInfo
    device: DeviceStorageInfo
    models: _containers.RepeatedCompositeFieldContainer[ModelStorageMetrics]
    total_models: int
    total_models_bytes: int
    def __init__(self, app: _Optional[_Union[AppStorageInfo, _Mapping]] = ..., device: _Optional[_Union[DeviceStorageInfo, _Mapping]] = ..., models: _Optional[_Iterable[_Union[ModelStorageMetrics, _Mapping]]] = ..., total_models: _Optional[int] = ..., total_models_bytes: _Optional[int] = ...) -> None: ...

class StorageAvailability(_message.Message):
    __slots__ = ("is_available", "required_bytes", "available_bytes", "warning_message", "recommendation")
    IS_AVAILABLE_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_BYTES_FIELD_NUMBER: _ClassVar[int]
    WARNING_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RECOMMENDATION_FIELD_NUMBER: _ClassVar[int]
    is_available: bool
    required_bytes: int
    available_bytes: int
    warning_message: str
    recommendation: str
    def __init__(self, is_available: _Optional[bool] = ..., required_bytes: _Optional[int] = ..., available_bytes: _Optional[int] = ..., warning_message: _Optional[str] = ..., recommendation: _Optional[str] = ...) -> None: ...

class StoredModel(_message.Message):
    __slots__ = ("model_id", "name", "size_bytes", "local_path", "downloaded_at_ms")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    DOWNLOADED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    name: str
    size_bytes: int
    local_path: str
    downloaded_at_ms: int
    def __init__(self, model_id: _Optional[str] = ..., name: _Optional[str] = ..., size_bytes: _Optional[int] = ..., local_path: _Optional[str] = ..., downloaded_at_ms: _Optional[int] = ...) -> None: ...
