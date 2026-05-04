import voice_events_pb2 as _voice_events_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class VoiceAgentRequest(_message.Message):
    __slots__ = ("event_filter",)
    EVENT_FILTER_FIELD_NUMBER: _ClassVar[int]
    event_filter: str
    def __init__(self, event_filter: _Optional[str] = ...) -> None: ...

class VoiceAgentResult(_message.Message):
    __slots__ = ("speech_detected", "transcription", "assistant_response", "thinking_content", "synthesized_audio", "final_state", "synthesized_audio_sample_rate_hz", "synthesized_audio_channels", "synthesized_audio_encoding")
    SPEECH_DETECTED_FIELD_NUMBER: _ClassVar[int]
    TRANSCRIPTION_FIELD_NUMBER: _ClassVar[int]
    ASSISTANT_RESPONSE_FIELD_NUMBER: _ClassVar[int]
    THINKING_CONTENT_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_FIELD_NUMBER: _ClassVar[int]
    FINAL_STATE_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    SYNTHESIZED_AUDIO_ENCODING_FIELD_NUMBER: _ClassVar[int]
    speech_detected: bool
    transcription: str
    assistant_response: str
    thinking_content: str
    synthesized_audio: bytes
    final_state: _voice_events_pb2.VoiceAgentComponentStates
    synthesized_audio_sample_rate_hz: int
    synthesized_audio_channels: int
    synthesized_audio_encoding: _voice_events_pb2.AudioEncoding
    def __init__(self, speech_detected: _Optional[bool] = ..., transcription: _Optional[str] = ..., assistant_response: _Optional[str] = ..., thinking_content: _Optional[str] = ..., synthesized_audio: _Optional[bytes] = ..., final_state: _Optional[_Union[_voice_events_pb2.VoiceAgentComponentStates, _Mapping]] = ..., synthesized_audio_sample_rate_hz: _Optional[int] = ..., synthesized_audio_channels: _Optional[int] = ..., synthesized_audio_encoding: _Optional[_Union[_voice_events_pb2.AudioEncoding, str]] = ...) -> None: ...

class VoiceSessionConfig(_message.Message):
    __slots__ = ("silence_duration_ms", "speech_threshold", "auto_play_tts", "continuous_mode", "thinking_mode_enabled", "max_tokens")
    SILENCE_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    SPEECH_THRESHOLD_FIELD_NUMBER: _ClassVar[int]
    AUTO_PLAY_TTS_FIELD_NUMBER: _ClassVar[int]
    CONTINUOUS_MODE_FIELD_NUMBER: _ClassVar[int]
    THINKING_MODE_ENABLED_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    silence_duration_ms: int
    speech_threshold: float
    auto_play_tts: bool
    continuous_mode: bool
    thinking_mode_enabled: bool
    max_tokens: int
    def __init__(self, silence_duration_ms: _Optional[int] = ..., speech_threshold: _Optional[float] = ..., auto_play_tts: _Optional[bool] = ..., continuous_mode: _Optional[bool] = ..., thinking_mode_enabled: _Optional[bool] = ..., max_tokens: _Optional[int] = ...) -> None: ...

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
    __slots__ = ("stt_model_path", "stt_model_id", "stt_model_name", "llm_model_path", "llm_model_id", "llm_model_name", "tts_voice_path", "tts_voice_id", "tts_voice_name", "vad_sample_rate", "vad_frame_length", "vad_energy_threshold", "wakeword_enabled", "wakeword_model_path", "wakeword_model_id", "wakeword_phrase", "wakeword_threshold", "wakeword_embedding_model_path", "wakeword_vad_model_path", "session_config", "audio_pipeline_config")
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
    def __init__(self, stt_model_path: _Optional[str] = ..., stt_model_id: _Optional[str] = ..., stt_model_name: _Optional[str] = ..., llm_model_path: _Optional[str] = ..., llm_model_id: _Optional[str] = ..., llm_model_name: _Optional[str] = ..., tts_voice_path: _Optional[str] = ..., tts_voice_id: _Optional[str] = ..., tts_voice_name: _Optional[str] = ..., vad_sample_rate: _Optional[int] = ..., vad_frame_length: _Optional[float] = ..., vad_energy_threshold: _Optional[float] = ..., wakeword_enabled: _Optional[bool] = ..., wakeword_model_path: _Optional[str] = ..., wakeword_model_id: _Optional[str] = ..., wakeword_phrase: _Optional[str] = ..., wakeword_threshold: _Optional[float] = ..., wakeword_embedding_model_path: _Optional[str] = ..., wakeword_vad_model_path: _Optional[str] = ..., session_config: _Optional[_Union[VoiceSessionConfig, _Mapping]] = ..., audio_pipeline_config: _Optional[_Union[AudioPipelineConfig, _Mapping]] = ...) -> None: ...
