from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
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

class DownloadSubscribeRequest(_message.Message):
    __slots__ = ("model_id",)
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    def __init__(self, model_id: _Optional[str] = ...) -> None: ...

class DownloadProgress(_message.Message):
    __slots__ = ("model_id", "stage", "bytes_downloaded", "total_bytes", "stage_progress", "overall_speed_bps", "eta_seconds", "state", "retry_attempt", "error_message")
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
    def __init__(self, model_id: _Optional[str] = ..., stage: _Optional[_Union[DownloadStage, str]] = ..., bytes_downloaded: _Optional[int] = ..., total_bytes: _Optional[int] = ..., stage_progress: _Optional[float] = ..., overall_speed_bps: _Optional[float] = ..., eta_seconds: _Optional[int] = ..., state: _Optional[_Union[DownloadState, str]] = ..., retry_attempt: _Optional[int] = ..., error_message: _Optional[str] = ...) -> None: ...
