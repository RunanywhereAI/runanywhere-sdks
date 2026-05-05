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
    __slots__ = ("is_available", "required_bytes", "available_bytes", "warning_message", "recommendation", "shortfall_bytes", "required_to_available_ratio")
    IS_AVAILABLE_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_BYTES_FIELD_NUMBER: _ClassVar[int]
    WARNING_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RECOMMENDATION_FIELD_NUMBER: _ClassVar[int]
    SHORTFALL_BYTES_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_TO_AVAILABLE_RATIO_FIELD_NUMBER: _ClassVar[int]
    is_available: bool
    required_bytes: int
    available_bytes: int
    warning_message: str
    recommendation: str
    shortfall_bytes: int
    required_to_available_ratio: float
    def __init__(self, is_available: _Optional[bool] = ..., required_bytes: _Optional[int] = ..., available_bytes: _Optional[int] = ..., warning_message: _Optional[str] = ..., recommendation: _Optional[str] = ..., shortfall_bytes: _Optional[int] = ..., required_to_available_ratio: _Optional[float] = ...) -> None: ...

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

class StorageInfoRequest(_message.Message):
    __slots__ = ("include_device", "include_app", "include_models", "include_cache")
    INCLUDE_DEVICE_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_APP_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_MODELS_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_CACHE_FIELD_NUMBER: _ClassVar[int]
    include_device: bool
    include_app: bool
    include_models: bool
    include_cache: bool
    def __init__(self, include_device: _Optional[bool] = ..., include_app: _Optional[bool] = ..., include_models: _Optional[bool] = ..., include_cache: _Optional[bool] = ...) -> None: ...

class StorageInfoResult(_message.Message):
    __slots__ = ("success", "info", "error_message", "warnings")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    INFO_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    success: bool
    info: StorageInfo
    error_message: str
    warnings: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, success: _Optional[bool] = ..., info: _Optional[_Union[StorageInfo, _Mapping]] = ..., error_message: _Optional[str] = ..., warnings: _Optional[_Iterable[str]] = ...) -> None: ...

class StorageAvailabilityRequest(_message.Message):
    __slots__ = ("model_id", "required_bytes", "safety_margin", "include_existing_model_bytes", "include_delete_plan", "allow_cache_reclamation")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    SAFETY_MARGIN_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_EXISTING_MODEL_BYTES_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_DELETE_PLAN_FIELD_NUMBER: _ClassVar[int]
    ALLOW_CACHE_RECLAMATION_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    required_bytes: int
    safety_margin: float
    include_existing_model_bytes: bool
    include_delete_plan: bool
    allow_cache_reclamation: bool
    def __init__(self, model_id: _Optional[str] = ..., required_bytes: _Optional[int] = ..., safety_margin: _Optional[float] = ..., include_existing_model_bytes: _Optional[bool] = ..., include_delete_plan: _Optional[bool] = ..., allow_cache_reclamation: _Optional[bool] = ...) -> None: ...

class StorageAvailabilityResult(_message.Message):
    __slots__ = ("success", "availability", "warnings", "error_message", "delete_plan")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    AVAILABILITY_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    DELETE_PLAN_FIELD_NUMBER: _ClassVar[int]
    success: bool
    availability: StorageAvailability
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    delete_plan: StorageDeletePlan
    def __init__(self, success: _Optional[bool] = ..., availability: _Optional[_Union[StorageAvailability, _Mapping]] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ..., delete_plan: _Optional[_Union[StorageDeletePlan, _Mapping]] = ...) -> None: ...

class StorageDeletePlanRequest(_message.Message):
    __slots__ = ("model_ids", "required_bytes", "include_cache", "oldest_first", "allow_loaded_models", "include_download_partials")
    MODEL_IDS_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_CACHE_FIELD_NUMBER: _ClassVar[int]
    OLDEST_FIRST_FIELD_NUMBER: _ClassVar[int]
    ALLOW_LOADED_MODELS_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_DOWNLOAD_PARTIALS_FIELD_NUMBER: _ClassVar[int]
    model_ids: _containers.RepeatedScalarFieldContainer[str]
    required_bytes: int
    include_cache: bool
    oldest_first: bool
    allow_loaded_models: bool
    include_download_partials: bool
    def __init__(self, model_ids: _Optional[_Iterable[str]] = ..., required_bytes: _Optional[int] = ..., include_cache: _Optional[bool] = ..., oldest_first: _Optional[bool] = ..., allow_loaded_models: _Optional[bool] = ..., include_download_partials: _Optional[bool] = ...) -> None: ...

class StorageDeleteCandidate(_message.Message):
    __slots__ = ("model_id", "reclaimable_bytes", "last_used_ms", "is_loaded", "local_path", "requires_unload", "requires_platform_delete", "storage_key")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    RECLAIMABLE_BYTES_FIELD_NUMBER: _ClassVar[int]
    LAST_USED_MS_FIELD_NUMBER: _ClassVar[int]
    IS_LOADED_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_UNLOAD_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_PLATFORM_DELETE_FIELD_NUMBER: _ClassVar[int]
    STORAGE_KEY_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    reclaimable_bytes: int
    last_used_ms: int
    is_loaded: bool
    local_path: str
    requires_unload: bool
    requires_platform_delete: bool
    storage_key: str
    def __init__(self, model_id: _Optional[str] = ..., reclaimable_bytes: _Optional[int] = ..., last_used_ms: _Optional[int] = ..., is_loaded: _Optional[bool] = ..., local_path: _Optional[str] = ..., requires_unload: _Optional[bool] = ..., requires_platform_delete: _Optional[bool] = ..., storage_key: _Optional[str] = ...) -> None: ...

class StorageDeletePlan(_message.Message):
    __slots__ = ("can_reclaim_required_bytes", "required_bytes", "reclaimable_bytes", "candidates", "warnings", "error_message", "requires_unload", "requires_platform_delete", "candidate_count")
    CAN_RECLAIM_REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    RECLAIMABLE_BYTES_FIELD_NUMBER: _ClassVar[int]
    CANDIDATES_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_UNLOAD_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_PLATFORM_DELETE_FIELD_NUMBER: _ClassVar[int]
    CANDIDATE_COUNT_FIELD_NUMBER: _ClassVar[int]
    can_reclaim_required_bytes: bool
    required_bytes: int
    reclaimable_bytes: int
    candidates: _containers.RepeatedCompositeFieldContainer[StorageDeleteCandidate]
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    requires_unload: bool
    requires_platform_delete: bool
    candidate_count: int
    def __init__(self, can_reclaim_required_bytes: _Optional[bool] = ..., required_bytes: _Optional[int] = ..., reclaimable_bytes: _Optional[int] = ..., candidates: _Optional[_Iterable[_Union[StorageDeleteCandidate, _Mapping]]] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ..., requires_unload: _Optional[bool] = ..., requires_platform_delete: _Optional[bool] = ..., candidate_count: _Optional[int] = ...) -> None: ...

class StorageDeleteRequest(_message.Message):
    __slots__ = ("model_ids", "delete_files", "clear_registry_paths", "unload_if_loaded", "dry_run", "plan", "require_plan_match", "allow_platform_delete")
    MODEL_IDS_FIELD_NUMBER: _ClassVar[int]
    DELETE_FILES_FIELD_NUMBER: _ClassVar[int]
    CLEAR_REGISTRY_PATHS_FIELD_NUMBER: _ClassVar[int]
    UNLOAD_IF_LOADED_FIELD_NUMBER: _ClassVar[int]
    DRY_RUN_FIELD_NUMBER: _ClassVar[int]
    PLAN_FIELD_NUMBER: _ClassVar[int]
    REQUIRE_PLAN_MATCH_FIELD_NUMBER: _ClassVar[int]
    ALLOW_PLATFORM_DELETE_FIELD_NUMBER: _ClassVar[int]
    model_ids: _containers.RepeatedScalarFieldContainer[str]
    delete_files: bool
    clear_registry_paths: bool
    unload_if_loaded: bool
    dry_run: bool
    plan: StorageDeletePlan
    require_plan_match: bool
    allow_platform_delete: bool
    def __init__(self, model_ids: _Optional[_Iterable[str]] = ..., delete_files: _Optional[bool] = ..., clear_registry_paths: _Optional[bool] = ..., unload_if_loaded: _Optional[bool] = ..., dry_run: _Optional[bool] = ..., plan: _Optional[_Union[StorageDeletePlan, _Mapping]] = ..., require_plan_match: _Optional[bool] = ..., allow_platform_delete: _Optional[bool] = ...) -> None: ...

class StorageDeleteResult(_message.Message):
    __slots__ = ("success", "deleted_bytes", "deleted_model_ids", "failed_model_ids", "warnings", "error_message", "skipped_model_ids", "dry_run", "registry_updated", "files_deleted")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    DELETED_BYTES_FIELD_NUMBER: _ClassVar[int]
    DELETED_MODEL_IDS_FIELD_NUMBER: _ClassVar[int]
    FAILED_MODEL_IDS_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    SKIPPED_MODEL_IDS_FIELD_NUMBER: _ClassVar[int]
    DRY_RUN_FIELD_NUMBER: _ClassVar[int]
    REGISTRY_UPDATED_FIELD_NUMBER: _ClassVar[int]
    FILES_DELETED_FIELD_NUMBER: _ClassVar[int]
    success: bool
    deleted_bytes: int
    deleted_model_ids: _containers.RepeatedScalarFieldContainer[str]
    failed_model_ids: _containers.RepeatedScalarFieldContainer[str]
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    skipped_model_ids: _containers.RepeatedScalarFieldContainer[str]
    dry_run: bool
    registry_updated: bool
    files_deleted: bool
    def __init__(self, success: _Optional[bool] = ..., deleted_bytes: _Optional[int] = ..., deleted_model_ids: _Optional[_Iterable[str]] = ..., failed_model_ids: _Optional[_Iterable[str]] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ..., skipped_model_ids: _Optional[_Iterable[str]] = ..., dry_run: _Optional[bool] = ..., registry_updated: _Optional[bool] = ..., files_deleted: _Optional[bool] = ...) -> None: ...
