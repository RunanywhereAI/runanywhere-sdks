//
//  Generated code. Do not modify.
//  source: voice_events.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class VoiceEventCategory extends $pb.ProtobufEnum {
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_UNSPECIFIED = VoiceEventCategory._(0, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_UNSPECIFIED');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_VOICE_AGENT = VoiceEventCategory._(1, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_VOICE_AGENT');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_STT = VoiceEventCategory._(2, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_STT');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_ASR = VoiceEventCategory._(3, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_ASR');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_TTS = VoiceEventCategory._(4, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_TTS');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_VAD = VoiceEventCategory._(5, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_VAD');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_STD = VoiceEventCategory._(6, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_STD');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_LLM = VoiceEventCategory._(7, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_LLM');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_AUDIO = VoiceEventCategory._(8, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_AUDIO');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_METRICS = VoiceEventCategory._(9, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_METRICS');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_ERROR = VoiceEventCategory._(10, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_ERROR');
  static const VoiceEventCategory VOICE_EVENT_CATEGORY_WAKEWORD = VoiceEventCategory._(11, _omitEnumNames ? '' : 'VOICE_EVENT_CATEGORY_WAKEWORD');

  static const $core.List<VoiceEventCategory> values = <VoiceEventCategory> [
    VOICE_EVENT_CATEGORY_UNSPECIFIED,
    VOICE_EVENT_CATEGORY_VOICE_AGENT,
    VOICE_EVENT_CATEGORY_STT,
    VOICE_EVENT_CATEGORY_ASR,
    VOICE_EVENT_CATEGORY_TTS,
    VOICE_EVENT_CATEGORY_VAD,
    VOICE_EVENT_CATEGORY_STD,
    VOICE_EVENT_CATEGORY_LLM,
    VOICE_EVENT_CATEGORY_AUDIO,
    VOICE_EVENT_CATEGORY_METRICS,
    VOICE_EVENT_CATEGORY_ERROR,
    VOICE_EVENT_CATEGORY_WAKEWORD,
  ];

  static final $core.Map<$core.int, VoiceEventCategory> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VoiceEventCategory? valueOf($core.int value) => _byValue[value];

  const VoiceEventCategory._($core.int v, $core.String n) : super(v, n);
}

class VoiceEventSeverity extends $pb.ProtobufEnum {
  static const VoiceEventSeverity VOICE_EVENT_SEVERITY_DEBUG = VoiceEventSeverity._(0, _omitEnumNames ? '' : 'VOICE_EVENT_SEVERITY_DEBUG');
  static const VoiceEventSeverity VOICE_EVENT_SEVERITY_INFO = VoiceEventSeverity._(1, _omitEnumNames ? '' : 'VOICE_EVENT_SEVERITY_INFO');
  static const VoiceEventSeverity VOICE_EVENT_SEVERITY_WARNING = VoiceEventSeverity._(2, _omitEnumNames ? '' : 'VOICE_EVENT_SEVERITY_WARNING');
  static const VoiceEventSeverity VOICE_EVENT_SEVERITY_ERROR = VoiceEventSeverity._(3, _omitEnumNames ? '' : 'VOICE_EVENT_SEVERITY_ERROR');
  static const VoiceEventSeverity VOICE_EVENT_SEVERITY_CRITICAL = VoiceEventSeverity._(4, _omitEnumNames ? '' : 'VOICE_EVENT_SEVERITY_CRITICAL');

  static const $core.List<VoiceEventSeverity> values = <VoiceEventSeverity> [
    VOICE_EVENT_SEVERITY_DEBUG,
    VOICE_EVENT_SEVERITY_INFO,
    VOICE_EVENT_SEVERITY_WARNING,
    VOICE_EVENT_SEVERITY_ERROR,
    VOICE_EVENT_SEVERITY_CRITICAL,
  ];

  static final $core.Map<$core.int, VoiceEventSeverity> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VoiceEventSeverity? valueOf($core.int value) => _byValue[value];

  const VoiceEventSeverity._($core.int v, $core.String n) : super(v, n);
}

class VoicePipelineComponent extends $pb.ProtobufEnum {
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_UNSPECIFIED = VoicePipelineComponent._(0, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_UNSPECIFIED');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_AGENT = VoicePipelineComponent._(1, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_AGENT');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_STT = VoicePipelineComponent._(2, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_STT');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_ASR = VoicePipelineComponent._(3, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_ASR');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_TTS = VoicePipelineComponent._(4, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_TTS');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_VAD = VoicePipelineComponent._(5, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_VAD');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_STD = VoicePipelineComponent._(6, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_STD');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_LLM = VoicePipelineComponent._(7, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_LLM');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_AUDIO = VoicePipelineComponent._(8, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_AUDIO');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_WAKEWORD = VoicePipelineComponent._(9, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_WAKEWORD');

  static const $core.List<VoicePipelineComponent> values = <VoicePipelineComponent> [
    VOICE_PIPELINE_COMPONENT_UNSPECIFIED,
    VOICE_PIPELINE_COMPONENT_AGENT,
    VOICE_PIPELINE_COMPONENT_STT,
    VOICE_PIPELINE_COMPONENT_ASR,
    VOICE_PIPELINE_COMPONENT_TTS,
    VOICE_PIPELINE_COMPONENT_VAD,
    VOICE_PIPELINE_COMPONENT_STD,
    VOICE_PIPELINE_COMPONENT_LLM,
    VOICE_PIPELINE_COMPONENT_AUDIO,
    VOICE_PIPELINE_COMPONENT_WAKEWORD,
  ];

  static final $core.Map<$core.int, VoicePipelineComponent> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VoicePipelineComponent? valueOf($core.int value) => _byValue[value];

  const VoicePipelineComponent._($core.int v, $core.String n) : super(v, n);
}

class TokenKind extends $pb.ProtobufEnum {
  static const TokenKind TOKEN_KIND_UNSPECIFIED = TokenKind._(0, _omitEnumNames ? '' : 'TOKEN_KIND_UNSPECIFIED');
  static const TokenKind TOKEN_KIND_ANSWER = TokenKind._(1, _omitEnumNames ? '' : 'TOKEN_KIND_ANSWER');
  static const TokenKind TOKEN_KIND_THOUGHT = TokenKind._(2, _omitEnumNames ? '' : 'TOKEN_KIND_THOUGHT');
  static const TokenKind TOKEN_KIND_TOOL_CALL = TokenKind._(3, _omitEnumNames ? '' : 'TOKEN_KIND_TOOL_CALL');

  static const $core.List<TokenKind> values = <TokenKind> [
    TOKEN_KIND_UNSPECIFIED,
    TOKEN_KIND_ANSWER,
    TOKEN_KIND_THOUGHT,
    TOKEN_KIND_TOOL_CALL,
  ];

  static final $core.Map<$core.int, TokenKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TokenKind? valueOf($core.int value) => _byValue[value];

  const TokenKind._($core.int v, $core.String n) : super(v, n);
}

class AudioEncoding extends $pb.ProtobufEnum {
  static const AudioEncoding AUDIO_ENCODING_UNSPECIFIED = AudioEncoding._(0, _omitEnumNames ? '' : 'AUDIO_ENCODING_UNSPECIFIED');
  static const AudioEncoding AUDIO_ENCODING_PCM_F32_LE = AudioEncoding._(1, _omitEnumNames ? '' : 'AUDIO_ENCODING_PCM_F32_LE');
  static const AudioEncoding AUDIO_ENCODING_PCM_S16_LE = AudioEncoding._(2, _omitEnumNames ? '' : 'AUDIO_ENCODING_PCM_S16_LE');

  static const $core.List<AudioEncoding> values = <AudioEncoding> [
    AUDIO_ENCODING_UNSPECIFIED,
    AUDIO_ENCODING_PCM_F32_LE,
    AUDIO_ENCODING_PCM_S16_LE,
  ];

  static final $core.Map<$core.int, AudioEncoding> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AudioEncoding? valueOf($core.int value) => _byValue[value];

  const AudioEncoding._($core.int v, $core.String n) : super(v, n);
}

class VADEventType extends $pb.ProtobufEnum {
  static const VADEventType VAD_EVENT_UNSPECIFIED = VADEventType._(0, _omitEnumNames ? '' : 'VAD_EVENT_UNSPECIFIED');
  static const VADEventType VAD_EVENT_VOICE_START = VADEventType._(1, _omitEnumNames ? '' : 'VAD_EVENT_VOICE_START');
  static const VADEventType VAD_EVENT_VOICE_END_OF_UTTERANCE = VADEventType._(2, _omitEnumNames ? '' : 'VAD_EVENT_VOICE_END_OF_UTTERANCE');
  static const VADEventType VAD_EVENT_BARGE_IN = VADEventType._(3, _omitEnumNames ? '' : 'VAD_EVENT_BARGE_IN');
  static const VADEventType VAD_EVENT_SILENCE = VADEventType._(4, _omitEnumNames ? '' : 'VAD_EVENT_SILENCE');
  static const VADEventType VAD_EVENT_STATISTICS = VADEventType._(5, _omitEnumNames ? '' : 'VAD_EVENT_STATISTICS');
  static const VADEventType VAD_EVENT_STATE_CHANGED = VADEventType._(6, _omitEnumNames ? '' : 'VAD_EVENT_STATE_CHANGED');

  static const $core.List<VADEventType> values = <VADEventType> [
    VAD_EVENT_UNSPECIFIED,
    VAD_EVENT_VOICE_START,
    VAD_EVENT_VOICE_END_OF_UTTERANCE,
    VAD_EVENT_BARGE_IN,
    VAD_EVENT_SILENCE,
    VAD_EVENT_STATISTICS,
    VAD_EVENT_STATE_CHANGED,
  ];

  static final $core.Map<$core.int, VADEventType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VADEventType? valueOf($core.int value) => _byValue[value];

  const VADEventType._($core.int v, $core.String n) : super(v, n);
}

class InterruptReason extends $pb.ProtobufEnum {
  static const InterruptReason INTERRUPT_REASON_UNSPECIFIED = InterruptReason._(0, _omitEnumNames ? '' : 'INTERRUPT_REASON_UNSPECIFIED');
  static const InterruptReason INTERRUPT_REASON_USER_BARGE_IN = InterruptReason._(1, _omitEnumNames ? '' : 'INTERRUPT_REASON_USER_BARGE_IN');
  static const InterruptReason INTERRUPT_REASON_APP_STOP = InterruptReason._(2, _omitEnumNames ? '' : 'INTERRUPT_REASON_APP_STOP');
  static const InterruptReason INTERRUPT_REASON_AUDIO_ROUTE_CHANGE = InterruptReason._(3, _omitEnumNames ? '' : 'INTERRUPT_REASON_AUDIO_ROUTE_CHANGE');
  static const InterruptReason INTERRUPT_REASON_TIMEOUT = InterruptReason._(4, _omitEnumNames ? '' : 'INTERRUPT_REASON_TIMEOUT');

  static const $core.List<InterruptReason> values = <InterruptReason> [
    INTERRUPT_REASON_UNSPECIFIED,
    INTERRUPT_REASON_USER_BARGE_IN,
    INTERRUPT_REASON_APP_STOP,
    INTERRUPT_REASON_AUDIO_ROUTE_CHANGE,
    INTERRUPT_REASON_TIMEOUT,
  ];

  static final $core.Map<$core.int, InterruptReason> _byValue = $pb.ProtobufEnum.initByValue(values);
  static InterruptReason? valueOf($core.int value) => _byValue[value];

  const InterruptReason._($core.int v, $core.String n) : super(v, n);
}

class PipelineState extends $pb.ProtobufEnum {
  static const PipelineState PIPELINE_STATE_UNSPECIFIED = PipelineState._(0, _omitEnumNames ? '' : 'PIPELINE_STATE_UNSPECIFIED');
  static const PipelineState PIPELINE_STATE_IDLE = PipelineState._(1, _omitEnumNames ? '' : 'PIPELINE_STATE_IDLE');
  static const PipelineState PIPELINE_STATE_LISTENING = PipelineState._(2, _omitEnumNames ? '' : 'PIPELINE_STATE_LISTENING');
  static const PipelineState PIPELINE_STATE_THINKING = PipelineState._(3, _omitEnumNames ? '' : 'PIPELINE_STATE_THINKING');
  static const PipelineState PIPELINE_STATE_SPEAKING = PipelineState._(4, _omitEnumNames ? '' : 'PIPELINE_STATE_SPEAKING');
  static const PipelineState PIPELINE_STATE_STOPPED = PipelineState._(5, _omitEnumNames ? '' : 'PIPELINE_STATE_STOPPED');
  static const PipelineState PIPELINE_STATE_WAITING_WAKEWORD = PipelineState._(6, _omitEnumNames ? '' : 'PIPELINE_STATE_WAITING_WAKEWORD');
  static const PipelineState PIPELINE_STATE_PROCESSING_SPEECH = PipelineState._(7, _omitEnumNames ? '' : 'PIPELINE_STATE_PROCESSING_SPEECH');
  static const PipelineState PIPELINE_STATE_GENERATING_RESPONSE = PipelineState._(8, _omitEnumNames ? '' : 'PIPELINE_STATE_GENERATING_RESPONSE');
  static const PipelineState PIPELINE_STATE_PLAYING_TTS = PipelineState._(9, _omitEnumNames ? '' : 'PIPELINE_STATE_PLAYING_TTS');
  static const PipelineState PIPELINE_STATE_COOLDOWN = PipelineState._(10, _omitEnumNames ? '' : 'PIPELINE_STATE_COOLDOWN');
  static const PipelineState PIPELINE_STATE_ERROR = PipelineState._(11, _omitEnumNames ? '' : 'PIPELINE_STATE_ERROR');

  static const $core.List<PipelineState> values = <PipelineState> [
    PIPELINE_STATE_UNSPECIFIED,
    PIPELINE_STATE_IDLE,
    PIPELINE_STATE_LISTENING,
    PIPELINE_STATE_THINKING,
    PIPELINE_STATE_SPEAKING,
    PIPELINE_STATE_STOPPED,
    PIPELINE_STATE_WAITING_WAKEWORD,
    PIPELINE_STATE_PROCESSING_SPEECH,
    PIPELINE_STATE_GENERATING_RESPONSE,
    PIPELINE_STATE_PLAYING_TTS,
    PIPELINE_STATE_COOLDOWN,
    PIPELINE_STATE_ERROR,
  ];

  static final $core.Map<$core.int, PipelineState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PipelineState? valueOf($core.int value) => _byValue[value];

  const PipelineState._($core.int v, $core.String n) : super(v, n);
}

/// Loading state of a single voice-agent component (STT, LLM, TTS, VAD).
/// UNSPECIFIED preserves proto3 zero-value semantics — frontends MUST treat it
/// the same as NOT_LOADED for forward-compatibility.
class ComponentLoadState extends $pb.ProtobufEnum {
  static const ComponentLoadState COMPONENT_LOAD_STATE_UNSPECIFIED = ComponentLoadState._(0, _omitEnumNames ? '' : 'COMPONENT_LOAD_STATE_UNSPECIFIED');
  static const ComponentLoadState COMPONENT_LOAD_STATE_NOT_LOADED = ComponentLoadState._(1, _omitEnumNames ? '' : 'COMPONENT_LOAD_STATE_NOT_LOADED');
  static const ComponentLoadState COMPONENT_LOAD_STATE_LOADING = ComponentLoadState._(2, _omitEnumNames ? '' : 'COMPONENT_LOAD_STATE_LOADING');
  static const ComponentLoadState COMPONENT_LOAD_STATE_LOADED = ComponentLoadState._(3, _omitEnumNames ? '' : 'COMPONENT_LOAD_STATE_LOADED');
  static const ComponentLoadState COMPONENT_LOAD_STATE_ERROR = ComponentLoadState._(4, _omitEnumNames ? '' : 'COMPONENT_LOAD_STATE_ERROR');

  static const $core.List<ComponentLoadState> values = <ComponentLoadState> [
    COMPONENT_LOAD_STATE_UNSPECIFIED,
    COMPONENT_LOAD_STATE_NOT_LOADED,
    COMPONENT_LOAD_STATE_LOADING,
    COMPONENT_LOAD_STATE_LOADED,
    COMPONENT_LOAD_STATE_ERROR,
  ];

  static final $core.Map<$core.int, ComponentLoadState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ComponentLoadState? valueOf($core.int value) => _byValue[value];

  const ComponentLoadState._($core.int v, $core.String n) : super(v, n);
}

class VoiceSessionErrorCode extends $pb.ProtobufEnum {
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_UNSPECIFIED = VoiceSessionErrorCode._(0, _omitEnumNames ? '' : 'VOICE_SESSION_ERROR_CODE_UNSPECIFIED');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED = VoiceSessionErrorCode._(1, _omitEnumNames ? '' : 'VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_NOT_READY = VoiceSessionErrorCode._(2, _omitEnumNames ? '' : 'VOICE_SESSION_ERROR_CODE_NOT_READY');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING = VoiceSessionErrorCode._(3, _omitEnumNames ? '' : 'VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE = VoiceSessionErrorCode._(4, _omitEnumNames ? '' : 'VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE');

  static const $core.List<VoiceSessionErrorCode> values = <VoiceSessionErrorCode> [
    VOICE_SESSION_ERROR_CODE_UNSPECIFIED,
    VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED,
    VOICE_SESSION_ERROR_CODE_NOT_READY,
    VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING,
    VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE,
  ];

  static final $core.Map<$core.int, VoiceSessionErrorCode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VoiceSessionErrorCode? valueOf($core.int value) => _byValue[value];

  const VoiceSessionErrorCode._($core.int v, $core.String n) : super(v, n);
}

class SpeechTurnDetectionEventKind extends $pb.ProtobufEnum {
  static const SpeechTurnDetectionEventKind SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED = SpeechTurnDetectionEventKind._(0, _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED');
  static const SpeechTurnDetectionEventKind SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED = SpeechTurnDetectionEventKind._(1, _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED');
  static const SpeechTurnDetectionEventKind SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED = SpeechTurnDetectionEventKind._(2, _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED');
  static const SpeechTurnDetectionEventKind SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED = SpeechTurnDetectionEventKind._(3, _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED');
  static const SpeechTurnDetectionEventKind SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS = SpeechTurnDetectionEventKind._(4, _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS');

  static const $core.List<SpeechTurnDetectionEventKind> values = <SpeechTurnDetectionEventKind> [
    SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED,
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED,
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED,
    SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED,
    SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS,
  ];

  static final $core.Map<$core.int, SpeechTurnDetectionEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static SpeechTurnDetectionEventKind? valueOf($core.int value) => _byValue[value];

  const SpeechTurnDetectionEventKind._($core.int v, $core.String n) : super(v, n);
}

class TurnLifecycleEventKind extends $pb.ProtobufEnum {
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED = TurnLifecycleEventKind._(0, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_STARTED = TurnLifecycleEventKind._(1, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_STARTED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED = TurnLifecycleEventKind._(2, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED = TurnLifecycleEventKind._(3, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL = TurnLifecycleEventKind._(4, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED = TurnLifecycleEventKind._(5, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED = TurnLifecycleEventKind._(6, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_COMPLETED = TurnLifecycleEventKind._(7, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_COMPLETED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_CANCELLED = TurnLifecycleEventKind._(8, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_CANCELLED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_FAILED = TurnLifecycleEventKind._(9, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_FAILED');

  static const $core.List<TurnLifecycleEventKind> values = <TurnLifecycleEventKind> [
    TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED,
    TURN_LIFECYCLE_EVENT_KIND_STARTED,
    TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED,
    TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED,
    TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL,
    TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED,
    TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED,
    TURN_LIFECYCLE_EVENT_KIND_COMPLETED,
    TURN_LIFECYCLE_EVENT_KIND_CANCELLED,
    TURN_LIFECYCLE_EVENT_KIND_FAILED,
  ];

  static final $core.Map<$core.int, TurnLifecycleEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TurnLifecycleEventKind? valueOf($core.int value) => _byValue[value];

  const TurnLifecycleEventKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
