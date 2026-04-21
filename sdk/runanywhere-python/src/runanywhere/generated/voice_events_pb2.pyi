from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class TokenKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TOKEN_KIND_UNSPECIFIED: _ClassVar[TokenKind]
    TOKEN_KIND_ANSWER: _ClassVar[TokenKind]
    TOKEN_KIND_THOUGHT: _ClassVar[TokenKind]
    TOKEN_KIND_TOOL_CALL: _ClassVar[TokenKind]

class AudioEncoding(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    AUDIO_ENCODING_UNSPECIFIED: _ClassVar[AudioEncoding]
    AUDIO_ENCODING_PCM_F32_LE: _ClassVar[AudioEncoding]
    AUDIO_ENCODING_PCM_S16_LE: _ClassVar[AudioEncoding]

class VADEventType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VAD_EVENT_UNSPECIFIED: _ClassVar[VADEventType]
    VAD_EVENT_VOICE_START: _ClassVar[VADEventType]
    VAD_EVENT_VOICE_END_OF_UTTERANCE: _ClassVar[VADEventType]
    VAD_EVENT_BARGE_IN: _ClassVar[VADEventType]
    VAD_EVENT_SILENCE: _ClassVar[VADEventType]

class InterruptReason(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    INTERRUPT_REASON_UNSPECIFIED: _ClassVar[InterruptReason]
    INTERRUPT_REASON_USER_BARGE_IN: _ClassVar[InterruptReason]
    INTERRUPT_REASON_APP_STOP: _ClassVar[InterruptReason]
    INTERRUPT_REASON_AUDIO_ROUTE_CHANGE: _ClassVar[InterruptReason]
    INTERRUPT_REASON_TIMEOUT: _ClassVar[InterruptReason]

class PipelineState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PIPELINE_STATE_UNSPECIFIED: _ClassVar[PipelineState]
    PIPELINE_STATE_IDLE: _ClassVar[PipelineState]
    PIPELINE_STATE_LISTENING: _ClassVar[PipelineState]
    PIPELINE_STATE_THINKING: _ClassVar[PipelineState]
    PIPELINE_STATE_SPEAKING: _ClassVar[PipelineState]
    PIPELINE_STATE_STOPPED: _ClassVar[PipelineState]
TOKEN_KIND_UNSPECIFIED: TokenKind
TOKEN_KIND_ANSWER: TokenKind
TOKEN_KIND_THOUGHT: TokenKind
TOKEN_KIND_TOOL_CALL: TokenKind
AUDIO_ENCODING_UNSPECIFIED: AudioEncoding
AUDIO_ENCODING_PCM_F32_LE: AudioEncoding
AUDIO_ENCODING_PCM_S16_LE: AudioEncoding
VAD_EVENT_UNSPECIFIED: VADEventType
VAD_EVENT_VOICE_START: VADEventType
VAD_EVENT_VOICE_END_OF_UTTERANCE: VADEventType
VAD_EVENT_BARGE_IN: VADEventType
VAD_EVENT_SILENCE: VADEventType
INTERRUPT_REASON_UNSPECIFIED: InterruptReason
INTERRUPT_REASON_USER_BARGE_IN: InterruptReason
INTERRUPT_REASON_APP_STOP: InterruptReason
INTERRUPT_REASON_AUDIO_ROUTE_CHANGE: InterruptReason
INTERRUPT_REASON_TIMEOUT: InterruptReason
PIPELINE_STATE_UNSPECIFIED: PipelineState
PIPELINE_STATE_IDLE: PipelineState
PIPELINE_STATE_LISTENING: PipelineState
PIPELINE_STATE_THINKING: PipelineState
PIPELINE_STATE_SPEAKING: PipelineState
PIPELINE_STATE_STOPPED: PipelineState

class VoiceEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "user_said", "assistant_token", "audio", "vad", "interrupted", "state", "error", "metrics")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    USER_SAID_FIELD_NUMBER: _ClassVar[int]
    ASSISTANT_TOKEN_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FIELD_NUMBER: _ClassVar[int]
    VAD_FIELD_NUMBER: _ClassVar[int]
    INTERRUPTED_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    METRICS_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    user_said: UserSaidEvent
    assistant_token: AssistantTokenEvent
    audio: AudioFrameEvent
    vad: VADEvent
    interrupted: InterruptedEvent
    state: StateChangeEvent
    error: ErrorEvent
    metrics: MetricsEvent
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., user_said: _Optional[_Union[UserSaidEvent, _Mapping]] = ..., assistant_token: _Optional[_Union[AssistantTokenEvent, _Mapping]] = ..., audio: _Optional[_Union[AudioFrameEvent, _Mapping]] = ..., vad: _Optional[_Union[VADEvent, _Mapping]] = ..., interrupted: _Optional[_Union[InterruptedEvent, _Mapping]] = ..., state: _Optional[_Union[StateChangeEvent, _Mapping]] = ..., error: _Optional[_Union[ErrorEvent, _Mapping]] = ..., metrics: _Optional[_Union[MetricsEvent, _Mapping]] = ...) -> None: ...

class UserSaidEvent(_message.Message):
    __slots__ = ("text", "is_final", "confidence", "audio_start_us", "audio_end_us")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    AUDIO_START_US_FIELD_NUMBER: _ClassVar[int]
    AUDIO_END_US_FIELD_NUMBER: _ClassVar[int]
    text: str
    is_final: bool
    confidence: float
    audio_start_us: int
    audio_end_us: int
    def __init__(self, text: _Optional[str] = ..., is_final: _Optional[bool] = ..., confidence: _Optional[float] = ..., audio_start_us: _Optional[int] = ..., audio_end_us: _Optional[int] = ...) -> None: ...

class AssistantTokenEvent(_message.Message):
    __slots__ = ("text", "is_final", "kind")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    text: str
    is_final: bool
    kind: TokenKind
    def __init__(self, text: _Optional[str] = ..., is_final: _Optional[bool] = ..., kind: _Optional[_Union[TokenKind, str]] = ...) -> None: ...

class AudioFrameEvent(_message.Message):
    __slots__ = ("pcm", "sample_rate_hz", "channels", "encoding")
    PCM_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    ENCODING_FIELD_NUMBER: _ClassVar[int]
    pcm: bytes
    sample_rate_hz: int
    channels: int
    encoding: AudioEncoding
    def __init__(self, pcm: _Optional[bytes] = ..., sample_rate_hz: _Optional[int] = ..., channels: _Optional[int] = ..., encoding: _Optional[_Union[AudioEncoding, str]] = ...) -> None: ...

class VADEvent(_message.Message):
    __slots__ = ("type", "frame_offset_us")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    FRAME_OFFSET_US_FIELD_NUMBER: _ClassVar[int]
    type: VADEventType
    frame_offset_us: int
    def __init__(self, type: _Optional[_Union[VADEventType, str]] = ..., frame_offset_us: _Optional[int] = ...) -> None: ...

class InterruptedEvent(_message.Message):
    __slots__ = ("reason", "detail")
    REASON_FIELD_NUMBER: _ClassVar[int]
    DETAIL_FIELD_NUMBER: _ClassVar[int]
    reason: InterruptReason
    detail: str
    def __init__(self, reason: _Optional[_Union[InterruptReason, str]] = ..., detail: _Optional[str] = ...) -> None: ...

class StateChangeEvent(_message.Message):
    __slots__ = ("previous", "current")
    PREVIOUS_FIELD_NUMBER: _ClassVar[int]
    CURRENT_FIELD_NUMBER: _ClassVar[int]
    previous: PipelineState
    current: PipelineState
    def __init__(self, previous: _Optional[_Union[PipelineState, str]] = ..., current: _Optional[_Union[PipelineState, str]] = ...) -> None: ...

class ErrorEvent(_message.Message):
    __slots__ = ("code", "message", "component", "is_recoverable")
    CODE_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_FIELD_NUMBER: _ClassVar[int]
    IS_RECOVERABLE_FIELD_NUMBER: _ClassVar[int]
    code: int
    message: str
    component: str
    is_recoverable: bool
    def __init__(self, code: _Optional[int] = ..., message: _Optional[str] = ..., component: _Optional[str] = ..., is_recoverable: _Optional[bool] = ...) -> None: ...

class MetricsEvent(_message.Message):
    __slots__ = ("stt_final_ms", "llm_first_token_ms", "tts_first_audio_ms", "end_to_end_ms", "tokens_generated", "audio_samples_played", "is_over_budget")
    STT_FINAL_MS_FIELD_NUMBER: _ClassVar[int]
    LLM_FIRST_TOKEN_MS_FIELD_NUMBER: _ClassVar[int]
    TTS_FIRST_AUDIO_MS_FIELD_NUMBER: _ClassVar[int]
    END_TO_END_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_GENERATED_FIELD_NUMBER: _ClassVar[int]
    AUDIO_SAMPLES_PLAYED_FIELD_NUMBER: _ClassVar[int]
    IS_OVER_BUDGET_FIELD_NUMBER: _ClassVar[int]
    stt_final_ms: float
    llm_first_token_ms: float
    tts_first_audio_ms: float
    end_to_end_ms: float
    tokens_generated: int
    audio_samples_played: int
    is_over_budget: bool
    def __init__(self, stt_final_ms: _Optional[float] = ..., llm_first_token_ms: _Optional[float] = ..., tts_first_audio_ms: _Optional[float] = ..., end_to_end_ms: _Optional[float] = ..., tokens_generated: _Optional[int] = ..., audio_samples_played: _Optional[int] = ..., is_over_budget: _Optional[bool] = ...) -> None: ...
