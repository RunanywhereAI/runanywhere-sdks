import voice_events_pb2 as _voice_events_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class VoiceAgentRequest(_message.Message):
    __slots__ = ("event_filter", "session_id", "categories", "min_severity", "replay_from_seq", "include_audio")
    EVENT_FILTER_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    CATEGORIES_FIELD_NUMBER: _ClassVar[int]
    MIN_SEVERITY_FIELD_NUMBER: _ClassVar[int]
    REPLAY_FROM_SEQ_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_AUDIO_FIELD_NUMBER: _ClassVar[int]
    event_filter: str
    session_id: str
    categories: _containers.RepeatedScalarFieldContainer[_voice_events_pb2.VoiceEventCategory]
    min_severity: _voice_events_pb2.VoiceEventSeverity
    replay_from_seq: int
    include_audio: bool
    def __init__(self, event_filter: _Optional[str] = ..., session_id: _Optional[str] = ..., categories: _Optional[_Iterable[_Union[_voice_events_pb2.VoiceEventCategory, str]]] = ..., min_severity: _Optional[_Union[_voice_events_pb2.VoiceEventSeverity, str]] = ..., replay_from_seq: _Optional[int] = ..., include_audio: _Optional[bool] = ...) -> None: ...

class VoiceAgentResult(_message.Message):
    __slots__ = ("speech_detected", "transcription", "assistant_response", "thinking_content", "synthesized_audio", "final_state", "synthesized_audio_sample_rate_hz", "synthesized_audio_channels", "synthesized_audio_encoding", "session_id", "turn_id", "stt_time_ms", "llm_time_ms", "tts_time_ms", "total_time_ms", "error_message", "error_code")
    SPEECH_DETECTED_FIELD_NUMBER: _ClassVar[int]
    TRANSCRIPTION_FIELD_NUMBER: _ClassVar[int]
    ASSISTANT_RESPONSE_FIELD_NUMBER: _ClassVar[int]
    THINKING_CONTENT_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_FIELD_NUMBER: _ClassVar[int]
    FINAL_STATE_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_ENCODING_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    TURN_ID_FIELD_NUMBER: _ClassVar[int]
    STT_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    LLM_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TTS_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    speech_detected: bool
    transcription: str
    assistant_response: str
    thinking_content: str
    synthesized_audio: bytes
    final_state: _voice_events_pb2.VoiceAgentComponentStates
    synthesized_audio_sample_rate_hz: int
    synthesized_audio_channels: int
    synthesized_audio_encoding: _voice_events_pb2.AudioEncoding
    session_id: str
    turn_id: str
    stt_time_ms: int
    llm_time_ms: int
    tts_time_ms: int
    total_time_ms: int
    error_message: str
    error_code: int
    def __init__(self, speech_detected: _Optional[bool] = ..., transcription: _Optional[str] = ..., assistant_response: _Optional[str] = ..., thinking_content: _Optional[str] = ..., synthesized_audio: _Optional[bytes] = ..., final_state: _Optional[_Union[_voice_events_pb2.VoiceAgentComponentStates, _Mapping]] = ..., synthesized_audio_sample_rate_hz: _Optional[int] = ..., synthesized_audio_channels: _Optional[int] = ..., synthesized_audio_encoding: _Optional[_Union[_voice_events_pb2.AudioEncoding, str]] = ..., session_id: _Optional[str] = ..., turn_id: _Optional[str] = ..., stt_time_ms: _Optional[int] = ..., llm_time_ms: _Optional[int] = ..., tts_time_ms: _Optional[int] = ..., total_time_ms: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class VoiceAgentTurnRequest(_message.Message):
    __slots__ = ("request_id", "session_id", "audio_data", "sample_rate_hz", "channels", "encoding", "session_config", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    AUDIO_DATA_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    ENCODING_FIELD_NUMBER: _ClassVar[int]
    SESSION_CONFIG_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    session_id: str
    audio_data: bytes
    sample_rate_hz: int
    channels: int
    encoding: _voice_events_pb2.AudioEncoding
    session_config: VoiceSessionConfig
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., session_id: _Optional[str] = ..., audio_data: _Optional[bytes] = ..., sample_rate_hz: _Optional[int] = ..., channels: _Optional[int] = ..., encoding: _Optional[_Union[_voice_events_pb2.AudioEncoding, str]] = ..., session_config: _Optional[_Union[VoiceSessionConfig, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class VoiceSessionConfig(_message.Message):
    __slots__ = ("silence_duration_ms", "speech_threshold", "auto_play_tts", "continuous_mode", "thinking_mode_enabled", "max_tokens", "max_recording_duration_ms", "language_code", "voice_id")
    SILENCE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    SPEECH_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    AUTO_PLAY_TTS_FIELD_NUMBER: _ClassVar[int]
    CONTINUOUS_MODE_FIELD_NUMBER: _ClassVar[int]
    THINKING_MODE_ENABLED_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    MAX_RECORDING_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    VOICE_ID_FIELD_NUMBER: _ClassVar[int]
    silence_duration_ms: int
    speech_threshold: float
    auto_play_tts: bool
    continuous_mode: bool
    thinking_mode_enabled: bool
    max_tokens: int
    max_recording_duration_ms: int
    language_code: str
    voice_id: str
    def __init__(self, silence_duration_ms: _Optional[int] = ..., speech_threshold: _Optional[float] = ..., auto_play_tts: _Optional[bool] = ..., continuous_mode: _Optional[bool] = ..., thinking_mode_enabled: _Optional[bool] = ..., max_tokens: _Optional[int] = ..., max_recording_duration_ms: _Optional[int] = ..., language_code: _Optional[str] = ..., voice_id: _Optional[str] = ...) -> None: ...

class AudioPipelineConfig(_message.Message):
    __slots__ = ("cooldown_duration_ms", "strict_transitions", "max_tts_duration_ms")
    COOLDOWN_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    STRICT_TRANSITIONS_FIELD_NUMBER: _ClassVar[int]
    MAX_TTS_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    cooldown_duration_ms: int
    strict_transitions: bool
    max_tts_duration_ms: int
    def __init__(self, cooldown_duration_ms: _Optional[int] = ..., strict_transitions: _Optional[bool] = ..., max_tts_duration_ms: _Optional[int] = ...) -> None: ...

class VoiceAgentComposeConfig(_message.Message):
    __slots__ = ("stt_model_path", "stt_model_id", "stt_model_name", "llm_model_path", "llm_model_id", "llm_model_name", "tts_voice_path", "tts_voice_id", "tts_voice_name", "vad_sample_rate", "vad_frame_length", "vad_energy_threshold", "wakeword_enabled", "wakeword_model_path", "wakeword_model_id", "wakeword_phrase", "wakeword_threshold", "wakeword_embedding_model_path", "wakeword_vad_model_path", "session_config", "audio_pipeline_config", "session_id", "default_language_code")
    STT_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    STT_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    STT_MODEL_NAME_FIELD_NUMBER: _ClassVar[int]
    LLM_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    LLM_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    LLM_MODEL_NAME_FIELD_NUMBER: _ClassVar[int]
    TTS_VOICE_PATH_FIELD_NUMBER: _ClassVar[int]
    TTS_VOICE_ID_FIELD_NUMBER: _ClassVar[int]
    TTS_VOICE_NAME_FIELD_NUMBER: _ClassVar[int]
    VAD_SAMPLE_RATE_FIELD_NUMBER: _ClassVar[int]
    VAD_FRAME_LENGTH_FIELD_NUMBER: _ClassVar[int]
    VAD_ENERGY_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_ENABLED_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_PHRASE_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_EMBEDDING_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    WAKEWORD_VAD_MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    SESSION_CONFIG_FIELD_NUMBER: _ClassVar[int]
    AUDIO_PIPELINE_CONFIG_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_LANGUAGE_CODE_FIELD_NUMBER: _ClassVar[int]
    stt_model_path: str
    stt_model_id: str
    stt_model_name: str
    llm_model_path: str
    llm_model_id: str
    llm_model_name: str
    tts_voice_path: str
    tts_voice_id: str
    tts_voice_name: str
    vad_sample_rate: int
    vad_frame_length: float
    vad_energy_threshold: float
    wakeword_enabled: bool
    wakeword_model_path: str
    wakeword_model_id: str
    wakeword_phrase: str
    wakeword_threshold: float
    wakeword_embedding_model_path: str
    wakeword_vad_model_path: str
    session_config: VoiceSessionConfig
    audio_pipeline_config: AudioPipelineConfig
    session_id: str
    default_language_code: str
    def __init__(self, stt_model_path: _Optional[str] = ..., stt_model_id: _Optional[str] = ..., stt_model_name: _Optional[str] = ..., llm_model_path: _Optional[str] = ..., llm_model_id: _Optional[str] = ..., llm_model_name: _Optional[str] = ..., tts_voice_path: _Optional[str] = ..., tts_voice_id: _Optional[str] = ..., tts_voice_name: _Optional[str] = ..., vad_sample_rate: _Optional[int] = ..., vad_frame_length: _Optional[float] = ..., vad_energy_threshold: _Optional[float] = ..., wakeword_enabled: _Optional[bool] = ..., wakeword_model_path: _Optional[str] = ..., wakeword_model_id: _Optional[str] = ..., wakeword_phrase: _Optional[str] = ..., wakeword_threshold: _Optional[float] = ..., wakeword_embedding_model_path: _Optional[str] = ..., wakeword_vad_model_path: _Optional[str] = ..., session_config: _Optional[_Union[VoiceSessionConfig, _Mapping]] = ..., audio_pipeline_config: _Optional[_Union[AudioPipelineConfig, _Mapping]] = ..., session_id: _Optional[str] = ..., default_language_code: _Optional[str] = ...) -> None: ...
