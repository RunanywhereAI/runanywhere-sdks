import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SpeechActivityKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SPEECH_ACTIVITY_KIND_UNSPECIFIED: _ClassVar[SpeechActivityKind]
    SPEECH_ACTIVITY_KIND_SPEECH_STARTED: _ClassVar[SpeechActivityKind]
    SPEECH_ACTIVITY_KIND_SPEECH_ENDED: _ClassVar[SpeechActivityKind]
    SPEECH_ACTIVITY_KIND_ONGOING: _ClassVar[SpeechActivityKind]
SPEECH_ACTIVITY_KIND_UNSPECIFIED: SpeechActivityKind
SPEECH_ACTIVITY_KIND_SPEECH_STARTED: SpeechActivityKind
SPEECH_ACTIVITY_KIND_SPEECH_ENDED: SpeechActivityKind
SPEECH_ACTIVITY_KIND_ONGOING: SpeechActivityKind

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
    __slots__ = ("threshold", "min_speech_duration_ms", "min_silence_duration_ms", "max_speech_duration_ms")
    THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    MIN_SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    MIN_SILENCE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    MAX_SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    threshold: float
    min_speech_duration_ms: int
    min_silence_duration_ms: int
    max_speech_duration_ms: int
    def __init__(self, threshold: _Optional[float] = ..., min_speech_duration_ms: _Optional[int] = ..., min_silence_duration_ms: _Optional[int] = ..., max_speech_duration_ms: _Optional[int] = ...) -> None: ...

class VADResult(_message.Message):
    __slots__ = ("is_speech", "confidence", "energy", "duration_ms", "timestamp_ms", "start_time_ms", "end_time_ms")
    IS_SPEECH_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    ENERGY_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    START_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    END_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    is_speech: bool
    confidence: float
    energy: float
    duration_ms: int
    timestamp_ms: int
    start_time_ms: int
    end_time_ms: int
    def __init__(self, is_speech: _Optional[bool] = ..., confidence: _Optional[float] = ..., energy: _Optional[float] = ..., duration_ms: _Optional[int] = ..., timestamp_ms: _Optional[int] = ..., start_time_ms: _Optional[int] = ..., end_time_ms: _Optional[int] = ...) -> None: ...

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
    __slots__ = ("event_type", "timestamp_ms", "duration_ms")
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    event_type: SpeechActivityKind
    timestamp_ms: int
    duration_ms: int
    def __init__(self, event_type: _Optional[_Union[SpeechActivityKind, str]] = ..., timestamp_ms: _Optional[int] = ..., duration_ms: _Optional[int] = ...) -> None: ...
