import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SpeechActivityKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SPEECH_ACTIVITY_KIND_UNSPECIFIED: _ClassVar[SpeechActivityKind]
    SPEECH_ACTIVITY_KIND_SPEECH_STARTED: _ClassVar[SpeechActivityKind]
    SPEECH_ACTIVITY_KIND_SPEECH_ENDED: _ClassVar[SpeechActivityKind]
    SPEECH_ACTIVITY_KIND_ONGOING: _ClassVar[SpeechActivityKind]

class VADAudioEncoding(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VAD_AUDIO_ENCODING_UNSPECIFIED: _ClassVar[VADAudioEncoding]
    VAD_AUDIO_ENCODING_PCM_F32_LE: _ClassVar[VADAudioEncoding]
    VAD_AUDIO_ENCODING_PCM_S16_LE: _ClassVar[VADAudioEncoding]

class VADStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VAD_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[VADStreamEventKind]
    VAD_STREAM_EVENT_KIND_STARTED: _ClassVar[VADStreamEventKind]
    VAD_STREAM_EVENT_KIND_FRAME: _ClassVar[VADStreamEventKind]
    VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY: _ClassVar[VADStreamEventKind]
    VAD_STREAM_EVENT_KIND_STATISTICS: _ClassVar[VADStreamEventKind]
    VAD_STREAM_EVENT_KIND_STOPPED: _ClassVar[VADStreamEventKind]
    VAD_STREAM_EVENT_KIND_ERROR: _ClassVar[VADStreamEventKind]
SPEECH_ACTIVITY_KIND_UNSPECIFIED: SpeechActivityKind
SPEECH_ACTIVITY_KIND_SPEECH_STARTED: SpeechActivityKind
SPEECH_ACTIVITY_KIND_SPEECH_ENDED: SpeechActivityKind
SPEECH_ACTIVITY_KIND_ONGOING: SpeechActivityKind
VAD_AUDIO_ENCODING_UNSPECIFIED: VADAudioEncoding
VAD_AUDIO_ENCODING_PCM_F32_LE: VADAudioEncoding
VAD_AUDIO_ENCODING_PCM_S16_LE: VADAudioEncoding
VAD_STREAM_EVENT_KIND_UNSPECIFIED: VADStreamEventKind
VAD_STREAM_EVENT_KIND_STARTED: VADStreamEventKind
VAD_STREAM_EVENT_KIND_FRAME: VADStreamEventKind
VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY: VADStreamEventKind
VAD_STREAM_EVENT_KIND_STATISTICS: VADStreamEventKind
VAD_STREAM_EVENT_KIND_STOPPED: VADStreamEventKind
VAD_STREAM_EVENT_KIND_ERROR: VADStreamEventKind

class VADConfiguration(_message.Message):
    __slots__ = ("model_id", "sample_rate", "frame_length_ms", "threshold", "enable_auto_calibration", "calibration_multiplier", "preferred_framework", "model_path", "window_size_samples", "max_speech_duration_ms")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    FRAME_LENGTH_MS_FIELD_NUMBER: _ClassVar[int]
    THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    ENABLE_AUTO_CALIBRATION_FIELD_NUMBER: _ClassVar[int]
    CALIBRATION_MULTIPLIER_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    WINDOW_SIZE_SAMPLES_FIELD_NUMBER: _ClassVar[int]
    MAX_SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    sample_rate: int
    frame_length_ms: int
    threshold: float
    enable_auto_calibration: bool
    calibration_multiplier: float
    preferred_framework: _model_types_pb2.InferenceFramework
    model_path: str
    window_size_samples: int
    max_speech_duration_ms: int
    def __init__(self, model_id: _Optional[str] = ..., sample_rate: _Optional[int] = ..., frame_length_ms: _Optional[int] = ..., threshold: _Optional[float] = ..., enable_auto_calibration: _Optional[bool] = ..., calibration_multiplier: _Optional[float] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ..., model_path: _Optional[str] = ..., window_size_samples: _Optional[int] = ..., max_speech_duration_ms: _Optional[int] = ...) -> None: ...

class VADOptions(_message.Message):
    __slots__ = ("threshold", "min_speech_duration_ms", "min_silence_duration_ms", "max_speech_duration_ms", "include_statistics")
    THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    MIN_SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    MIN_SILENCE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    MAX_SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_STATISTICS_FIELD_NUMBER: _ClassVar[int]
    threshold: float
    min_speech_duration_ms: int
    min_silence_duration_ms: int
    max_speech_duration_ms: int
    include_statistics: bool
    def __init__(self, threshold: _Optional[float] = ..., min_speech_duration_ms: _Optional[int] = ..., min_silence_duration_ms: _Optional[int] = ..., max_speech_duration_ms: _Optional[int] = ..., include_statistics: _Optional[bool] = ...) -> None: ...

class VADAudioSource(_message.Message):
    __slots__ = ("audio_data", "adapter_handle", "encoding", "sample_rate", "channels", "frame_offset_ms")
    AUDIO_DATA_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_HANDLE_FIELD_NUMBER: _ClassVar[int]
    ENCODING_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    FRAME_OFFSET_MS_FIELD_NUMBER: _ClassVar[int]
    audio_data: bytes
    adapter_handle: str
    encoding: VADAudioEncoding
    sample_rate: int
    channels: int
    frame_offset_ms: int
    def __init__(self, audio_data: _Optional[bytes] = ..., adapter_handle: _Optional[str] = ..., encoding: _Optional[_Union[VADAudioEncoding, str]] = ..., sample_rate: _Optional[int] = ..., channels: _Optional[int] = ..., frame_offset_ms: _Optional[int] = ...) -> None: ...

class VADProcessRequest(_message.Message):
    __slots__ = ("request_id", "audio", "options", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    audio: VADAudioSource
    options: VADOptions
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., audio: _Optional[_Union[VADAudioSource, _Mapping]] = ..., options: _Optional[_Union[VADOptions, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class VADResult(_message.Message):
    __slots__ = ("is_speech", "confidence", "energy", "duration_ms", "timestamp_ms", "start_time_ms", "end_time_ms", "statistics", "error_message", "error_code")
    IS_SPEECH_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    ENERGY_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    START_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    END_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    STATISTICS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_speech: bool
    confidence: float
    energy: float
    duration_ms: int
    timestamp_ms: int
    start_time_ms: int
    end_time_ms: int
    statistics: VADStatistics
    error_message: str
    error_code: int
    def __init__(self, is_speech: _Optional[bool] = ..., confidence: _Optional[float] = ..., energy: _Optional[float] = ..., duration_ms: _Optional[int] = ..., timestamp_ms: _Optional[int] = ..., start_time_ms: _Optional[int] = ..., end_time_ms: _Optional[int] = ..., statistics: _Optional[_Union[VADStatistics, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class VADStatistics(_message.Message):
    __slots__ = ("current_energy", "current_threshold", "ambient_level", "recent_avg", "recent_max", "total_speech_segments", "total_speech_duration_ms", "average_energy", "peak_energy")
    CURRENT_ENERGY_FIELD_NUMBER: _ClassVar[int]
    CURRENT_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    AMBIENT_LEVEL_FIELD_NUMBER: _ClassVar[int]
    RECENT_AVG_FIELD_NUMBER: _ClassVar[int]
    RECENT_MAX_FIELD_NUMBER: _ClassVar[int]
    TOTAL_SPEECH_SEGMENTS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    AVERAGE_ENERGY_FIELD_NUMBER: _ClassVar[int]
    PEAK_ENERGY_FIELD_NUMBER: _ClassVar[int]
    current_energy: float
    current_threshold: float
    ambient_level: float
    recent_avg: float
    recent_max: float
    total_speech_segments: int
    total_speech_duration_ms: int
    average_energy: float
    peak_energy: float
    def __init__(self, current_energy: _Optional[float] = ..., current_threshold: _Optional[float] = ..., ambient_level: _Optional[float] = ..., recent_avg: _Optional[float] = ..., recent_max: _Optional[float] = ..., total_speech_segments: _Optional[int] = ..., total_speech_duration_ms: _Optional[int] = ..., average_energy: _Optional[float] = ..., peak_energy: _Optional[float] = ...) -> None: ...

class SpeechActivityEvent(_message.Message):
    __slots__ = ("event_type", "timestamp_ms", "duration_ms", "confidence", "result", "segment_id")
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    SEGMENT_ID_FIELD_NUMBER: _ClassVar[int]
    event_type: SpeechActivityKind
    timestamp_ms: int
    duration_ms: int
    confidence: float
    result: VADResult
    segment_id: str
    def __init__(self, event_type: _Optional[_Union[SpeechActivityKind, str]] = ..., timestamp_ms: _Optional[int] = ..., duration_ms: _Optional[int] = ..., confidence: _Optional[float] = ..., result: _Optional[_Union[VADResult, _Mapping]] = ..., segment_id: _Optional[str] = ...) -> None: ...

class VADStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "request_id", "kind", "result", "activity", "statistics", "error_message", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    ACTIVITY_FIELD_NUMBER: _ClassVar[int]
    STATISTICS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    request_id: str
    kind: VADStreamEventKind
    result: VADResult
    activity: SpeechActivityEvent
    statistics: VADStatistics
    error_message: str
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., request_id: _Optional[str] = ..., kind: _Optional[_Union[VADStreamEventKind, str]] = ..., result: _Optional[_Union[VADResult, _Mapping]] = ..., activity: _Optional[_Union[SpeechActivityEvent, _Mapping]] = ..., statistics: _Optional[_Union[VADStatistics, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class VADServiceState(_message.Message):
    __slots__ = ("is_ready", "is_speech_active", "energy_threshold", "sample_rate", "frame_length_ms", "current_model", "error_message", "error_code")
    IS_READY_FIELD_NUMBER: _ClassVar[int]
    IS_SPEECH_ACTIVE_FIELD_NUMBER: _ClassVar[int]
    ENERGY_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    FRAME_LENGTH_MS_FIELD_NUMBER: _ClassVar[int]
    CURRENT_MODEL_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_ready: bool
    is_speech_active: bool
    energy_threshold: float
    sample_rate: int
    frame_length_ms: int
    current_model: str
    error_message: str
    error_code: int
    def __init__(self, is_ready: _Optional[bool] = ..., is_speech_active: _Optional[bool] = ..., energy_threshold: _Optional[float] = ..., sample_rate: _Optional[int] = ..., frame_length_ms: _Optional[int] = ..., current_model: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...
