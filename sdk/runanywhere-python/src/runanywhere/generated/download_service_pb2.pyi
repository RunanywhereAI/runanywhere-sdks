import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class DownloadStage(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DOWNLOAD_STAGE_UNSPECIFIED: _ClassVar[DownloadStage]
    DOWNLOAD_STAGE_DOWNLOADING: _ClassVar[DownloadStage]
    DOWNLOAD_STAGE_EXTRACTING: _ClassVar[DownloadStage]
    DOWNLOAD_STAGE_VALIDATING: _ClassVar[DownloadStage]
    DOWNLOAD_STAGE_COMPLETED: _ClassVar[DownloadStage]

class DownloadState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DOWNLOAD_STATE_UNSPECIFIED: _ClassVar[DownloadState]
    DOWNLOAD_STATE_PENDING: _ClassVar[DownloadState]
    DOWNLOAD_STATE_DOWNLOADING: _ClassVar[DownloadState]
    DOWNLOAD_STATE_EXTRACTING: _ClassVar[DownloadState]
    DOWNLOAD_STATE_RETRYING: _ClassVar[DownloadState]
    DOWNLOAD_STATE_COMPLETED: _ClassVar[DownloadState]
    DOWNLOAD_STATE_FAILED: _ClassVar[DownloadState]
    DOWNLOAD_STATE_CANCELLED: _ClassVar[DownloadState]
    DOWNLOAD_STATE_PAUSED: _ClassVar[DownloadState]
    DOWNLOAD_STATE_RESUMING: _ClassVar[DownloadState]
DOWNLOAD_STAGE_UNSPECIFIED: DownloadStage
DOWNLOAD_STAGE_DOWNLOADING: DownloadStage
DOWNLOAD_STAGE_EXTRACTING: DownloadStage
DOWNLOAD_STAGE_VALIDATING: DownloadStage
DOWNLOAD_STAGE_COMPLETED: DownloadStage
DOWNLOAD_STATE_UNSPECIFIED: DownloadState
DOWNLOAD_STATE_PENDING: DownloadState
DOWNLOAD_STATE_DOWNLOADING: DownloadState
DOWNLOAD_STATE_EXTRACTING: DownloadState
DOWNLOAD_STATE_RETRYING: DownloadState
DOWNLOAD_STATE_COMPLETED: DownloadState
DOWNLOAD_STATE_FAILED: DownloadState
DOWNLOAD_STATE_CANCELLED: DownloadState
DOWNLOAD_STATE_PAUSED: DownloadState
DOWNLOAD_STATE_RESUMING: DownloadState

class DownloadSubscribeRequest(_message.Message):
    __slots__ = ("model_id", "task_id")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    task_id: str
    def __init__(self, model_id: _Optional[str] = ..., task_id: _Optional[str] = ...) -> None: ...

class DownloadProgress(_message.Message):
    __slots__ = ("model_id", "stage", "bytes_downloaded", "total_bytes", "stage_progress", "overall_speed_bps", "eta_seconds", "state", "retry_attempt", "error_message", "task_id", "current_file_index", "total_files", "storage_key", "local_path", "overall_progress", "started_at_unix_ms", "updated_at_unix_ms", "current_file_name", "resume_token")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    STAGE_FIELD_NUMBER: _ClassVar[int]
    BYTES_DOWNLOADED_FIELD_NUMBER: _ClassVar[int]
    TOTAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    STAGE_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    OVERALL_SPEED_BPS_FIELD_NUMBER: _ClassVar[int]
    ETA_SECONDS_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    RETRY_ATTEMPT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    CURRENT_FILE_INDEX_FIELD_NUMBER: _ClassVar[int]
    TOTAL_FILES_FIELD_NUMBER: _ClassVar[int]
    STORAGE_KEY_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    OVERALL_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    STARTED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    UPDATED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    CURRENT_FILE_NAME_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    stage: DownloadStage
    bytes_downloaded: int
    total_bytes: int
    stage_progress: float
    overall_speed_bps: float
    eta_seconds: int
    state: DownloadState
    retry_attempt: int
    error_message: str
    task_id: str
    current_file_index: int
    total_files: int
    storage_key: str
    local_path: str
    overall_progress: float
    started_at_unix_ms: int
    updated_at_unix_ms: int
    current_file_name: str
    resume_token: str
    def __init__(self, model_id: _Optional[str] = ..., stage: _Optional[_Union[DownloadStage, str]] = ..., bytes_downloaded: _Optional[int] = ..., total_bytes: _Optional[int] = ..., stage_progress: _Optional[float] = ..., overall_speed_bps: _Optional[float] = ..., eta_seconds: _Optional[int] = ..., state: _Optional[_Union[DownloadState, str]] = ..., retry_attempt: _Optional[int] = ..., error_message: _Optional[str] = ..., task_id: _Optional[str] = ..., current_file_index: _Optional[int] = ..., total_files: _Optional[int] = ..., storage_key: _Optional[str] = ..., local_path: _Optional[str] = ..., overall_progress: _Optional[float] = ..., started_at_unix_ms: _Optional[int] = ..., updated_at_unix_ms: _Optional[int] = ..., current_file_name: _Optional[str] = ..., resume_token: _Optional[str] = ...) -> None: ...

class DownloadPlanRequest(_message.Message):
    __slots__ = ("model_id", "model", "resume_existing", "available_storage_bytes", "allow_metered_network", "storage_namespace", "validate_existing_bytes", "verify_checksums", "required_free_bytes_after_download")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    RESUME_EXISTING_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_STORAGE_BYTES_FIELD_NUMBER: _ClassVar[int]
    ALLOW_METERED_NETWORK_FIELD_NUMBER: _ClassVar[int]
    STORAGE_NAMESPACE_FIELD_NUMBER: _ClassVar[int]
    VALIDATE_EXISTING_BYTES_FIELD_NUMBER: _ClassVar[int]
    VERIFY_CHECKSUMS_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_FREE_BYTES_AFTER_DOWNLOAD_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    model: _model_types_pb2.ModelInfo
    resume_existing: bool
    available_storage_bytes: int
    allow_metered_network: bool
    storage_namespace: str
    validate_existing_bytes: bool
    verify_checksums: bool
    required_free_bytes_after_download: int
    def __init__(self, model_id: _Optional[str] = ..., model: _Optional[_Union[_model_types_pb2.ModelInfo, _Mapping]] = ..., resume_existing: _Optional[bool] = ..., available_storage_bytes: _Optional[int] = ..., allow_metered_network: _Optional[bool] = ..., storage_namespace: _Optional[str] = ..., validate_existing_bytes: _Optional[bool] = ..., verify_checksums: _Optional[bool] = ..., required_free_bytes_after_download: _Optional[int] = ...) -> None: ...

class DownloadFilePlan(_message.Message):
    __slots__ = ("file", "storage_key", "destination_path", "expected_bytes", "requires_extraction", "checksum_sha256", "is_resume_candidate")
    FILE_FIELD_NUMBER: _ClassVar[int]
    STORAGE_KEY_FIELD_NUMBER: _ClassVar[int]
    DESTINATION_PATH_FIELD_NUMBER: _ClassVar[int]
    EXPECTED_BYTES_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_EXTRACTION_FIELD_NUMBER: _ClassVar[int]
    CHECKSUM_SHA256_FIELD_NUMBER: _ClassVar[int]
    IS_RESUME_CANDIDATE_FIELD_NUMBER: _ClassVar[int]
    file: _model_types_pb2.ModelFileDescriptor
    storage_key: str
    destination_path: str
    expected_bytes: int
    requires_extraction: bool
    checksum_sha256: str
    is_resume_candidate: bool
    def __init__(self, file: _Optional[_Union[_model_types_pb2.ModelFileDescriptor, _Mapping]] = ..., storage_key: _Optional[str] = ..., destination_path: _Optional[str] = ..., expected_bytes: _Optional[int] = ..., requires_extraction: _Optional[bool] = ..., checksum_sha256: _Optional[str] = ..., is_resume_candidate: _Optional[bool] = ...) -> None: ...

class DownloadPlanResult(_message.Message):
    __slots__ = ("can_start", "model_id", "files", "total_bytes", "requires_extraction", "can_resume", "resume_from_bytes", "warnings", "error_message", "storage_namespace", "resume_token", "required_free_bytes_after_download")
    CAN_START_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    FILES_FIELD_NUMBER: _ClassVar[int]
    TOTAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_EXTRACTION_FIELD_NUMBER: _ClassVar[int]
    CAN_RESUME_FIELD_NUMBER: _ClassVar[int]
    RESUME_FROM_BYTES_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    STORAGE_NAMESPACE_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_FREE_BYTES_AFTER_DOWNLOAD_FIELD_NUMBER: _ClassVar[int]
    can_start: bool
    model_id: str
    files: _containers.RepeatedCompositeFieldContainer[DownloadFilePlan]
    total_bytes: int
    requires_extraction: bool
    can_resume: bool
    resume_from_bytes: int
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    storage_namespace: str
    resume_token: str
    required_free_bytes_after_download: int
    def __init__(self, can_start: _Optional[bool] = ..., model_id: _Optional[str] = ..., files: _Optional[_Iterable[_Union[DownloadFilePlan, _Mapping]]] = ..., total_bytes: _Optional[int] = ..., requires_extraction: _Optional[bool] = ..., can_resume: _Optional[bool] = ..., resume_from_bytes: _Optional[int] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ..., storage_namespace: _Optional[str] = ..., resume_token: _Optional[str] = ..., required_free_bytes_after_download: _Optional[int] = ...) -> None: ...

class DownloadStartRequest(_message.Message):
    __slots__ = ("model_id", "plan", "resume", "resume_token", "update_registry_on_completion")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    PLAN_FIELD_NUMBER: _ClassVar[int]
    RESUME_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    UPDATE_REGISTRY_ON_COMPLETION_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    plan: DownloadPlanResult
    resume: bool
    resume_token: str
    update_registry_on_completion: bool
    def __init__(self, model_id: _Optional[str] = ..., plan: _Optional[_Union[DownloadPlanResult, _Mapping]] = ..., resume: _Optional[bool] = ..., resume_token: _Optional[str] = ..., update_registry_on_completion: _Optional[bool] = ...) -> None: ...

class DownloadStartResult(_message.Message):
    __slots__ = ("accepted", "task_id", "model_id", "initial_progress", "error_message", "resume_token")
    ACCEPTED_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    INITIAL_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    accepted: bool
    task_id: str
    model_id: str
    initial_progress: DownloadProgress
    error_message: str
    resume_token: str
    def __init__(self, accepted: _Optional[bool] = ..., task_id: _Optional[str] = ..., model_id: _Optional[str] = ..., initial_progress: _Optional[_Union[DownloadProgress, _Mapping]] = ..., error_message: _Optional[str] = ..., resume_token: _Optional[str] = ...) -> None: ...

class DownloadCancelRequest(_message.Message):
    __slots__ = ("task_id", "model_id", "delete_partial_bytes")
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    DELETE_PARTIAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    task_id: str
    model_id: str
    delete_partial_bytes: bool
    def __init__(self, task_id: _Optional[str] = ..., model_id: _Optional[str] = ..., delete_partial_bytes: _Optional[bool] = ...) -> None: ...

class DownloadCancelResult(_message.Message):
    __slots__ = ("success", "task_id", "model_id", "partial_bytes_deleted", "error_message", "was_running", "partial_bytes_preserved", "resume_token")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    PARTIAL_BYTES_DELETED_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    WAS_RUNNING_FIELD_NUMBER: _ClassVar[int]
    PARTIAL_BYTES_PRESERVED_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    success: bool
    task_id: str
    model_id: str
    partial_bytes_deleted: int
    error_message: str
    was_running: bool
    partial_bytes_preserved: bool
    resume_token: str
    def __init__(self, success: _Optional[bool] = ..., task_id: _Optional[str] = ..., model_id: _Optional[str] = ..., partial_bytes_deleted: _Optional[int] = ..., error_message: _Optional[str] = ..., was_running: _Optional[bool] = ..., partial_bytes_preserved: _Optional[bool] = ..., resume_token: _Optional[str] = ...) -> None: ...

class DownloadResumeRequest(_message.Message):
    __slots__ = ("task_id", "model_id", "resume_from_bytes", "resume_token", "validate_partial_bytes")
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    RESUME_FROM_BYTES_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    VALIDATE_PARTIAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    task_id: str
    model_id: str
    resume_from_bytes: int
    resume_token: str
    validate_partial_bytes: bool
    def __init__(self, task_id: _Optional[str] = ..., model_id: _Optional[str] = ..., resume_from_bytes: _Optional[int] = ..., resume_token: _Optional[str] = ..., validate_partial_bytes: _Optional[bool] = ...) -> None: ...

class DownloadResumeResult(_message.Message):
    __slots__ = ("accepted", "task_id", "model_id", "initial_progress", "error_message", "resume_token")
    ACCEPTED_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    INITIAL_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RESUME_TOKEN_FIELD_NUMBER: _ClassVar[int]
    accepted: bool
    task_id: str
    model_id: str
    initial_progress: DownloadProgress
    error_message: str
    resume_token: str
    def __init__(self, accepted: _Optional[bool] = ..., task_id: _Optional[str] = ..., model_id: _Optional[str] = ..., initial_progress: _Optional[_Union[DownloadProgress, _Mapping]] = ..., error_message: _Optional[str] = ..., resume_token: _Optional[str] = ...) -> None: ...
