import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class TTSVoiceGender(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TTS_VOICE_GENDER_UNSPECIFIED: _ClassVar[TTSVoiceGender]
    TTS_VOICE_GENDER_MALE: _ClassVar[TTSVoiceGender]
    TTS_VOICE_GENDER_FEMALE: _ClassVar[TTSVoiceGender]
    TTS_VOICE_GENDER_NEUTRAL: _ClassVar[TTSVoiceGender]

class TTSStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TTS_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[TTSStreamEventKind]
    TTS_STREAM_EVENT_KIND_STARTED: _ClassVar[TTSStreamEventKind]
    TTS_STREAM_EVENT_KIND_AUDIO_CHUNK: _ClassVar[TTSStreamEventKind]
    TTS_STREAM_EVENT_KIND_PHONEME: _ClassVar[TTSStreamEventKind]
    TTS_STREAM_EVENT_KIND_COMPLETED: _ClassVar[TTSStreamEventKind]
    TTS_STREAM_EVENT_KIND_ERROR: _ClassVar[TTSStreamEventKind]
    TTS_STREAM_EVENT_KIND_PROGRESS: _ClassVar[TTSStreamEventKind]
TTS_VOICE_GENDER_UNSPECIFIED: TTSVoiceGender
TTS_VOICE_GENDER_MALE: TTSVoiceGender
TTS_VOICE_GENDER_FEMALE: TTSVoiceGender
TTS_VOICE_GENDER_NEUTRAL: TTSVoiceGender
TTS_STREAM_EVENT_KIND_UNSPECIFIED: TTSStreamEventKind
TTS_STREAM_EVENT_KIND_STARTED: TTSStreamEventKind
TTS_STREAM_EVENT_KIND_AUDIO_CHUNK: TTSStreamEventKind
TTS_STREAM_EVENT_KIND_PHONEME: TTSStreamEventKind
TTS_STREAM_EVENT_KIND_COMPLETED: TTSStreamEventKind
TTS_STREAM_EVENT_KIND_ERROR: TTSStreamEventKind
TTS_STREAM_EVENT_KIND_PROGRESS: TTSStreamEventKind

class TTSConfiguration(_message.Message):
    __slots__ = ("model_id", "voice", "language_code", "speaking_rate", "pitch", "volume", "audio_format", "sample_rate", "enable_neural_voice", "enable_ssml", "preferred_framework")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    VOICE_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    SPEAKING_RATE_FIELD_NUMBER: _ClassVar[int]
    PITCH_FIELD_NUMBER: _ClassVar[int]
    VOLUME_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    ENABLE_NEURAL_VOICE_FIELD_NUMBER: _ClassVar[int]
    ENABLE_SSML_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    voice: str
    language_code: str
    speaking_rate: float
    pitch: float
    volume: float
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    enable_neural_voice: bool
    enable_ssml: bool
    preferred_framework: _model_types_pb2.InferenceFramework
    def __init__(self, model_id: _Optional[str] = ..., voice: _Optional[str] = ..., language_code: _Optional[str] = ..., speaking_rate: _Optional[float] = ..., pitch: _Optional[float] = ..., volume: _Optional[float] = ..., audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ..., enable_neural_voice: _Optional[bool] = ..., enable_ssml: _Optional[bool] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ...) -> None: ...

class TTSOptions(_message.Message):
    __slots__ = ("voice", "language_code", "speaking_rate", "pitch", "volume", "enable_ssml", "audio_format", "sample_rate", "speaker_id", "speed", "style")
    VOICE_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    SPEAKING_RATE_FIELD_NUMBER: _ClassVar[int]
    PITCH_FIELD_NUMBER: _ClassVar[int]
    VOLUME_FIELD_NUMBER: _ClassVar[int]
    ENABLE_SSML_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    SPEAKER_ID_FIELD_NUMBER: _ClassVar[int]
    SPEED_FIELD_NUMBER: _ClassVar[int]
    STYLE_FIELD_NUMBER: _ClassVar[int]
    voice: str
    language_code: str
    speaking_rate: float
    pitch: float
    volume: float
    enable_ssml: bool
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    speaker_id: int
    speed: float
    style: str
    def __init__(self, voice: _Optional[str] = ..., language_code: _Optional[str] = ..., speaking_rate: _Optional[float] = ..., pitch: _Optional[float] = ..., volume: _Optional[float] = ..., enable_ssml: _Optional[bool] = ..., audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ..., speaker_id: _Optional[int] = ..., speed: _Optional[float] = ..., style: _Optional[str] = ...) -> None: ...

class TTSSynthesisRequest(_message.Message):
    __slots__ = ("request_id", "text", "ssml", "options", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    TEXT_FIELD_NUMBER: _ClassVar[int]
    SSML_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    text: str
    ssml: str
    options: TTSOptions
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., text: _Optional[str] = ..., ssml: _Optional[str] = ..., options: _Optional[_Union[TTSOptions, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class TTSPhonemeTimestamp(_message.Message):
    __slots__ = ("phoneme", "start_ms", "end_ms")
    PHONEME_FIELD_NUMBER: _ClassVar[int]
    START_MS_FIELD_NUMBER: _ClassVar[int]
    END_MS_FIELD_NUMBER: _ClassVar[int]
    phoneme: str
    start_ms: int
    end_ms: int
    def __init__(self, phoneme: _Optional[str] = ..., start_ms: _Optional[int] = ..., end_ms: _Optional[int] = ...) -> None: ...

class TTSSynthesisMetadata(_message.Message):
    __slots__ = ("voice_id", "language_code", "processing_time_ms", "character_count", "audio_duration_ms", "characters_per_second")
    VOICE_ID_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    PROCESSING_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    CHARACTER_COUNT_FIELD_NUMBER: _ClassVar[int]
    AUDIO_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    CHARACTERS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    voice_id: str
    language_code: str
    processing_time_ms: int
    character_count: int
    audio_duration_ms: int
    characters_per_second: float
    def __init__(self, voice_id: _Optional[str] = ..., language_code: _Optional[str] = ..., processing_time_ms: _Optional[int] = ..., character_count: _Optional[int] = ..., audio_duration_ms: _Optional[int] = ..., characters_per_second: _Optional[float] = ...) -> None: ...

class TTSOutput(_message.Message):
    __slots__ = ("audio_data", "audio_format", "sample_rate", "duration_ms", "phoneme_timestamps", "metadata", "timestamp_ms", "chunk_index", "is_final", "audio_size_bytes", "error_message", "error_code")
    AUDIO_DATA_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    PHONEME_TIMESTAMPS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    CHUNK_INDEX_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    AUDIO_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    audio_data: bytes
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    duration_ms: int
    phoneme_timestamps: _containers.RepeatedCompositeFieldContainer[TTSPhonemeTimestamp]
    metadata: TTSSynthesisMetadata
    timestamp_ms: int
    chunk_index: int
    is_final: bool
    audio_size_bytes: int
    error_message: str
    error_code: int
    def __init__(self, audio_data: _Optional[bytes] = ..., audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ..., duration_ms: _Optional[int] = ..., phoneme_timestamps: _Optional[_Iterable[_Union[TTSPhonemeTimestamp, _Mapping]]] = ..., metadata: _Optional[_Union[TTSSynthesisMetadata, _Mapping]] = ..., timestamp_ms: _Optional[int] = ..., chunk_index: _Optional[int] = ..., is_final: _Optional[bool] = ..., audio_size_bytes: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class TTSSpeakResult(_message.Message):
    __slots__ = ("audio_format", "sample_rate", "duration_ms", "audio_size_bytes", "metadata", "timestamp_ms", "error_message", "error_code")
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    AUDIO_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    duration_ms: int
    audio_size_bytes: int
    metadata: TTSSynthesisMetadata
    timestamp_ms: int
    error_message: str
    error_code: int
    def __init__(self, audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ..., duration_ms: _Optional[int] = ..., audio_size_bytes: _Optional[int] = ..., metadata: _Optional[_Union[TTSSynthesisMetadata, _Mapping]] = ..., timestamp_ms: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class TTSVoiceInfo(_message.Message):
    __slots__ = ("id", "display_name", "language_code", "gender", "description", "is_neural", "is_system", "sample_rate", "supported_styles")
    ID_FIELD_NUMBER: _ClassVar[int]
    DISPLAY_NAME_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    GENDER_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    IS_NEURAL_FIELD_NUMBER: _ClassVar[int]
    IS_SYSTEM_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    SUPPORTED_STYLES_FIELD_NUMBER: _ClassVar[int]
    id: str
    display_name: str
    language_code: str
    gender: TTSVoiceGender
    description: str
    is_neural: bool
    is_system: bool
    sample_rate: int
    supported_styles: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, id: _Optional[str] = ..., display_name: _Optional[str] = ..., language_code: _Optional[str] = ..., gender: _Optional[_Union[TTSVoiceGender, str]] = ..., description: _Optional[str] = ..., is_neural: _Optional[bool] = ..., is_system: _Optional[bool] = ..., sample_rate: _Optional[int] = ..., supported_styles: _Optional[_Iterable[str]] = ...) -> None: ...

class TTSStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "request_id", "kind", "output", "phoneme", "speak_result", "error_message", "error_code", "progress", "chunk_index", "total_chunks", "elapsed_ms", "status_message")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    OUTPUT_FIELD_NUMBER: _ClassVar[int]
    PHONEME_FIELD_NUMBER: _ClassVar[int]
    SPEAK_RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    CHUNK_INDEX_FIELD_NUMBER: _ClassVar[int]
    TOTAL_CHUNKS_FIELD_NUMBER: _ClassVar[int]
    ELAPSED_MS_FIELD_NUMBER: _ClassVar[int]
    STATUS_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    request_id: str
    kind: TTSStreamEventKind
    output: TTSOutput
    phoneme: TTSPhonemeTimestamp
    speak_result: TTSSpeakResult
    error_message: str
    error_code: int
    progress: float
    chunk_index: int
    total_chunks: int
    elapsed_ms: int
    status_message: str
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., request_id: _Optional[str] = ..., kind: _Optional[_Union[TTSStreamEventKind, str]] = ..., output: _Optional[_Union[TTSOutput, _Mapping]] = ..., phoneme: _Optional[_Union[TTSPhonemeTimestamp, _Mapping]] = ..., speak_result: _Optional[_Union[TTSSpeakResult, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ..., progress: _Optional[float] = ..., chunk_index: _Optional[int] = ..., total_chunks: _Optional[int] = ..., elapsed_ms: _Optional[int] = ..., status_message: _Optional[str] = ...) -> None: ...

class TTSServiceState(_message.Message):
    __slots__ = ("is_ready", "current_voice", "voices", "supported_language_codes", "error_message", "error_code")
    IS_READY_FIELD_NUMBER: _ClassVar[int]
    CURRENT_VOICE_FIELD_NUMBER: _ClassVar[int]
    VOICES_FIELD_NUMBER: _ClassVar[int]
    SUPPORTED_LANGUAGE_CODES_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_ready: bool
    current_voice: str
    voices: _containers.RepeatedCompositeFieldContainer[TTSVoiceInfo]
    supported_language_codes: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    error_code: int
    def __init__(self, is_ready: _Optional[bool] = ..., current_voice: _Optional[str] = ..., voices: _Optional[_Iterable[_Union[TTSVoiceInfo, _Mapping]]] = ..., supported_language_codes: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...
