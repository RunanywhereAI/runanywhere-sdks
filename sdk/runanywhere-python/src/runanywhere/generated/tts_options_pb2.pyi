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
TTS_VOICE_GENDER_UNSPECIFIED: TTSVoiceGender
TTS_VOICE_GENDER_MALE: TTSVoiceGender
TTS_VOICE_GENDER_FEMALE: TTSVoiceGender
TTS_VOICE_GENDER_NEUTRAL: TTSVoiceGender

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
    __slots__ = ("voice", "language_code", "speaking_rate", "pitch", "volume", "enable_ssml", "audio_format", "sample_rate")
    VOICE_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    SPEAKING_RATE_FIELD_NUMBER: _ClassVar[int]
    PITCH_FIELD_NUMBER: _ClassVar[int]
    VOLUME_FIELD_NUMBER: _ClassVar[int]
    ENABLE_SSML_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    voice: str
    language_code: str
    speaking_rate: float
    pitch: float
    volume: float
    enable_ssml: bool
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    def __init__(self, voice: _Optional[str] = ..., language_code: _Optional[str] = ..., speaking_rate: _Optional[float] = ..., pitch: _Optional[float] = ..., volume: _Optional[float] = ..., enable_ssml: _Optional[bool] = ..., audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ...) -> None: ...

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
    __slots__ = ("audio_data", "audio_format", "sample_rate", "duration_ms", "phoneme_timestamps", "metadata", "timestamp_ms")
    AUDIO_DATA_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    PHONEME_TIMESTAMPS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    audio_data: bytes
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    duration_ms: int
    phoneme_timestamps: _containers.RepeatedCompositeFieldContainer[TTSPhonemeTimestamp]
    metadata: TTSSynthesisMetadata
    timestamp_ms: int
    def __init__(self, audio_data: _Optional[bytes] = ..., audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ..., duration_ms: _Optional[int] = ..., phoneme_timestamps: _Optional[_Iterable[_Union[TTSPhonemeTimestamp, _Mapping]]] = ..., metadata: _Optional[_Union[TTSSynthesisMetadata, _Mapping]] = ..., timestamp_ms: _Optional[int] = ...) -> None: ...

class TTSSpeakResult(_message.Message):
    __slots__ = ("audio_format", "sample_rate", "duration_ms", "audio_size_bytes", "metadata", "timestamp_ms")
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    AUDIO_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    audio_format: _model_types_pb2.AudioFormat
    sample_rate: int
    duration_ms: int
    audio_size_bytes: int
    metadata: TTSSynthesisMetadata
    timestamp_ms: int
    def __init__(self, audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ..., sample_rate: _Optional[int] = ..., duration_ms: _Optional[int] = ..., audio_size_bytes: _Optional[int] = ..., metadata: _Optional[_Union[TTSSynthesisMetadata, _Mapping]] = ..., timestamp_ms: _Optional[int] = ...) -> None: ...

class TTSVoiceInfo(_message.Message):
    __slots__ = ("id", "display_name", "language_code", "gender", "description")
    ID_FIELD_NUMBER: _ClassVar[int]
    DISPLAY_NAME_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    GENDER_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    id: str
    display_name: str
    language_code: str
    gender: TTSVoiceGender
    description: str
    def __init__(self, id: _Optional[str] = ..., display_name: _Optional[str] = ..., language_code: _Optional[str] = ..., gender: _Optional[_Union[TTSVoiceGender, str]] = ..., description: _Optional[str] = ...) -> None: ...
