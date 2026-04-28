///
//  Generated code. Do not modify.
//  source: voice_events.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class TokenKind extends $pb.ProtobufEnum {
  static const TokenKind TOKEN_KIND_UNSPECIFIED = TokenKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOKEN_KIND_UNSPECIFIED');
  static const TokenKind TOKEN_KIND_ANSWER = TokenKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOKEN_KIND_ANSWER');
  static const TokenKind TOKEN_KIND_THOUGHT = TokenKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOKEN_KIND_THOUGHT');
  static const TokenKind TOKEN_KIND_TOOL_CALL = TokenKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOKEN_KIND_TOOL_CALL');

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
  static const AudioEncoding AUDIO_ENCODING_UNSPECIFIED = AudioEncoding._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_ENCODING_UNSPECIFIED');
  static const AudioEncoding AUDIO_ENCODING_PCM_F32_LE = AudioEncoding._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_ENCODING_PCM_F32_LE');
  static const AudioEncoding AUDIO_ENCODING_PCM_S16_LE = AudioEncoding._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_ENCODING_PCM_S16_LE');

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
  static const VADEventType VAD_EVENT_UNSPECIFIED = VADEventType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VAD_EVENT_UNSPECIFIED');
  static const VADEventType VAD_EVENT_VOICE_START = VADEventType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VAD_EVENT_VOICE_START');
  static const VADEventType VAD_EVENT_VOICE_END_OF_UTTERANCE = VADEventType._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VAD_EVENT_VOICE_END_OF_UTTERANCE');
  static const VADEventType VAD_EVENT_BARGE_IN = VADEventType._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VAD_EVENT_BARGE_IN');
  static const VADEventType VAD_EVENT_SILENCE = VADEventType._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VAD_EVENT_SILENCE');

  static const $core.List<VADEventType> values = <VADEventType> [
    VAD_EVENT_UNSPECIFIED,
    VAD_EVENT_VOICE_START,
    VAD_EVENT_VOICE_END_OF_UTTERANCE,
    VAD_EVENT_BARGE_IN,
    VAD_EVENT_SILENCE,
  ];

  static final $core.Map<$core.int, VADEventType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VADEventType? valueOf($core.int value) => _byValue[value];

  const VADEventType._($core.int v, $core.String n) : super(v, n);
}

class InterruptReason extends $pb.ProtobufEnum {
  static const InterruptReason INTERRUPT_REASON_UNSPECIFIED = InterruptReason._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INTERRUPT_REASON_UNSPECIFIED');
  static const InterruptReason INTERRUPT_REASON_USER_BARGE_IN = InterruptReason._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INTERRUPT_REASON_USER_BARGE_IN');
  static const InterruptReason INTERRUPT_REASON_APP_STOP = InterruptReason._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INTERRUPT_REASON_APP_STOP');
  static const InterruptReason INTERRUPT_REASON_AUDIO_ROUTE_CHANGE = InterruptReason._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INTERRUPT_REASON_AUDIO_ROUTE_CHANGE');
  static const InterruptReason INTERRUPT_REASON_TIMEOUT = InterruptReason._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INTERRUPT_REASON_TIMEOUT');

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
  static const PipelineState PIPELINE_STATE_UNSPECIFIED = PipelineState._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PIPELINE_STATE_UNSPECIFIED');
  static const PipelineState PIPELINE_STATE_IDLE = PipelineState._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PIPELINE_STATE_IDLE');
  static const PipelineState PIPELINE_STATE_LISTENING = PipelineState._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PIPELINE_STATE_LISTENING');
  static const PipelineState PIPELINE_STATE_THINKING = PipelineState._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PIPELINE_STATE_THINKING');
  static const PipelineState PIPELINE_STATE_SPEAKING = PipelineState._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PIPELINE_STATE_SPEAKING');
  static const PipelineState PIPELINE_STATE_STOPPED = PipelineState._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PIPELINE_STATE_STOPPED');

  static const $core.List<PipelineState> values = <PipelineState> [
    PIPELINE_STATE_UNSPECIFIED,
    PIPELINE_STATE_IDLE,
    PIPELINE_STATE_LISTENING,
    PIPELINE_STATE_THINKING,
    PIPELINE_STATE_SPEAKING,
    PIPELINE_STATE_STOPPED,
  ];

  static final $core.Map<$core.int, PipelineState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PipelineState? valueOf($core.int value) => _byValue[value];

  const PipelineState._($core.int v, $core.String n) : super(v, n);
}

class ComponentLoadState extends $pb.ProtobufEnum {
  static const ComponentLoadState COMPONENT_LOAD_STATE_UNSPECIFIED = ComponentLoadState._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_LOAD_STATE_UNSPECIFIED');
  static const ComponentLoadState COMPONENT_LOAD_STATE_NOT_LOADED = ComponentLoadState._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_LOAD_STATE_NOT_LOADED');
  static const ComponentLoadState COMPONENT_LOAD_STATE_LOADING = ComponentLoadState._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_LOAD_STATE_LOADING');
  static const ComponentLoadState COMPONENT_LOAD_STATE_LOADED = ComponentLoadState._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_LOAD_STATE_LOADED');
  static const ComponentLoadState COMPONENT_LOAD_STATE_ERROR = ComponentLoadState._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_LOAD_STATE_ERROR');

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
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_UNSPECIFIED = VoiceSessionErrorCode._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_SESSION_ERROR_CODE_UNSPECIFIED');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED = VoiceSessionErrorCode._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_NOT_READY = VoiceSessionErrorCode._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_SESSION_ERROR_CODE_NOT_READY');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING = VoiceSessionErrorCode._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING');
  static const VoiceSessionErrorCode VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE = VoiceSessionErrorCode._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE');

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

