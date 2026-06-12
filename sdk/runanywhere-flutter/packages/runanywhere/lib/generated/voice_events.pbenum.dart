// This is a generated file - do not edit.
//
// Generated from voice_events.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class VoicePipelineComponent extends $pb.ProtobufEnum {
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_UNSPECIFIED =
      VoicePipelineComponent._(
          0, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_UNSPECIFIED');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_AGENT =
      VoicePipelineComponent._(
          1, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_AGENT');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_STT =
      VoicePipelineComponent._(
          2, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_STT');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_ASR =
      VoicePipelineComponent._(
          3, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_ASR');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_TTS =
      VoicePipelineComponent._(
          4, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_TTS');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_VAD =
      VoicePipelineComponent._(
          5, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_VAD');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_STD =
      VoicePipelineComponent._(
          6, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_STD');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_LLM =
      VoicePipelineComponent._(
          7, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_LLM');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_AUDIO =
      VoicePipelineComponent._(
          8, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_AUDIO');
  static const VoicePipelineComponent VOICE_PIPELINE_COMPONENT_WAKEWORD =
      VoicePipelineComponent._(
          9, _omitEnumNames ? '' : 'VOICE_PIPELINE_COMPONENT_WAKEWORD');

  static const $core.List<VoicePipelineComponent> values =
      <VoicePipelineComponent>[
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

  static final $core.List<VoicePipelineComponent?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 9);
  static VoicePipelineComponent? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VoicePipelineComponent._(super.value, super.name);
}

class TokenKind extends $pb.ProtobufEnum {
  static const TokenKind TOKEN_KIND_UNSPECIFIED =
      TokenKind._(0, _omitEnumNames ? '' : 'TOKEN_KIND_UNSPECIFIED');
  static const TokenKind TOKEN_KIND_ANSWER =
      TokenKind._(1, _omitEnumNames ? '' : 'TOKEN_KIND_ANSWER');
  static const TokenKind TOKEN_KIND_THOUGHT =
      TokenKind._(2, _omitEnumNames ? '' : 'TOKEN_KIND_THOUGHT');
  static const TokenKind TOKEN_KIND_TOOL_CALL =
      TokenKind._(3, _omitEnumNames ? '' : 'TOKEN_KIND_TOOL_CALL');

  static const $core.List<TokenKind> values = <TokenKind>[
    TOKEN_KIND_UNSPECIFIED,
    TOKEN_KIND_ANSWER,
    TOKEN_KIND_THOUGHT,
    TOKEN_KIND_TOOL_CALL,
  ];

  static final $core.List<TokenKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static TokenKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TokenKind._(super.value, super.name);
}

class AudioEncoding extends $pb.ProtobufEnum {
  static const AudioEncoding AUDIO_ENCODING_UNSPECIFIED =
      AudioEncoding._(0, _omitEnumNames ? '' : 'AUDIO_ENCODING_UNSPECIFIED');
  static const AudioEncoding AUDIO_ENCODING_PCM_F32_LE =
      AudioEncoding._(1, _omitEnumNames ? '' : 'AUDIO_ENCODING_PCM_F32_LE');
  static const AudioEncoding AUDIO_ENCODING_PCM_S16_LE =
      AudioEncoding._(2, _omitEnumNames ? '' : 'AUDIO_ENCODING_PCM_S16_LE');

  static const $core.List<AudioEncoding> values = <AudioEncoding>[
    AUDIO_ENCODING_UNSPECIFIED,
    AUDIO_ENCODING_PCM_F32_LE,
    AUDIO_ENCODING_PCM_S16_LE,
  ];

  static final $core.List<AudioEncoding?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static AudioEncoding? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AudioEncoding._(super.value, super.name);
}

class InterruptReason extends $pb.ProtobufEnum {
  static const InterruptReason INTERRUPT_REASON_UNSPECIFIED = InterruptReason._(
      0, _omitEnumNames ? '' : 'INTERRUPT_REASON_UNSPECIFIED');
  static const InterruptReason INTERRUPT_REASON_USER_BARGE_IN =
      InterruptReason._(
          1, _omitEnumNames ? '' : 'INTERRUPT_REASON_USER_BARGE_IN');
  static const InterruptReason INTERRUPT_REASON_APP_STOP =
      InterruptReason._(2, _omitEnumNames ? '' : 'INTERRUPT_REASON_APP_STOP');
  static const InterruptReason INTERRUPT_REASON_AUDIO_ROUTE_CHANGE =
      InterruptReason._(
          3, _omitEnumNames ? '' : 'INTERRUPT_REASON_AUDIO_ROUTE_CHANGE');
  static const InterruptReason INTERRUPT_REASON_TIMEOUT =
      InterruptReason._(4, _omitEnumNames ? '' : 'INTERRUPT_REASON_TIMEOUT');

  static const $core.List<InterruptReason> values = <InterruptReason>[
    INTERRUPT_REASON_UNSPECIFIED,
    INTERRUPT_REASON_USER_BARGE_IN,
    INTERRUPT_REASON_APP_STOP,
    INTERRUPT_REASON_AUDIO_ROUTE_CHANGE,
    INTERRUPT_REASON_TIMEOUT,
  ];

  static final $core.List<InterruptReason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static InterruptReason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const InterruptReason._(super.value, super.name);
}

class PipelineState extends $pb.ProtobufEnum {
  static const PipelineState PIPELINE_STATE_UNSPECIFIED =
      PipelineState._(0, _omitEnumNames ? '' : 'PIPELINE_STATE_UNSPECIFIED');
  static const PipelineState PIPELINE_STATE_IDLE =
      PipelineState._(1, _omitEnumNames ? '' : 'PIPELINE_STATE_IDLE');
  static const PipelineState PIPELINE_STATE_LISTENING =
      PipelineState._(2, _omitEnumNames ? '' : 'PIPELINE_STATE_LISTENING');
  static const PipelineState PIPELINE_STATE_THINKING =
      PipelineState._(3, _omitEnumNames ? '' : 'PIPELINE_STATE_THINKING');
  static const PipelineState PIPELINE_STATE_SPEAKING =
      PipelineState._(4, _omitEnumNames ? '' : 'PIPELINE_STATE_SPEAKING');
  static const PipelineState PIPELINE_STATE_STOPPED =
      PipelineState._(5, _omitEnumNames ? '' : 'PIPELINE_STATE_STOPPED');
  static const PipelineState PIPELINE_STATE_WAITING_WAKEWORD = PipelineState._(
      6, _omitEnumNames ? '' : 'PIPELINE_STATE_WAITING_WAKEWORD');
  static const PipelineState PIPELINE_STATE_PROCESSING_SPEECH = PipelineState._(
      7, _omitEnumNames ? '' : 'PIPELINE_STATE_PROCESSING_SPEECH');
  static const PipelineState PIPELINE_STATE_GENERATING_RESPONSE =
      PipelineState._(
          8, _omitEnumNames ? '' : 'PIPELINE_STATE_GENERATING_RESPONSE');
  static const PipelineState PIPELINE_STATE_PLAYING_TTS =
      PipelineState._(9, _omitEnumNames ? '' : 'PIPELINE_STATE_PLAYING_TTS');
  static const PipelineState PIPELINE_STATE_COOLDOWN =
      PipelineState._(10, _omitEnumNames ? '' : 'PIPELINE_STATE_COOLDOWN');
  static const PipelineState PIPELINE_STATE_ERROR =
      PipelineState._(11, _omitEnumNames ? '' : 'PIPELINE_STATE_ERROR');

  static const $core.List<PipelineState> values = <PipelineState>[
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

  static final $core.List<PipelineState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 11);
  static PipelineState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PipelineState._(super.value, super.name);
}

class SpeechTurnDetectionEventKind extends $pb.ProtobufEnum {
  static const SpeechTurnDetectionEventKind
      SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED =
      SpeechTurnDetectionEventKind._(0,
          _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED');
  static const SpeechTurnDetectionEventKind
      SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED =
      SpeechTurnDetectionEventKind._(
          1,
          _omitEnumNames
              ? ''
              : 'SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED');
  static const SpeechTurnDetectionEventKind
      SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED =
      SpeechTurnDetectionEventKind._(2,
          _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED');
  static const SpeechTurnDetectionEventKind
      SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED =
      SpeechTurnDetectionEventKind._(
          3,
          _omitEnumNames
              ? ''
              : 'SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED');
  static const SpeechTurnDetectionEventKind
      SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS =
      SpeechTurnDetectionEventKind._(4,
          _omitEnumNames ? '' : 'SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS');

  static const $core.List<SpeechTurnDetectionEventKind> values =
      <SpeechTurnDetectionEventKind>[
    SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED,
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED,
    SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED,
    SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED,
    SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS,
  ];

  static final $core.List<SpeechTurnDetectionEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static SpeechTurnDetectionEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SpeechTurnDetectionEventKind._(super.value, super.name);
}

class TurnLifecycleEventKind extends $pb.ProtobufEnum {
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED =
      TurnLifecycleEventKind._(
          0, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_STARTED =
      TurnLifecycleEventKind._(
          1, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_STARTED');
  static const TurnLifecycleEventKind
      TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED = TurnLifecycleEventKind._(
          2,
          _omitEnumNames
              ? ''
              : 'TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED');
  static const TurnLifecycleEventKind
      TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED = TurnLifecycleEventKind._(3,
          _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED');
  static const TurnLifecycleEventKind
      TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL = TurnLifecycleEventKind._(
          4,
          _omitEnumNames
              ? ''
              : 'TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL');
  static const TurnLifecycleEventKind
      TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED =
      TurnLifecycleEventKind._(
          5,
          _omitEnumNames
              ? ''
              : 'TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED');
  static const TurnLifecycleEventKind
      TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED =
      TurnLifecycleEventKind._(
          6,
          _omitEnumNames
              ? ''
              : 'TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_COMPLETED =
      TurnLifecycleEventKind._(
          7, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_COMPLETED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_CANCELLED =
      TurnLifecycleEventKind._(
          8, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_CANCELLED');
  static const TurnLifecycleEventKind TURN_LIFECYCLE_EVENT_KIND_FAILED =
      TurnLifecycleEventKind._(
          9, _omitEnumNames ? '' : 'TURN_LIFECYCLE_EVENT_KIND_FAILED');

  static const $core.List<TurnLifecycleEventKind> values =
      <TurnLifecycleEventKind>[
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

  static final $core.List<TurnLifecycleEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 9);
  static TurnLifecycleEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TurnLifecycleEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
