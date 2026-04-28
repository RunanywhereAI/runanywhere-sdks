import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class STTLanguage(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    STT_LANGUAGE_UNSPECIFIED: _ClassVar[STTLanguage]
    STT_LANGUAGE_AUTO: _ClassVar[STTLanguage]
    STT_LANGUAGE_EN: _ClassVar[STTLanguage]
    STT_LANGUAGE_ES: _ClassVar[STTLanguage]
    STT_LANGUAGE_FR: _ClassVar[STTLanguage]
    STT_LANGUAGE_DE: _ClassVar[STTLanguage]
    STT_LANGUAGE_ZH: _ClassVar[STTLanguage]
    STT_LANGUAGE_JA: _ClassVar[STTLanguage]
    STT_LANGUAGE_KO: _ClassVar[STTLanguage]
    STT_LANGUAGE_IT: _ClassVar[STTLanguage]
    STT_LANGUAGE_PT: _ClassVar[STTLanguage]
    STT_LANGUAGE_AR: _ClassVar[STTLanguage]
    STT_LANGUAGE_RU: _ClassVar[STTLanguage]
    STT_LANGUAGE_HI: _ClassVar[STTLanguage]
STT_LANGUAGE_UNSPECIFIED: STTLanguage
STT_LANGUAGE_AUTO: STTLanguage
STT_LANGUAGE_EN: STTLanguage
STT_LANGUAGE_ES: STTLanguage
STT_LANGUAGE_FR: STTLanguage
STT_LANGUAGE_DE: STTLanguage
STT_LANGUAGE_ZH: STTLanguage
STT_LANGUAGE_JA: STTLanguage
STT_LANGUAGE_KO: STTLanguage
STT_LANGUAGE_IT: STTLanguage
STT_LANGUAGE_PT: STTLanguage
STT_LANGUAGE_AR: STTLanguage
STT_LANGUAGE_RU: STTLanguage
STT_LANGUAGE_HI: STTLanguage

class STTConfiguration(_message.Message):
    __slots__ = ("model_id", "language", "sample_rate", "enable_vad", "audio_format")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    ENABLE_VAD_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FORMAT_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    language: STTLanguage
    sample_rate: int
    enable_vad: bool
    audio_format: _model_types_pb2.AudioFormat
    def __init__(self, model_id: _Optional[str] = ..., language: _Optional[_Union[STTLanguage, str]] = ..., sample_rate: _Optional[int] = ..., enable_vad: _Optional[bool] = ..., audio_format: _Optional[_Union[_model_types_pb2.AudioFormat, str]] = ...) -> None: ...

class STTOptions(_message.Message):
    __slots__ = ("language", "enable_punctuation", "enable_diarization", "max_speakers", "vocabulary_list", "enable_word_timestamps", "beam_size")
    LANGUAGE_FIELD_NUMBER: _ClassVar[int]
    ENABLE_PUNCTUATION_FIELD_NUMBER: _ClassVar[int]
    ENABLE_DIARIZATION_FIELD_NUMBER: _ClassVar[int]
    MAX_SPEAKERS_FIELD_NUMBER: _ClassVar[int]
    VOCABULARY_LIST_FIELD_NUMBER: _ClassVar[int]
    ENABLE_WORD_TIMESTAMPS_FIELD_NUMBER: _ClassVar[int]
    BEAM_SIZE_FIELD_NUMBER: _ClassVar[int]
    language: STTLanguage
    enable_punctuation: bool
    enable_diarization: bool
    max_speakers: int
    vocabulary_list: _containers.RepeatedScalarFieldContainer[str]
    enable_word_timestamps: bool
    beam_size: int
    def __init__(self, language: _Optional[_Union[STTLanguage, str]] = ..., enable_punctuation: _Optional[bool] = ..., enable_diarization: _Optional[bool] = ..., max_speakers: _Optional[int] = ..., vocabulary_list: _Optional[_Iterable[str]] = ..., enable_word_timestamps: _Optional[bool] = ..., beam_size: _Optional[int] = ...) -> None: ...

class WordTimestamp(_message.Message):
    __slots__ = ("word", "start_ms", "end_ms", "confidence")
    WORD_FIELD_NUMBER: _ClassVar[int]
    START_MS_FIELD_NUMBER: _ClassVar[int]
    END_MS_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    word: str
    start_ms: int
    end_ms: int
    confidence: float
    def __init__(self, word: _Optional[str] = ..., start_ms: _Optional[int] = ..., end_ms: _Optional[int] = ..., confidence: _Optional[float] = ...) -> None: ...

class TranscriptionAlternative(_message.Message):
    __slots__ = ("text", "confidence", "words")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    WORDS_FIELD_NUMBER: _ClassVar[int]
    text: str
    confidence: float
    words: _containers.RepeatedCompositeFieldContainer[WordTimestamp]
    def __init__(self, text: _Optional[str] = ..., confidence: _Optional[float] = ..., words: _Optional[_Iterable[_Union[WordTimestamp, _Mapping]]] = ...) -> None: ...

class TranscriptionMetadata(_message.Message):
    __slots__ = ("model_id", "processing_time_ms", "audio_length_ms", "real_time_factor")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    PROCESSING_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    AUDIO_LENGTH_MS_FIELD_NUMBER: _ClassVar[int]
    REAL_TIME_FACTOR_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    processing_time_ms: int
    audio_length_ms: int
    real_time_factor: float
    def __init__(self, model_id: _Optional[str] = ..., processing_time_ms: _Optional[int] = ..., audio_length_ms: _Optional[int] = ..., real_time_factor: _Optional[float] = ...) -> None: ...

class STTOutput(_message.Message):
    __slots__ = ("text", "language", "confidence", "words", "alternatives", "metadata")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    WORDS_FIELD_NUMBER: _ClassVar[int]
    ALTERNATIVES_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    text: str
    language: STTLanguage
    confidence: float
    words: _containers.RepeatedCompositeFieldContainer[WordTimestamp]
    alternatives: _containers.RepeatedCompositeFieldContainer[TranscriptionAlternative]
    metadata: TranscriptionMetadata
    def __init__(self, text: _Optional[str] = ..., language: _Optional[_Union[STTLanguage, str]] = ..., confidence: _Optional[float] = ..., words: _Optional[_Iterable[_Union[WordTimestamp, _Mapping]]] = ..., alternatives: _Optional[_Iterable[_Union[TranscriptionAlternative, _Mapping]]] = ..., metadata: _Optional[_Union[TranscriptionMetadata, _Mapping]] = ...) -> None: ...

class STTPartialResult(_message.Message):
    __slots__ = ("text", "is_final", "stability")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    STABILITY_FIELD_NUMBER: _ClassVar[int]
    text: str
    is_final: bool
    stability: float
    def __init__(self, text: _Optional[str] = ..., is_final: _Optional[bool] = ..., stability: _Optional[float] = ...) -> None: ...
