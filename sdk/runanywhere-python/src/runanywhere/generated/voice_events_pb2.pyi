from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class VoiceEventCategory(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VOICE_EVENT_CATEGORY_UNSPECIFIED: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_VOICE_AGENT: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_STT: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_ASR: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_TTS: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_VAD: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_STD: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_LLM: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_AUDIO: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_METRICS: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_ERROR: _ClassVar[VoiceEventCategory]
    VOICE_EVENT_CATEGORY_WAKEWORD: _ClassVar[VoiceEventCategory]

class VoiceEventSeverity(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VOICE_EVENT_SEVERITY_DEBUG: _ClassVar[VoiceEventSeverity]
    VOICE_EVENT_SEVERITY_INFO: _ClassVar[VoiceEventSeverity]
    VOICE_EVENT_SEVERITY_WARNING: _ClassVar[VoiceEventSeverity]
    VOICE_EVENT_SEVERITY_ERROR: _ClassVar[VoiceEventSeverity]
    VOICE_EVENT_SEVERITY_CRITICAL: _ClassVar[VoiceEventSeverity]

class VoicePipelineComponent(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VOICE_PIPELINE_COMPONENT_UNSPECIFIED: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_AGENT: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_STT: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_ASR: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_TTS: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_VAD: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_STD: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_LLM: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_AUDIO: _ClassVar[VoicePipelineComponent]
    VOICE_PIPELINE_COMPONENT_WAKEWORD: _ClassVar[VoicePipelineComponent]

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
    VAD_EVENT_STATISTICS: _ClassVar[VADEventType]
    VAD_EVENT_STATE_CHANGED: _ClassVar[VADEventType]

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
    PIPELINE_STATE_WAITING_WAKEWORD: _ClassVar[PipelineState]
    PIPELINE_STATE_PROCESSING_SPEECH: _ClassVar[PipelineState]
    PIPELINE_STATE_GENERATING_RESPONSE: _ClassVar[PipelineState]
    PIPELINE_STATE_PLAYING_TTS: _ClassVar[PipelineState]
    PIPELINE_STATE_COOLDOWN: _ClassVar[PipelineState]
    PIPELINE_STATE_ERROR: _ClassVar[PipelineState]

class ComponentLoadState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    COMPONENT_LOAD_STATE_UNSPECIFIED: _ClassVar[ComponentLoadState]
    COMPONENT_LOAD_STATE_NOT_LOADED: _ClassVar[ComponentLoadState]
    COMPONENT_LOAD_STATE_LOADING: _ClassVar[ComponentLoadState]
    COMPONENT_LOAD_STATE_LOADED: _ClassVar[ComponentLoadState]
    COMPONENT_LOAD_STATE_ERROR: _ClassVar[ComponentLoadState]

class VoiceSessionErrorCode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VOICE_SESSION_ERROR_CODE_UNSPECIFIED: _ClassVar[VoiceSessionErrorCode]
    VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED: _ClassVar[VoiceSessionErrorCode]
    VOICE_SESSION_ERROR_CODE_NOT_READY: _ClassVar[VoiceSessionErrorCode]
    VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING: _ClassVar[VoiceSessionErrorCode]
    VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE: _ClassVar[VoiceSessionErrorCode]

class SpeechTurnDetectionEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED: _ClassVar[SpeechTurnDetectionEventKind]
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED: _ClassVar[SpeechTurnDetectionEventKind]
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED: _ClassVar[SpeechTurnDetectionEventKind]
    SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED: _ClassVar[SpeechTurnDetectionEventKind]
    SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS: _ClassVar[SpeechTurnDetectionEventKind]

class TurnLifecycleEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_STARTED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_COMPLETED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_CANCELLED: _ClassVar[TurnLifecycleEventKind]
    TURN_LIFECYCLE_EVENT_KIND_FAILED: _ClassVar[TurnLifecycleEventKind]
VOICE_EVENT_CATEGORY_UNSPECIFIED: VoiceEventCategory
VOICE_EVENT_CATEGORY_VOICE_AGENT: VoiceEventCategory
VOICE_EVENT_CATEGORY_STT: VoiceEventCategory
VOICE_EVENT_CATEGORY_ASR: VoiceEventCategory
VOICE_EVENT_CATEGORY_TTS: VoiceEventCategory
VOICE_EVENT_CATEGORY_VAD: VoiceEventCategory
VOICE_EVENT_CATEGORY_STD: VoiceEventCategory
VOICE_EVENT_CATEGORY_LLM: VoiceEventCategory
VOICE_EVENT_CATEGORY_AUDIO: VoiceEventCategory
VOICE_EVENT_CATEGORY_METRICS: VoiceEventCategory
VOICE_EVENT_CATEGORY_ERROR: VoiceEventCategory
VOICE_EVENT_CATEGORY_WAKEWORD: VoiceEventCategory
VOICE_EVENT_SEVERITY_DEBUG: VoiceEventSeverity
VOICE_EVENT_SEVERITY_INFO: VoiceEventSeverity
VOICE_EVENT_SEVERITY_WARNING: VoiceEventSeverity
VOICE_EVENT_SEVERITY_ERROR: VoiceEventSeverity
VOICE_EVENT_SEVERITY_CRITICAL: VoiceEventSeverity
VOICE_PIPELINE_COMPONENT_UNSPECIFIED: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_AGENT: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_STT: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_ASR: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_TTS: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_VAD: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_STD: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_LLM: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_AUDIO: VoicePipelineComponent
VOICE_PIPELINE_COMPONENT_WAKEWORD: VoicePipelineComponent
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
VAD_EVENT_STATISTICS: VADEventType
VAD_EVENT_STATE_CHANGED: VADEventType
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
PIPELINE_STATE_WAITING_WAKEWORD: PipelineState
PIPELINE_STATE_PROCESSING_SPEECH: PipelineState
PIPELINE_STATE_GENERATING_RESPONSE: PipelineState
PIPELINE_STATE_PLAYING_TTS: PipelineState
PIPELINE_STATE_COOLDOWN: PipelineState
PIPELINE_STATE_ERROR: PipelineState
COMPONENT_LOAD_STATE_UNSPECIFIED: ComponentLoadState
COMPONENT_LOAD_STATE_NOT_LOADED: ComponentLoadState
COMPONENT_LOAD_STATE_LOADING: ComponentLoadState
COMPONENT_LOAD_STATE_LOADED: ComponentLoadState
COMPONENT_LOAD_STATE_ERROR: ComponentLoadState
VOICE_SESSION_ERROR_CODE_UNSPECIFIED: VoiceSessionErrorCode
VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED: VoiceSessionErrorCode
VOICE_SESSION_ERROR_CODE_NOT_READY: VoiceSessionErrorCode
VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING: VoiceSessionErrorCode
VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE: VoiceSessionErrorCode
SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED: SpeechTurnDetectionEventKind
SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED: SpeechTurnDetectionEventKind
SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED: SpeechTurnDetectionEventKind
SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED: SpeechTurnDetectionEventKind
SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS: SpeechTurnDetectionEventKind
TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_STARTED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_COMPLETED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_CANCELLED: TurnLifecycleEventKind
TURN_LIFECYCLE_EVENT_KIND_FAILED: TurnLifecycleEventKind

class VoiceEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "category", "severity", "component", "user_said", "assistant_token", "audio", "vad", "interrupted", "state", "error", "metrics", "component_state_changed", "session_error", "session_started", "session_stopped", "agent_response_started", "agent_response_completed", "speech_turn_detection", "turn_lifecycle", "wakeword_detected", "audio_level", "component_progress", "session_id", "turn_id", "request_id", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    SEVERITY_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_FIELD_NUMBER: _ClassVar[int]
    USER_SAID_FIELD_NUMBER: _ClassVar[int]
    ASSISTANT_TOKEN_FIELD_NUMBER: _ClassVar[int]
    AUDIO_FIELD_NUMBER: _ClassVar[int]
    VAD_FIELD_NUMBER: _ClassVar[int]
    INTERRUPTED_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    METRICS_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_STATE_CHANGED_FIELD_NUMBER: _ClassVar[int]
    SESSION_ERROR_FIELD_NUMBER: _ClassVar[int]
    SESSION_STARTED_FIELD_NUMBER: _ClassVar[int]
    SESSION_STOPPED_FIELD_NUMBER: _ClassVar[int]
    AGENT_RESPONSE_STARTED_FIELD_NUMBER: _ClassVar[int]
    AGENT_RESPONSE_COMPLETED_FIELD_NUMBER: _ClassVar[int]
    SPEECH_TURN_DETECTION_FIELD_NUMBER: _ClassVar[int]
    TURN_LIFECYCLE_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_DETECTED_FIELD_NUMBER: _ClassVar[int]
    AUDIO_LEVEL_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_PROGRESS_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    TURN_ID_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    category: VoiceEventCategory
    severity: VoiceEventSeverity
    component: VoicePipelineComponent
    user_said: UserSaidEvent
    assistant_token: AssistantTokenEvent
    audio: AudioFrameEvent
    vad: VADEvent
    interrupted: InterruptedEvent
    state: StateChangeEvent
    error: ErrorEvent
    metrics: MetricsEvent
    component_state_changed: VoiceAgentComponentStates
    session_error: VoiceSessionError
    session_started: SessionStartedEvent
    session_stopped: SessionStoppedEvent
    agent_response_started: AgentResponseStartedEvent
    agent_response_completed: AgentResponseCompletedEvent
    speech_turn_detection: SpeechTurnDetectionEvent
    turn_lifecycle: TurnLifecycleEvent
    wakeword_detected: WakeWordDetectedEvent
    audio_level: AudioLevelEvent
    component_progress: ComponentProgressEvent
    session_id: str
    turn_id: str
    request_id: str
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., category: _Optional[_Union[VoiceEventCategory, str]] = ..., severity: _Optional[_Union[VoiceEventSeverity, str]] = ..., component: _Optional[_Union[VoicePipelineComponent, str]] = ..., user_said: _Optional[_Union[UserSaidEvent, _Mapping]] = ..., assistant_token: _Optional[_Union[AssistantTokenEvent, _Mapping]] = ..., audio: _Optional[_Union[AudioFrameEvent, _Mapping]] = ..., vad: _Optional[_Union[VADEvent, _Mapping]] = ..., interrupted: _Optional[_Union[InterruptedEvent, _Mapping]] = ..., state: _Optional[_Union[StateChangeEvent, _Mapping]] = ..., error: _Optional[_Union[ErrorEvent, _Mapping]] = ..., metrics: _Optional[_Union[MetricsEvent, _Mapping]] = ..., component_state_changed: _Optional[_Union[VoiceAgentComponentStates, _Mapping]] = ..., session_error: _Optional[_Union[VoiceSessionError, _Mapping]] = ..., session_started: _Optional[_Union[SessionStartedEvent, _Mapping]] = ..., session_stopped: _Optional[_Union[SessionStoppedEvent, _Mapping]] = ..., agent_response_started: _Optional[_Union[AgentResponseStartedEvent, _Mapping]] = ..., agent_response_completed: _Optional[_Union[AgentResponseCompletedEvent, _Mapping]] = ..., speech_turn_detection: _Optional[_Union[SpeechTurnDetectionEvent, _Mapping]] = ..., turn_lifecycle: _Optional[_Union[TurnLifecycleEvent, _Mapping]] = ..., wakeword_detected: _Optional[_Union[WakeWordDetectedEvent, _Mapping]] = ..., audio_level: _Optional[_Union[AudioLevelEvent, _Mapping]] = ..., component_progress: _Optional[_Union[ComponentProgressEvent, _Mapping]] = ..., session_id: _Optional[str] = ..., turn_id: _Optional[str] = ..., request_id: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class UserSaidEvent(_message.Message):
    __slots__ = ("text", "is_final", "confidence", "audio_start_us", "audio_end_us", "language_code", "segment_index")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    AUDIO_START_US_FIELD_NUMBER: _ClassVar[int]
    AUDIO_END_US_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    SEGMENT_INDEX_FIELD_NUMBER: _ClassVar[int]
    text: str
    is_final: bool
    confidence: float
    audio_start_us: int
    audio_end_us: int
    language_code: str
    segment_index: int
    def __init__(self, text: _Optional[str] = ..., is_final: _Optional[bool] = ..., confidence: _Optional[float] = ..., audio_start_us: _Optional[int] = ..., audio_end_us: _Optional[int] = ..., language_code: _Optional[str] = ..., segment_index: _Optional[int] = ...) -> None: ...

class AssistantTokenEvent(_message.Message):
    __slots__ = ("text", "is_final", "kind", "token_id", "logprob", "finish_reason")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TOKEN_ID_FIELD_NUMBER: _ClassVar[int]
    LOGPROB_FIELD_NUMBER: _ClassVar[int]
    FINISH_REASON_FIELD_NUMBER: _ClassVar[int]
    text: str
    is_final: bool
    kind: TokenKind
    token_id: int
    logprob: float
    finish_reason: str
    def __init__(self, text: _Optional[str] = ..., is_final: _Optional[bool] = ..., kind: _Optional[_Union[TokenKind, str]] = ..., token_id: _Optional[int] = ..., logprob: _Optional[float] = ..., finish_reason: _Optional[str] = ...) -> None: ...

class AudioFrameEvent(_message.Message):
    __slots__ = ("pcm", "sample_rate_hz", "channels", "encoding", "is_final", "chunk_index", "duration_ms")
    PCM_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    ENCODING_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    CHUNK_INDEX_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    pcm: bytes
    sample_rate_hz: int
    channels: int
    encoding: AudioEncoding
    is_final: bool
    chunk_index: int
    duration_ms: int
    def __init__(self, pcm: _Optional[bytes] = ..., sample_rate_hz: _Optional[int] = ..., channels: _Optional[int] = ..., encoding: _Optional[_Union[AudioEncoding, str]] = ..., is_final: _Optional[bool] = ..., chunk_index: _Optional[int] = ..., duration_ms: _Optional[int] = ...) -> None: ...

class VADEvent(_message.Message):
    __slots__ = ("type", "frame_offset_us", "confidence", "is_speech", "speech_duration_ms", "silence_duration_ms", "noise_floor_db")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    FRAME_OFFSET_US_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    IS_SPEECH_FIELD_NUMBER: _ClassVar[int]
    SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    SILENCE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    NOISE_FLOOR_DB_FIELD_NUMBER: _ClassVar[int]
    type: VADEventType
    frame_offset_us: int
    confidence: float
    is_speech: bool
    speech_duration_ms: float
    silence_duration_ms: float
    noise_floor_db: float
    def __init__(self, type: _Optional[_Union[VADEventType, str]] = ..., frame_offset_us: _Optional[int] = ..., confidence: _Optional[float] = ..., is_speech: _Optional[bool] = ..., speech_duration_ms: _Optional[float] = ..., silence_duration_ms: _Optional[float] = ..., noise_floor_db: _Optional[float] = ...) -> None: ...

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
    __slots__ = ("code", "message", "component", "is_recoverable", "operation", "details_json")
    CODE_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_FIELD_NUMBER: _ClassVar[int]
    IS_RECOVERABLE_FIELD_NUMBER: _ClassVar[int]
    OPERATION_FIELD_NUMBER: _ClassVar[int]
    DETAILS_JSON_FIELD_NUMBER: _ClassVar[int]
    code: int
    message: str
    component: str
    is_recoverable: bool
    operation: str
    details_json: str
    def __init__(self, code: _Optional[int] = ..., message: _Optional[str] = ..., component: _Optional[str] = ..., is_recoverable: _Optional[bool] = ..., operation: _Optional[str] = ..., details_json: _Optional[str] = ...) -> None: ...

class MetricsEvent(_message.Message):
    __slots__ = ("stt_final_ms", "llm_first_token_ms", "tts_first_audio_ms", "end_to_end_ms", "tokens_generated", "audio_samples_played", "is_over_budget", "created_at_ns", "vad_first_speech_ms", "stt_first_partial_ms", "llm_total_ms", "tts_total_ms")
    STT_FINAL_MS_FIELD_NUMBER: _ClassVar[int]
    LLM_FIRST_TOKEN_MS_FIELD_NUMBER: _ClassVar[int]
    TTS_FIRST_AUDIO_MS_FIELD_NUMBER: _ClassVar[int]
    END_TO_END_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_GENERATED_FIELD_NUMBER: _ClassVar[int]
    AUDIO_SAMPLES_PLAYED_FIELD_NUMBER: _ClassVar[int]
    IS_OVER_BUDGET_FIELD_NUMBER: _ClassVar[int]
    CREATED_AT_NS_FIELD_NUMBER: _ClassVar[int]
    VAD_FIRST_SPEECH_MS_FIELD_NUMBER: _ClassVar[int]
    STT_FIRST_PARTIAL_MS_FIELD_NUMBER: _ClassVar[int]
    LLM_TOTAL_MS_FIELD_NUMBER: _ClassVar[int]
    TTS_TOTAL_MS_FIELD_NUMBER: _ClassVar[int]
    stt_final_ms: float
    llm_first_token_ms: float
    tts_first_audio_ms: float
    end_to_end_ms: float
    tokens_generated: int
    audio_samples_played: int
    is_over_budget: bool
    created_at_ns: int
    vad_first_speech_ms: float
    stt_first_partial_ms: float
    llm_total_ms: float
    tts_total_ms: float
    def __init__(self, stt_final_ms: _Optional[float] = ..., llm_first_token_ms: _Optional[float] = ..., tts_first_audio_ms: _Optional[float] = ..., end_to_end_ms: _Optional[float] = ..., tokens_generated: _Optional[int] = ..., audio_samples_played: _Optional[int] = ..., is_over_budget: _Optional[bool] = ..., created_at_ns: _Optional[int] = ..., vad_first_speech_ms: _Optional[float] = ..., stt_first_partial_ms: _Optional[float] = ..., llm_total_ms: _Optional[float] = ..., tts_total_ms: _Optional[float] = ...) -> None: ...

class AudioLevelEvent(_message.Message):
    __slots__ = ("rms", "peak", "noise_floor_db", "is_speech")
    RMS_FIELD_NUMBER: _ClassVar[int]
    PEAK_FIELD_NUMBER: _ClassVar[int]
    NOISE_FLOOR_DB_FIELD_NUMBER: _ClassVar[int]
    IS_SPEECH_FIELD_NUMBER: _ClassVar[int]
    rms: float
    peak: float
    noise_floor_db: float
    is_speech: bool
    def __init__(self, rms: _Optional[float] = ..., peak: _Optional[float] = ..., noise_floor_db: _Optional[float] = ..., is_speech: _Optional[bool] = ...) -> None: ...

class ComponentProgressEvent(_message.Message):
    __slots__ = ("component", "operation", "progress", "message")
    COMPONENT_FIELD_NUMBER: _ClassVar[int]
    OPERATION_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    component: VoicePipelineComponent
    operation: str
    progress: float
    message: str
    def __init__(self, component: _Optional[_Union[VoicePipelineComponent, str]] = ..., operation: _Optional[str] = ..., progress: _Optional[float] = ..., message: _Optional[str] = ...) -> None: ...

class VoiceAgentComponentStates(_message.Message):
    __slots__ = ("stt_state", "llm_state", "tts_state", "vad_state", "ready", "any_loading", "wakeword_state", "error_message")
    STT_STATE_FIELD_NUMBER: _ClassVar[int]
    LLM_STATE_FIELD_NUMBER: _ClassVar[int]
    TTS_STATE_FIELD_NUMBER: _ClassVar[int]
    VAD_STATE_FIELD_NUMBER: _ClassVar[int]
    READY_FIELD_NUMBER: _ClassVar[int]
    ANY_LOADING_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_STATE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    stt_state: ComponentLoadState
    llm_state: ComponentLoadState
    tts_state: ComponentLoadState
    vad_state: ComponentLoadState
    ready: bool
    any_loading: bool
    wakeword_state: ComponentLoadState
    error_message: str
    def __init__(self, stt_state: _Optional[_Union[ComponentLoadState, str]] = ..., llm_state: _Optional[_Union[ComponentLoadState, str]] = ..., tts_state: _Optional[_Union[ComponentLoadState, str]] = ..., vad_state: _Optional[_Union[ComponentLoadState, str]] = ..., ready: _Optional[bool] = ..., any_loading: _Optional[bool] = ..., wakeword_state: _Optional[_Union[ComponentLoadState, str]] = ..., error_message: _Optional[str] = ...) -> None: ...

class VoiceSessionError(_message.Message):
    __slots__ = ("code", "message", "failed_component", "c_abi_code", "recoverable")
    CODE_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    FAILED_COMPONENT_FIELD_NUMBER: _ClassVar[int]
    C_ABI_CODE_FIELD_NUMBER: _ClassVar[int]
    RECOVERABLE_FIELD_NUMBER: _ClassVar[int]
    code: VoiceSessionErrorCode
    message: str
    failed_component: str
    c_abi_code: int
    recoverable: bool
    def __init__(self, code: _Optional[_Union[VoiceSessionErrorCode, str]] = ..., message: _Optional[str] = ..., failed_component: _Optional[str] = ..., c_abi_code: _Optional[int] = ..., recoverable: _Optional[bool] = ...) -> None: ...

class SessionStartedEvent(_message.Message):
    __slots__ = ("session_id",)
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    session_id: str
    def __init__(self, session_id: _Optional[str] = ...) -> None: ...

class SessionStoppedEvent(_message.Message):
    __slots__ = ("session_id", "reason")
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    session_id: str
    reason: str
    def __init__(self, session_id: _Optional[str] = ..., reason: _Optional[str] = ...) -> None: ...

class AgentResponseStartedEvent(_message.Message):
    __slots__ = ("turn_id",)
    TURN_ID_FIELD_NUMBER: _ClassVar[int]
    turn_id: str
    def __init__(self, turn_id: _Optional[str] = ...) -> None: ...

class AgentResponseCompletedEvent(_message.Message):
    __slots__ = ("turn_id", "response_duration_ms")
    TURN_ID_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    turn_id: str
    response_duration_ms: int
    def __init__(self, turn_id: _Optional[str] = ..., response_duration_ms: _Optional[int] = ...) -> None: ...

class SpeechTurnDetectionEvent(_message.Message):
    __slots__ = ("kind", "speaker_id", "turn_start_us", "turn_end_us", "confidence", "speech_duration_ms", "silence_duration_ms")
    KIND_FIELD_NUMBER: _ClassVar[int]
    SPEAKER_ID_FIELD_NUMBER: _ClassVar[int]
    TURN_START_US_FIELD_NUMBER: _ClassVar[int]
    TURN_END_US_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    SPEECH_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    SILENCE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    kind: SpeechTurnDetectionEventKind
    speaker_id: str
    turn_start_us: int
    turn_end_us: int
    confidence: float
    speech_duration_ms: float
    silence_duration_ms: float
    def __init__(self, kind: _Optional[_Union[SpeechTurnDetectionEventKind, str]] = ..., speaker_id: _Optional[str] = ..., turn_start_us: _Optional[int] = ..., turn_end_us: _Optional[int] = ..., confidence: _Optional[float] = ..., speech_duration_ms: _Optional[float] = ..., silence_duration_ms: _Optional[float] = ...) -> None: ...

class TurnLifecycleEvent(_message.Message):
    __slots__ = ("kind", "turn_id", "session_id", "transcript", "response", "error", "started_at_ms", "completed_at_ms")
    KIND_FIELD_NUMBER: _ClassVar[int]
    TURN_ID_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    TRANSCRIPT_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    STARTED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    COMPLETED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    kind: TurnLifecycleEventKind
    turn_id: str
    session_id: str
    transcript: str
    response: str
    error: str
    started_at_ms: int
    completed_at_ms: int
    def __init__(self, kind: _Optional[_Union[TurnLifecycleEventKind, str]] = ..., turn_id: _Optional[str] = ..., session_id: _Optional[str] = ..., transcript: _Optional[str] = ..., response: _Optional[str] = ..., error: _Optional[str] = ..., started_at_ms: _Optional[int] = ..., completed_at_ms: _Optional[int] = ...) -> None: ...

class WakeWordDetectedEvent(_message.Message):
    __slots__ = ("wake_word", "confidence", "timestamp_ms", "model_id", "model_index", "duration_ms")
    WAKE_WORD_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_INDEX_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    wake_word: str
    confidence: float
    timestamp_ms: int
    model_id: str
    model_index: int
    duration_ms: int
    def __init__(self, wake_word: _Optional[str] = ..., confidence: _Optional[float] = ..., timestamp_ms: _Optional[int] = ..., model_id: _Optional[str] = ..., model_index: _Optional[int] = ..., duration_ms: _Optional[int] = ...) -> None: ...
