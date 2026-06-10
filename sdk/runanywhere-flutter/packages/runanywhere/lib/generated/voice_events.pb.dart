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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'component_types.pbenum.dart' as $0;
import 'errors.pbenum.dart' as $1;
import 'vad_options.pbenum.dart' as $2;
import 'voice_events.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'voice_events.pbenum.dart';

enum VoiceEvent_Payload {
  userSaid,
  assistantToken,
  audio,
  vad,
  interrupted,
  state,
  error,
  metrics,
  componentStateChanged,
  sessionError,
  sessionStarted,
  sessionStopped,
  agentResponseStarted,
  agentResponseCompleted,
  speechTurnDetection,
  turnLifecycle,
  wakewordDetected,
  audioLevel,
  componentProgress,
  notSet
}

/// ---------------------------------------------------------------------------
/// Sum type emitted on the output edge of the VoiceAgent pipeline.
/// ---------------------------------------------------------------------------
class VoiceEvent extends $pb.GeneratedMessage {
  factory VoiceEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $0.EventCategory? category,
    $1.ErrorSeverity? severity,
    VoicePipelineComponent? component,
    UserSaidEvent? userSaid,
    AssistantTokenEvent? assistantToken,
    AudioFrameEvent? audio,
    VADEvent? vad,
    InterruptedEvent? interrupted,
    StateChangeEvent? state,
    ErrorEvent? error,
    MetricsEvent? metrics,
    VoiceAgentComponentStates? componentStateChanged,
    VoiceSessionError? sessionError,
    SessionStartedEvent? sessionStarted,
    SessionStoppedEvent? sessionStopped,
    AgentResponseStartedEvent? agentResponseStarted,
    AgentResponseCompletedEvent? agentResponseCompleted,
    SpeechTurnDetectionEvent? speechTurnDetection,
    TurnLifecycleEvent? turnLifecycle,
    WakeWordDetectedEvent? wakewordDetected,
    AudioLevelEvent? audioLevel,
    ComponentProgressEvent? componentProgress,
    $core.String? sessionId,
    $core.String? turnId,
    $core.String? requestId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (seq != null) result.seq = seq;
    if (timestampUs != null) result.timestampUs = timestampUs;
    if (category != null) result.category = category;
    if (severity != null) result.severity = severity;
    if (component != null) result.component = component;
    if (userSaid != null) result.userSaid = userSaid;
    if (assistantToken != null) result.assistantToken = assistantToken;
    if (audio != null) result.audio = audio;
    if (vad != null) result.vad = vad;
    if (interrupted != null) result.interrupted = interrupted;
    if (state != null) result.state = state;
    if (error != null) result.error = error;
    if (metrics != null) result.metrics = metrics;
    if (componentStateChanged != null)
      result.componentStateChanged = componentStateChanged;
    if (sessionError != null) result.sessionError = sessionError;
    if (sessionStarted != null) result.sessionStarted = sessionStarted;
    if (sessionStopped != null) result.sessionStopped = sessionStopped;
    if (agentResponseStarted != null)
      result.agentResponseStarted = agentResponseStarted;
    if (agentResponseCompleted != null)
      result.agentResponseCompleted = agentResponseCompleted;
    if (speechTurnDetection != null)
      result.speechTurnDetection = speechTurnDetection;
    if (turnLifecycle != null) result.turnLifecycle = turnLifecycle;
    if (wakewordDetected != null) result.wakewordDetected = wakewordDetected;
    if (audioLevel != null) result.audioLevel = audioLevel;
    if (componentProgress != null) result.componentProgress = componentProgress;
    if (sessionId != null) result.sessionId = sessionId;
    if (turnId != null) result.turnId = turnId;
    if (requestId != null) result.requestId = requestId;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  VoiceEvent._();

  factory VoiceEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, VoiceEvent_Payload>
      _VoiceEvent_PayloadByTag = {
    10: VoiceEvent_Payload.userSaid,
    11: VoiceEvent_Payload.assistantToken,
    12: VoiceEvent_Payload.audio,
    13: VoiceEvent_Payload.vad,
    14: VoiceEvent_Payload.interrupted,
    15: VoiceEvent_Payload.state,
    16: VoiceEvent_Payload.error,
    17: VoiceEvent_Payload.metrics,
    18: VoiceEvent_Payload.componentStateChanged,
    19: VoiceEvent_Payload.sessionError,
    20: VoiceEvent_Payload.sessionStarted,
    21: VoiceEvent_Payload.sessionStopped,
    22: VoiceEvent_Payload.agentResponseStarted,
    23: VoiceEvent_Payload.agentResponseCompleted,
    24: VoiceEvent_Payload.speechTurnDetection,
    25: VoiceEvent_Payload.turnLifecycle,
    26: VoiceEvent_Payload.wakewordDetected,
    27: VoiceEvent_Payload.audioLevel,
    28: VoiceEvent_Payload.componentProgress,
    0: VoiceEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28
    ])
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aE<$0.EventCategory>(3, _omitFieldNames ? '' : 'category',
        enumValues: $0.EventCategory.values)
    ..aE<$1.ErrorSeverity>(4, _omitFieldNames ? '' : 'severity',
        enumValues: $1.ErrorSeverity.values)
    ..aE<VoicePipelineComponent>(5, _omitFieldNames ? '' : 'component',
        enumValues: VoicePipelineComponent.values)
    ..aOM<UserSaidEvent>(10, _omitFieldNames ? '' : 'userSaid',
        subBuilder: UserSaidEvent.create)
    ..aOM<AssistantTokenEvent>(11, _omitFieldNames ? '' : 'assistantToken',
        subBuilder: AssistantTokenEvent.create)
    ..aOM<AudioFrameEvent>(12, _omitFieldNames ? '' : 'audio',
        subBuilder: AudioFrameEvent.create)
    ..aOM<VADEvent>(13, _omitFieldNames ? '' : 'vad',
        subBuilder: VADEvent.create)
    ..aOM<InterruptedEvent>(14, _omitFieldNames ? '' : 'interrupted',
        subBuilder: InterruptedEvent.create)
    ..aOM<StateChangeEvent>(15, _omitFieldNames ? '' : 'state',
        subBuilder: StateChangeEvent.create)
    ..aOM<ErrorEvent>(16, _omitFieldNames ? '' : 'error',
        subBuilder: ErrorEvent.create)
    ..aOM<MetricsEvent>(17, _omitFieldNames ? '' : 'metrics',
        subBuilder: MetricsEvent.create)
    ..aOM<VoiceAgentComponentStates>(
        18, _omitFieldNames ? '' : 'componentStateChanged',
        subBuilder: VoiceAgentComponentStates.create)
    ..aOM<VoiceSessionError>(19, _omitFieldNames ? '' : 'sessionError',
        subBuilder: VoiceSessionError.create)
    ..aOM<SessionStartedEvent>(20, _omitFieldNames ? '' : 'sessionStarted',
        subBuilder: SessionStartedEvent.create)
    ..aOM<SessionStoppedEvent>(21, _omitFieldNames ? '' : 'sessionStopped',
        subBuilder: SessionStoppedEvent.create)
    ..aOM<AgentResponseStartedEvent>(
        22, _omitFieldNames ? '' : 'agentResponseStarted',
        subBuilder: AgentResponseStartedEvent.create)
    ..aOM<AgentResponseCompletedEvent>(
        23, _omitFieldNames ? '' : 'agentResponseCompleted',
        subBuilder: AgentResponseCompletedEvent.create)
    ..aOM<SpeechTurnDetectionEvent>(
        24, _omitFieldNames ? '' : 'speechTurnDetection',
        subBuilder: SpeechTurnDetectionEvent.create)
    ..aOM<TurnLifecycleEvent>(25, _omitFieldNames ? '' : 'turnLifecycle',
        subBuilder: TurnLifecycleEvent.create)
    ..aOM<WakeWordDetectedEvent>(26, _omitFieldNames ? '' : 'wakewordDetected',
        subBuilder: WakeWordDetectedEvent.create)
    ..aOM<AudioLevelEvent>(27, _omitFieldNames ? '' : 'audioLevel',
        subBuilder: AudioLevelEvent.create)
    ..aOM<ComponentProgressEvent>(
        28, _omitFieldNames ? '' : 'componentProgress',
        subBuilder: ComponentProgressEvent.create)
    ..aOS(30, _omitFieldNames ? '' : 'sessionId')
    ..aOS(31, _omitFieldNames ? '' : 'turnId')
    ..aOS(32, _omitFieldNames ? '' : 'requestId')
    ..m<$core.String, $core.String>(33, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'VoiceEvent.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceEvent copyWith(void Function(VoiceEvent) updates) =>
      super.copyWith((message) => updates(message as VoiceEvent)) as VoiceEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceEvent create() => VoiceEvent._();
  @$core.override
  VoiceEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceEvent>(create);
  static VoiceEvent? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  VoiceEvent_Payload whichPayload() =>
      _VoiceEvent_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  void clearPayload() => $_clearField($_whichOneof(0));

  /// Monotonic pipeline-local sequence number. Useful for frontends that
  /// need to detect gaps after reconnection or out-of-order delivery.
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  /// Wall-clock timestamp captured at the C++ edge, in microseconds since
  /// Unix epoch. Frontends may re-timestamp for UI display.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.EventCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category($0.EventCategory value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => $_clearField(3);

  @$pb.TagNumber(4)
  $1.ErrorSeverity get severity => $_getN(3);
  @$pb.TagNumber(4)
  set severity($1.ErrorSeverity value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSeverity() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeverity() => $_clearField(4);

  @$pb.TagNumber(5)
  VoicePipelineComponent get component => $_getN(4);
  @$pb.TagNumber(5)
  set component(VoicePipelineComponent value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasComponent() => $_has(4);
  @$pb.TagNumber(5)
  void clearComponent() => $_clearField(5);

  @$pb.TagNumber(10)
  UserSaidEvent get userSaid => $_getN(5);
  @$pb.TagNumber(10)
  set userSaid(UserSaidEvent value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasUserSaid() => $_has(5);
  @$pb.TagNumber(10)
  void clearUserSaid() => $_clearField(10);
  @$pb.TagNumber(10)
  UserSaidEvent ensureUserSaid() => $_ensure(5);

  @$pb.TagNumber(11)
  AssistantTokenEvent get assistantToken => $_getN(6);
  @$pb.TagNumber(11)
  set assistantToken(AssistantTokenEvent value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasAssistantToken() => $_has(6);
  @$pb.TagNumber(11)
  void clearAssistantToken() => $_clearField(11);
  @$pb.TagNumber(11)
  AssistantTokenEvent ensureAssistantToken() => $_ensure(6);

  @$pb.TagNumber(12)
  AudioFrameEvent get audio => $_getN(7);
  @$pb.TagNumber(12)
  set audio(AudioFrameEvent value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasAudio() => $_has(7);
  @$pb.TagNumber(12)
  void clearAudio() => $_clearField(12);
  @$pb.TagNumber(12)
  AudioFrameEvent ensureAudio() => $_ensure(7);

  @$pb.TagNumber(13)
  VADEvent get vad => $_getN(8);
  @$pb.TagNumber(13)
  set vad(VADEvent value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasVad() => $_has(8);
  @$pb.TagNumber(13)
  void clearVad() => $_clearField(13);
  @$pb.TagNumber(13)
  VADEvent ensureVad() => $_ensure(8);

  @$pb.TagNumber(14)
  InterruptedEvent get interrupted => $_getN(9);
  @$pb.TagNumber(14)
  set interrupted(InterruptedEvent value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasInterrupted() => $_has(9);
  @$pb.TagNumber(14)
  void clearInterrupted() => $_clearField(14);
  @$pb.TagNumber(14)
  InterruptedEvent ensureInterrupted() => $_ensure(9);

  @$pb.TagNumber(15)
  StateChangeEvent get state => $_getN(10);
  @$pb.TagNumber(15)
  set state(StateChangeEvent value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasState() => $_has(10);
  @$pb.TagNumber(15)
  void clearState() => $_clearField(15);
  @$pb.TagNumber(15)
  StateChangeEvent ensureState() => $_ensure(10);

  @$pb.TagNumber(16)
  ErrorEvent get error => $_getN(11);
  @$pb.TagNumber(16)
  set error(ErrorEvent value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasError() => $_has(11);
  @$pb.TagNumber(16)
  void clearError() => $_clearField(16);
  @$pb.TagNumber(16)
  ErrorEvent ensureError() => $_ensure(11);

  @$pb.TagNumber(17)
  MetricsEvent get metrics => $_getN(12);
  @$pb.TagNumber(17)
  set metrics(MetricsEvent value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasMetrics() => $_has(12);
  @$pb.TagNumber(17)
  void clearMetrics() => $_clearField(17);
  @$pb.TagNumber(17)
  MetricsEvent ensureMetrics() => $_ensure(12);

  /// Voice agent lifecycle events. Mirror Swift VoiceSessionError /
  /// VoiceAgentComponentStates and the AsyncSequence-style lifecycle
  /// signals consumed by the cross-platform VoiceAgent extensions
  /// (Swift VoiceAgentTypes.swift, Kotlin VoiceAgentTypes.kt, RN
  /// VoiceAgentTypes.ts, Web VoiceAgentCTypes.ts, Flutter
  /// voice_agent_types.dart).
  @$pb.TagNumber(18)
  VoiceAgentComponentStates get componentStateChanged => $_getN(13);
  @$pb.TagNumber(18)
  set componentStateChanged(VoiceAgentComponentStates value) =>
      $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasComponentStateChanged() => $_has(13);
  @$pb.TagNumber(18)
  void clearComponentStateChanged() => $_clearField(18);
  @$pb.TagNumber(18)
  VoiceAgentComponentStates ensureComponentStateChanged() => $_ensure(13);

  @$pb.TagNumber(19)
  VoiceSessionError get sessionError => $_getN(14);
  @$pb.TagNumber(19)
  set sessionError(VoiceSessionError value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasSessionError() => $_has(14);
  @$pb.TagNumber(19)
  void clearSessionError() => $_clearField(19);
  @$pb.TagNumber(19)
  VoiceSessionError ensureSessionError() => $_ensure(14);

  @$pb.TagNumber(20)
  SessionStartedEvent get sessionStarted => $_getN(15);
  @$pb.TagNumber(20)
  set sessionStarted(SessionStartedEvent value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasSessionStarted() => $_has(15);
  @$pb.TagNumber(20)
  void clearSessionStarted() => $_clearField(20);
  @$pb.TagNumber(20)
  SessionStartedEvent ensureSessionStarted() => $_ensure(15);

  @$pb.TagNumber(21)
  SessionStoppedEvent get sessionStopped => $_getN(16);
  @$pb.TagNumber(21)
  set sessionStopped(SessionStoppedEvent value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasSessionStopped() => $_has(16);
  @$pb.TagNumber(21)
  void clearSessionStopped() => $_clearField(21);
  @$pb.TagNumber(21)
  SessionStoppedEvent ensureSessionStopped() => $_ensure(16);

  @$pb.TagNumber(22)
  AgentResponseStartedEvent get agentResponseStarted => $_getN(17);
  @$pb.TagNumber(22)
  set agentResponseStarted(AgentResponseStartedEvent value) =>
      $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasAgentResponseStarted() => $_has(17);
  @$pb.TagNumber(22)
  void clearAgentResponseStarted() => $_clearField(22);
  @$pb.TagNumber(22)
  AgentResponseStartedEvent ensureAgentResponseStarted() => $_ensure(17);

  @$pb.TagNumber(23)
  AgentResponseCompletedEvent get agentResponseCompleted => $_getN(18);
  @$pb.TagNumber(23)
  set agentResponseCompleted(AgentResponseCompletedEvent value) =>
      $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasAgentResponseCompleted() => $_has(18);
  @$pb.TagNumber(23)
  void clearAgentResponseCompleted() => $_clearField(23);
  @$pb.TagNumber(23)
  AgentResponseCompletedEvent ensureAgentResponseCompleted() => $_ensure(18);

  @$pb.TagNumber(24)
  SpeechTurnDetectionEvent get speechTurnDetection => $_getN(19);
  @$pb.TagNumber(24)
  set speechTurnDetection(SpeechTurnDetectionEvent value) =>
      $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasSpeechTurnDetection() => $_has(19);
  @$pb.TagNumber(24)
  void clearSpeechTurnDetection() => $_clearField(24);
  @$pb.TagNumber(24)
  SpeechTurnDetectionEvent ensureSpeechTurnDetection() => $_ensure(19);

  @$pb.TagNumber(25)
  TurnLifecycleEvent get turnLifecycle => $_getN(20);
  @$pb.TagNumber(25)
  set turnLifecycle(TurnLifecycleEvent value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasTurnLifecycle() => $_has(20);
  @$pb.TagNumber(25)
  void clearTurnLifecycle() => $_clearField(25);
  @$pb.TagNumber(25)
  TurnLifecycleEvent ensureTurnLifecycle() => $_ensure(20);

  @$pb.TagNumber(26)
  WakeWordDetectedEvent get wakewordDetected => $_getN(21);
  @$pb.TagNumber(26)
  set wakewordDetected(WakeWordDetectedEvent value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasWakewordDetected() => $_has(21);
  @$pb.TagNumber(26)
  void clearWakewordDetected() => $_clearField(26);
  @$pb.TagNumber(26)
  WakeWordDetectedEvent ensureWakewordDetected() => $_ensure(21);

  @$pb.TagNumber(27)
  AudioLevelEvent get audioLevel => $_getN(22);
  @$pb.TagNumber(27)
  set audioLevel(AudioLevelEvent value) => $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasAudioLevel() => $_has(22);
  @$pb.TagNumber(27)
  void clearAudioLevel() => $_clearField(27);
  @$pb.TagNumber(27)
  AudioLevelEvent ensureAudioLevel() => $_ensure(22);

  @$pb.TagNumber(28)
  ComponentProgressEvent get componentProgress => $_getN(23);
  @$pb.TagNumber(28)
  set componentProgress(ComponentProgressEvent value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasComponentProgress() => $_has(23);
  @$pb.TagNumber(28)
  void clearComponentProgress() => $_clearField(28);
  @$pb.TagNumber(28)
  ComponentProgressEvent ensureComponentProgress() => $_ensure(23);

  /// Correlation fields shared by streaming and one-shot voice turns.
  @$pb.TagNumber(30)
  $core.String get sessionId => $_getSZ(24);
  @$pb.TagNumber(30)
  set sessionId($core.String value) => $_setString(24, value);
  @$pb.TagNumber(30)
  $core.bool hasSessionId() => $_has(24);
  @$pb.TagNumber(30)
  void clearSessionId() => $_clearField(30);

  @$pb.TagNumber(31)
  $core.String get turnId => $_getSZ(25);
  @$pb.TagNumber(31)
  set turnId($core.String value) => $_setString(25, value);
  @$pb.TagNumber(31)
  $core.bool hasTurnId() => $_has(25);
  @$pb.TagNumber(31)
  void clearTurnId() => $_clearField(31);

  @$pb.TagNumber(32)
  $core.String get requestId => $_getSZ(26);
  @$pb.TagNumber(32)
  set requestId($core.String value) => $_setString(26, value);
  @$pb.TagNumber(32)
  $core.bool hasRequestId() => $_has(26);
  @$pb.TagNumber(32)
  void clearRequestId() => $_clearField(32);

  @$pb.TagNumber(33)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(27);
}

/// User speech finalized by STT (is_final=false → partial hypothesis).
class UserSaidEvent extends $pb.GeneratedMessage {
  factory UserSaidEvent({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? confidence,
    $fixnum.Int64? audioStartUs,
    $fixnum.Int64? audioEndUs,
    $core.String? languageCode,
    $core.int? segmentIndex,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (isFinal != null) result.isFinal = isFinal;
    if (confidence != null) result.confidence = confidence;
    if (audioStartUs != null) result.audioStartUs = audioStartUs;
    if (audioEndUs != null) result.audioEndUs = audioEndUs;
    if (languageCode != null) result.languageCode = languageCode;
    if (segmentIndex != null) result.segmentIndex = segmentIndex;
    return result;
  }

  UserSaidEvent._();

  factory UserSaidEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UserSaidEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserSaidEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..aD(3, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aInt64(4, _omitFieldNames ? '' : 'audioStartUs')
    ..aInt64(5, _omitFieldNames ? '' : 'audioEndUs')
    ..aOS(6, _omitFieldNames ? '' : 'languageCode')
    ..aI(7, _omitFieldNames ? '' : 'segmentIndex')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserSaidEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserSaidEvent copyWith(void Function(UserSaidEvent) updates) =>
      super.copyWith((message) => updates(message as UserSaidEvent))
          as UserSaidEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UserSaidEvent create() => UserSaidEvent._();
  @$core.override
  UserSaidEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UserSaidEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UserSaidEvent>(create);
  static UserSaidEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get confidence => $_getN(2);
  @$pb.TagNumber(3)
  set confidence($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfidence() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfidence() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get audioStartUs => $_getI64(3);
  @$pb.TagNumber(4)
  set audioStartUs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAudioStartUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearAudioStartUs() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get audioEndUs => $_getI64(4);
  @$pb.TagNumber(5)
  set audioEndUs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAudioEndUs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioEndUs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get languageCode => $_getSZ(5);
  @$pb.TagNumber(6)
  set languageCode($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLanguageCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearLanguageCode() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get segmentIndex => $_getIZ(6);
  @$pb.TagNumber(7)
  set segmentIndex($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSegmentIndex() => $_has(6);
  @$pb.TagNumber(7)
  void clearSegmentIndex() => $_clearField(7);
}

/// Single token decoded by the LLM. is_final=true on the last token of a
/// response (end-of-stream marker).
class AssistantTokenEvent extends $pb.GeneratedMessage {
  factory AssistantTokenEvent({
    $core.String? text,
    $core.bool? isFinal,
    TokenKind? kind,
    $core.int? tokenId,
    $core.double? logprob,
    $core.String? finishReason,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (isFinal != null) result.isFinal = isFinal;
    if (kind != null) result.kind = kind;
    if (tokenId != null) result.tokenId = tokenId;
    if (logprob != null) result.logprob = logprob;
    if (finishReason != null) result.finishReason = finishReason;
    return result;
  }

  AssistantTokenEvent._();

  factory AssistantTokenEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AssistantTokenEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AssistantTokenEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..aE<TokenKind>(3, _omitFieldNames ? '' : 'kind',
        enumValues: TokenKind.values)
    ..aI(4, _omitFieldNames ? '' : 'tokenId', fieldType: $pb.PbFieldType.OU3)
    ..aD(5, _omitFieldNames ? '' : 'logprob', fieldType: $pb.PbFieldType.OF)
    ..aOS(6, _omitFieldNames ? '' : 'finishReason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssistantTokenEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssistantTokenEvent copyWith(void Function(AssistantTokenEvent) updates) =>
      super.copyWith((message) => updates(message as AssistantTokenEvent))
          as AssistantTokenEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AssistantTokenEvent create() => AssistantTokenEvent._();
  @$core.override
  AssistantTokenEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AssistantTokenEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AssistantTokenEvent>(create);
  static AssistantTokenEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => $_clearField(2);

  @$pb.TagNumber(3)
  TokenKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(TokenKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get tokenId => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokenId($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTokenId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokenId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get logprob => $_getN(4);
  @$pb.TagNumber(5)
  set logprob($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLogprob() => $_has(4);
  @$pb.TagNumber(5)
  void clearLogprob() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get finishReason => $_getSZ(5);
  @$pb.TagNumber(6)
  set finishReason($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFinishReason() => $_has(5);
  @$pb.TagNumber(6)
  void clearFinishReason() => $_clearField(6);
}

/// A chunk of synthesized PCM audio, ready for the sink. The frontend is
/// expected to copy the bytes out; the C ABI does NOT retain ownership.
class AudioFrameEvent extends $pb.GeneratedMessage {
  factory AudioFrameEvent({
    $core.List<$core.int>? pcm,
    $core.int? sampleRateHz,
    $core.int? channels,
    AudioEncoding? encoding,
    $core.bool? isFinal,
    $core.int? chunkIndex,
    $fixnum.Int64? durationMs,
  }) {
    final result = create();
    if (pcm != null) result.pcm = pcm;
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (channels != null) result.channels = channels;
    if (encoding != null) result.encoding = encoding;
    if (isFinal != null) result.isFinal = isFinal;
    if (chunkIndex != null) result.chunkIndex = chunkIndex;
    if (durationMs != null) result.durationMs = durationMs;
    return result;
  }

  AudioFrameEvent._();

  factory AudioFrameEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioFrameEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioFrameEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'pcm', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'sampleRateHz')
    ..aI(3, _omitFieldNames ? '' : 'channels')
    ..aE<AudioEncoding>(4, _omitFieldNames ? '' : 'encoding',
        enumValues: AudioEncoding.values)
    ..aOB(5, _omitFieldNames ? '' : 'isFinal')
    ..aI(6, _omitFieldNames ? '' : 'chunkIndex')
    ..aInt64(7, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFrameEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioFrameEvent copyWith(void Function(AudioFrameEvent) updates) =>
      super.copyWith((message) => updates(message as AudioFrameEvent))
          as AudioFrameEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioFrameEvent create() => AudioFrameEvent._();
  @$core.override
  AudioFrameEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioFrameEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioFrameEvent>(create);
  static AudioFrameEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pcm => $_getN(0);
  @$pb.TagNumber(1)
  set pcm($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPcm() => $_has(0);
  @$pb.TagNumber(1)
  void clearPcm() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRateHz => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRateHz($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSampleRateHz() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRateHz() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get channels => $_getIZ(2);
  @$pb.TagNumber(3)
  set channels($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChannels() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannels() => $_clearField(3);

  @$pb.TagNumber(4)
  AudioEncoding get encoding => $_getN(3);
  @$pb.TagNumber(4)
  set encoding(AudioEncoding value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasEncoding() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncoding() => $_clearField(4);

  /// True for the final audio chunk in a TTS/voice-agent audio stream.
  @$pb.TagNumber(5)
  $core.bool get isFinal => $_getBF(4);
  @$pb.TagNumber(5)
  set isFinal($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIsFinal() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsFinal() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get chunkIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkIndex($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasChunkIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkIndex() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get durationMs => $_getI64(6);
  @$pb.TagNumber(7)
  set durationMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearDurationMs() => $_clearField(7);
}

/// Voice Activity Detection output. Frontends usually do not need this —
/// exposed for debugging and custom UIs (waveform highlighting, etc.).
/// `type` uses the canonical VADStreamEventKind enum from
/// vad_options.proto (the hand-rolled VADEventType was deleted).
class VADEvent extends $pb.GeneratedMessage {
  factory VADEvent({
    $2.VADStreamEventKind? type,
    $fixnum.Int64? frameOffsetUs,
    $core.double? confidence,
    $core.bool? isSpeech,
    $core.double? speechDurationMs,
    $core.double? silenceDurationMs,
    $core.double? noiseFloorDb,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (frameOffsetUs != null) result.frameOffsetUs = frameOffsetUs;
    if (confidence != null) result.confidence = confidence;
    if (isSpeech != null) result.isSpeech = isSpeech;
    if (speechDurationMs != null) result.speechDurationMs = speechDurationMs;
    if (silenceDurationMs != null) result.silenceDurationMs = silenceDurationMs;
    if (noiseFloorDb != null) result.noiseFloorDb = noiseFloorDb;
    return result;
  }

  VADEvent._();

  factory VADEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VADEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VADEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$2.VADStreamEventKind>(1, _omitFieldNames ? '' : 'type',
        enumValues: $2.VADStreamEventKind.values)
    ..aInt64(2, _omitFieldNames ? '' : 'frameOffsetUs')
    ..aD(3, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'isSpeech')
    ..aD(5, _omitFieldNames ? '' : 'speechDurationMs')
    ..aD(6, _omitFieldNames ? '' : 'silenceDurationMs')
    ..aD(7, _omitFieldNames ? '' : 'noiseFloorDb')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VADEvent copyWith(void Function(VADEvent) updates) =>
      super.copyWith((message) => updates(message as VADEvent)) as VADEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADEvent create() => VADEvent._();
  @$core.override
  VADEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VADEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADEvent>(create);
  static VADEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $2.VADStreamEventKind get type => $_getN(0);
  @$pb.TagNumber(1)
  set type($2.VADStreamEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get frameOffsetUs => $_getI64(1);
  @$pb.TagNumber(2)
  set frameOffsetUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFrameOffsetUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrameOffsetUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get confidence => $_getN(2);
  @$pb.TagNumber(3)
  set confidence($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfidence() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfidence() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isSpeech => $_getBF(3);
  @$pb.TagNumber(4)
  set isSpeech($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsSpeech() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSpeech() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get speechDurationMs => $_getN(4);
  @$pb.TagNumber(5)
  set speechDurationMs($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSpeechDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeechDurationMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get silenceDurationMs => $_getN(5);
  @$pb.TagNumber(6)
  set silenceDurationMs($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSilenceDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearSilenceDurationMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get noiseFloorDb => $_getN(6);
  @$pb.TagNumber(7)
  set noiseFloorDb($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNoiseFloorDb() => $_has(6);
  @$pb.TagNumber(7)
  void clearNoiseFloorDb() => $_clearField(7);
}

/// Assistant playback was interrupted by a barge-in. The reason distinguishes
/// user barge-in from app-initiated cancel.
class InterruptedEvent extends $pb.GeneratedMessage {
  factory InterruptedEvent({
    InterruptReason? reason,
    $core.String? detail,
  }) {
    final result = create();
    if (reason != null) result.reason = reason;
    if (detail != null) result.detail = detail;
    return result;
  }

  InterruptedEvent._();

  factory InterruptedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InterruptedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InterruptedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<InterruptReason>(1, _omitFieldNames ? '' : 'reason',
        enumValues: InterruptReason.values)
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InterruptedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InterruptedEvent copyWith(void Function(InterruptedEvent) updates) =>
      super.copyWith((message) => updates(message as InterruptedEvent))
          as InterruptedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InterruptedEvent create() => InterruptedEvent._();
  @$core.override
  InterruptedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InterruptedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InterruptedEvent>(create);
  static InterruptedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  InterruptReason get reason => $_getN(0);
  @$pb.TagNumber(1)
  set reason(InterruptReason value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => $_clearField(2);
}

/// Pipeline lifecycle state. Ordered — callers can compare numerically.
class StateChangeEvent extends $pb.GeneratedMessage {
  factory StateChangeEvent({
    PipelineState? previous,
    PipelineState? current,
  }) {
    final result = create();
    if (previous != null) result.previous = previous;
    if (current != null) result.current = current;
    return result;
  }

  StateChangeEvent._();

  factory StateChangeEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StateChangeEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StateChangeEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<PipelineState>(1, _omitFieldNames ? '' : 'previous',
        enumValues: PipelineState.values)
    ..aE<PipelineState>(2, _omitFieldNames ? '' : 'current',
        enumValues: PipelineState.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateChangeEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateChangeEvent copyWith(void Function(StateChangeEvent) updates) =>
      super.copyWith((message) => updates(message as StateChangeEvent))
          as StateChangeEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StateChangeEvent create() => StateChangeEvent._();
  @$core.override
  StateChangeEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StateChangeEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StateChangeEvent>(create);
  static StateChangeEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PipelineState get previous => $_getN(0);
  @$pb.TagNumber(1)
  set previous(PipelineState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPrevious() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrevious() => $_clearField(1);

  @$pb.TagNumber(2)
  PipelineState get current => $_getN(1);
  @$pb.TagNumber(2)
  set current(PipelineState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrent() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrent() => $_clearField(2);
}

/// Terminal or recoverable error in the pipeline. Frontends map these to
/// their native error types.
class ErrorEvent extends $pb.GeneratedMessage {
  factory ErrorEvent({
    $core.int? code,
    $core.String? message,
    $core.String? component,
    $core.bool? isRecoverable,
    $core.String? operation,
    $core.String? detailsJson,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (component != null) result.component = component;
    if (isRecoverable != null) result.isRecoverable = isRecoverable;
    if (operation != null) result.operation = operation;
    if (detailsJson != null) result.detailsJson = detailsJson;
    return result;
  }

  ErrorEvent._();

  factory ErrorEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ErrorEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'code')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'component')
    ..aOB(4, _omitFieldNames ? '' : 'isRecoverable')
    ..aOS(5, _omitFieldNames ? '' : 'operation')
    ..aOS(6, _omitFieldNames ? '' : 'detailsJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorEvent copyWith(void Function(ErrorEvent) updates) =>
      super.copyWith((message) => updates(message as ErrorEvent)) as ErrorEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ErrorEvent create() => ErrorEvent._();
  @$core.override
  ErrorEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ErrorEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ErrorEvent>(create);
  static ErrorEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get component => $_getSZ(2);
  @$pb.TagNumber(3)
  set component($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasComponent() => $_has(2);
  @$pb.TagNumber(3)
  void clearComponent() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isRecoverable => $_getBF(3);
  @$pb.TagNumber(4)
  set isRecoverable($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsRecoverable() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsRecoverable() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get operation => $_getSZ(4);
  @$pb.TagNumber(5)
  set operation($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOperation() => $_has(4);
  @$pb.TagNumber(5)
  void clearOperation() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get detailsJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set detailsJson($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDetailsJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearDetailsJson() => $_clearField(6);
}

/// Per-primitive latency breakdown. Emitted at barge-in and at pipeline stop.
class MetricsEvent extends $pb.GeneratedMessage {
  factory MetricsEvent({
    $core.double? sttFinalMs,
    $core.double? llmFirstTokenMs,
    $core.double? ttsFirstAudioMs,
    $core.double? endToEndMs,
    $fixnum.Int64? tokensGenerated,
    $fixnum.Int64? audioSamplesPlayed,
    $core.bool? isOverBudget,
    $fixnum.Int64? createdAtNs,
    $core.double? vadFirstSpeechMs,
    $core.double? sttFirstPartialMs,
    $core.double? llmTotalMs,
    $core.double? ttsTotalMs,
  }) {
    final result = create();
    if (sttFinalMs != null) result.sttFinalMs = sttFinalMs;
    if (llmFirstTokenMs != null) result.llmFirstTokenMs = llmFirstTokenMs;
    if (ttsFirstAudioMs != null) result.ttsFirstAudioMs = ttsFirstAudioMs;
    if (endToEndMs != null) result.endToEndMs = endToEndMs;
    if (tokensGenerated != null) result.tokensGenerated = tokensGenerated;
    if (audioSamplesPlayed != null)
      result.audioSamplesPlayed = audioSamplesPlayed;
    if (isOverBudget != null) result.isOverBudget = isOverBudget;
    if (createdAtNs != null) result.createdAtNs = createdAtNs;
    if (vadFirstSpeechMs != null) result.vadFirstSpeechMs = vadFirstSpeechMs;
    if (sttFirstPartialMs != null) result.sttFirstPartialMs = sttFirstPartialMs;
    if (llmTotalMs != null) result.llmTotalMs = llmTotalMs;
    if (ttsTotalMs != null) result.ttsTotalMs = ttsTotalMs;
    return result;
  }

  MetricsEvent._();

  factory MetricsEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MetricsEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MetricsEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'sttFinalMs')
    ..aD(2, _omitFieldNames ? '' : 'llmFirstTokenMs')
    ..aD(3, _omitFieldNames ? '' : 'ttsFirstAudioMs')
    ..aD(4, _omitFieldNames ? '' : 'endToEndMs')
    ..aInt64(5, _omitFieldNames ? '' : 'tokensGenerated')
    ..aInt64(6, _omitFieldNames ? '' : 'audioSamplesPlayed')
    ..aOB(7, _omitFieldNames ? '' : 'isOverBudget')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAtNs')
    ..aD(9, _omitFieldNames ? '' : 'vadFirstSpeechMs')
    ..aD(10, _omitFieldNames ? '' : 'sttFirstPartialMs')
    ..aD(11, _omitFieldNames ? '' : 'llmTotalMs')
    ..aD(12, _omitFieldNames ? '' : 'ttsTotalMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MetricsEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MetricsEvent copyWith(void Function(MetricsEvent) updates) =>
      super.copyWith((message) => updates(message as MetricsEvent))
          as MetricsEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MetricsEvent create() => MetricsEvent._();
  @$core.override
  MetricsEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MetricsEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MetricsEvent>(create);
  static MetricsEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get sttFinalMs => $_getN(0);
  @$pb.TagNumber(1)
  set sttFinalMs($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSttFinalMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttFinalMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get llmFirstTokenMs => $_getN(1);
  @$pb.TagNumber(2)
  set llmFirstTokenMs($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLlmFirstTokenMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmFirstTokenMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get ttsFirstAudioMs => $_getN(2);
  @$pb.TagNumber(3)
  set ttsFirstAudioMs($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTtsFirstAudioMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsFirstAudioMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get endToEndMs => $_getN(3);
  @$pb.TagNumber(4)
  set endToEndMs($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEndToEndMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndToEndMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get tokensGenerated => $_getI64(4);
  @$pb.TagNumber(5)
  set tokensGenerated($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTokensGenerated() => $_has(4);
  @$pb.TagNumber(5)
  void clearTokensGenerated() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get audioSamplesPlayed => $_getI64(5);
  @$pb.TagNumber(6)
  set audioSamplesPlayed($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAudioSamplesPlayed() => $_has(5);
  @$pb.TagNumber(6)
  void clearAudioSamplesPlayed() => $_clearField(6);

  /// True when `end_to_end_ms` exceeded the `PipelineOptions.latency_budget_ms`
  /// configured for this run. Frontends can surface this to the UI for SLO
  /// dashboards without re-computing the threshold themselves.
  @$pb.TagNumber(7)
  $core.bool get isOverBudget => $_getBF(6);
  @$pb.TagNumber(7)
  set isOverBudget($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsOverBudget() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsOverBudget() => $_clearField(7);

  /// Monotonic producer-side timestamp in nanoseconds. Set by the
  /// producer (C++ dispatcher) at event-emit time; read by consumers
  /// (5-SDK perf_bench + p50 benchmark CI) to compute event-to-frontend
  /// latency without relying on wall-clock sync. Encoded as int64 so
  /// std::chrono::steady_clock::now().time_since_epoch() values fit
  /// directly (2^63 ns ≈ 292 years of runtime headroom).
  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtNs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtNs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtNs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtNs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get vadFirstSpeechMs => $_getN(8);
  @$pb.TagNumber(9)
  set vadFirstSpeechMs($core.double value) => $_setDouble(8, value);
  @$pb.TagNumber(9)
  $core.bool hasVadFirstSpeechMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearVadFirstSpeechMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.double get sttFirstPartialMs => $_getN(9);
  @$pb.TagNumber(10)
  set sttFirstPartialMs($core.double value) => $_setDouble(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSttFirstPartialMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearSttFirstPartialMs() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.double get llmTotalMs => $_getN(10);
  @$pb.TagNumber(11)
  set llmTotalMs($core.double value) => $_setDouble(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLlmTotalMs() => $_has(10);
  @$pb.TagNumber(11)
  void clearLlmTotalMs() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.double get ttsTotalMs => $_getN(11);
  @$pb.TagNumber(12)
  set ttsTotalMs($core.double value) => $_setDouble(11, value);
  @$pb.TagNumber(12)
  $core.bool hasTtsTotalMs() => $_has(11);
  @$pb.TagNumber(12)
  void clearTtsTotalMs() => $_clearField(12);
}

class AudioLevelEvent extends $pb.GeneratedMessage {
  factory AudioLevelEvent({
    $core.double? rms,
    $core.double? peak,
    $core.double? noiseFloorDb,
    $core.bool? isSpeech,
  }) {
    final result = create();
    if (rms != null) result.rms = rms;
    if (peak != null) result.peak = peak;
    if (noiseFloorDb != null) result.noiseFloorDb = noiseFloorDb;
    if (isSpeech != null) result.isSpeech = isSpeech;
    return result;
  }

  AudioLevelEvent._();

  factory AudioLevelEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AudioLevelEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AudioLevelEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'rms', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'peak', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'noiseFloorDb',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'isSpeech')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioLevelEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AudioLevelEvent copyWith(void Function(AudioLevelEvent) updates) =>
      super.copyWith((message) => updates(message as AudioLevelEvent))
          as AudioLevelEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioLevelEvent create() => AudioLevelEvent._();
  @$core.override
  AudioLevelEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AudioLevelEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AudioLevelEvent>(create);
  static AudioLevelEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get rms => $_getN(0);
  @$pb.TagNumber(1)
  set rms($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRms() => $_has(0);
  @$pb.TagNumber(1)
  void clearRms() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get peak => $_getN(1);
  @$pb.TagNumber(2)
  set peak($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPeak() => $_has(1);
  @$pb.TagNumber(2)
  void clearPeak() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get noiseFloorDb => $_getN(2);
  @$pb.TagNumber(3)
  set noiseFloorDb($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNoiseFloorDb() => $_has(2);
  @$pb.TagNumber(3)
  void clearNoiseFloorDb() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isSpeech => $_getBF(3);
  @$pb.TagNumber(4)
  set isSpeech($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsSpeech() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSpeech() => $_clearField(4);
}

class ComponentProgressEvent extends $pb.GeneratedMessage {
  factory ComponentProgressEvent({
    VoicePipelineComponent? component,
    $core.String? operation,
    $core.double? progress,
    $core.String? message,
  }) {
    final result = create();
    if (component != null) result.component = component;
    if (operation != null) result.operation = operation;
    if (progress != null) result.progress = progress;
    if (message != null) result.message = message;
    return result;
  }

  ComponentProgressEvent._();

  factory ComponentProgressEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComponentProgressEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentProgressEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<VoicePipelineComponent>(1, _omitFieldNames ? '' : 'component',
        enumValues: VoicePipelineComponent.values)
    ..aOS(2, _omitFieldNames ? '' : 'operation')
    ..aD(3, _omitFieldNames ? '' : 'progress', fieldType: $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentProgressEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentProgressEvent copyWith(
          void Function(ComponentProgressEvent) updates) =>
      super.copyWith((message) => updates(message as ComponentProgressEvent))
          as ComponentProgressEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentProgressEvent create() => ComponentProgressEvent._();
  @$core.override
  ComponentProgressEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComponentProgressEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComponentProgressEvent>(create);
  static ComponentProgressEvent? _defaultInstance;

  @$pb.TagNumber(1)
  VoicePipelineComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component(VoicePipelineComponent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get operation => $_getSZ(1);
  @$pb.TagNumber(2)
  set operation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperation() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperation() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get progress => $_getN(2);
  @$pb.TagNumber(3)
  set progress($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProgress() => $_has(2);
  @$pb.TagNumber(3)
  void clearProgress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);
}

/// Aggregate load state across all four voice-agent components. Mirrors Swift
/// `VoiceAgentComponentStates`, Kotlin `VoiceAgentComponentStates`, RN
/// `VoiceAgentComponentStates`, Web `VoiceAgentComponentStates`, and Flutter
/// `VoiceAgentComponentStates`.
///
/// The former `ComponentLoadState` enum was consolidated into the
/// canonical richer `ComponentLifecycleState` (component_types.proto). Where
/// the old enum's `COMPONENT_LOAD_STATE_LOADED` value was used to mean "this
/// component is ready to use", callers now use
/// `COMPONENT_LIFECYCLE_STATE_READY`.
class VoiceAgentComponentStates extends $pb.GeneratedMessage {
  factory VoiceAgentComponentStates({
    $0.ComponentLifecycleState? sttState,
    $0.ComponentLifecycleState? llmState,
    $0.ComponentLifecycleState? ttsState,
    $0.ComponentLifecycleState? vadState,
    $core.bool? ready,
    $core.bool? anyLoading,
    $0.ComponentLifecycleState? wakewordState,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (sttState != null) result.sttState = sttState;
    if (llmState != null) result.llmState = llmState;
    if (ttsState != null) result.ttsState = ttsState;
    if (vadState != null) result.vadState = vadState;
    if (ready != null) result.ready = ready;
    if (anyLoading != null) result.anyLoading = anyLoading;
    if (wakewordState != null) result.wakewordState = wakewordState;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  VoiceAgentComponentStates._();

  factory VoiceAgentComponentStates.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentComponentStates.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentComponentStates',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$0.ComponentLifecycleState>(1, _omitFieldNames ? '' : 'sttState',
        enumValues: $0.ComponentLifecycleState.values)
    ..aE<$0.ComponentLifecycleState>(2, _omitFieldNames ? '' : 'llmState',
        enumValues: $0.ComponentLifecycleState.values)
    ..aE<$0.ComponentLifecycleState>(3, _omitFieldNames ? '' : 'ttsState',
        enumValues: $0.ComponentLifecycleState.values)
    ..aE<$0.ComponentLifecycleState>(4, _omitFieldNames ? '' : 'vadState',
        enumValues: $0.ComponentLifecycleState.values)
    ..aOB(5, _omitFieldNames ? '' : 'ready')
    ..aOB(6, _omitFieldNames ? '' : 'anyLoading')
    ..aE<$0.ComponentLifecycleState>(7, _omitFieldNames ? '' : 'wakewordState',
        enumValues: $0.ComponentLifecycleState.values)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentComponentStates clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentComponentStates copyWith(
          void Function(VoiceAgentComponentStates) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentComponentStates))
          as VoiceAgentComponentStates;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentComponentStates create() => VoiceAgentComponentStates._();
  @$core.override
  VoiceAgentComponentStates createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComponentStates getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentComponentStates>(create);
  static VoiceAgentComponentStates? _defaultInstance;

  @$pb.TagNumber(1)
  $0.ComponentLifecycleState get sttState => $_getN(0);
  @$pb.TagNumber(1)
  set sttState($0.ComponentLifecycleState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSttState() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttState() => $_clearField(1);

  @$pb.TagNumber(2)
  $0.ComponentLifecycleState get llmState => $_getN(1);
  @$pb.TagNumber(2)
  set llmState($0.ComponentLifecycleState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasLlmState() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmState() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.ComponentLifecycleState get ttsState => $_getN(2);
  @$pb.TagNumber(3)
  set ttsState($0.ComponentLifecycleState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTtsState() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsState() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.ComponentLifecycleState get vadState => $_getN(3);
  @$pb.TagNumber(4)
  set vadState($0.ComponentLifecycleState value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasVadState() => $_has(3);
  @$pb.TagNumber(4)
  void clearVadState() => $_clearField(4);

  /// Computed: true when stt_state, llm_state, tts_state, vad_state are all
  /// COMPONENT_LIFECYCLE_STATE_READY. Producer sets this; consumers must NOT
  /// recompute.
  @$pb.TagNumber(5)
  $core.bool get ready => $_getBF(4);
  @$pb.TagNumber(5)
  set ready($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasReady() => $_has(4);
  @$pb.TagNumber(5)
  void clearReady() => $_clearField(5);

  /// Computed: true when any of the four states is
  /// COMPONENT_LIFECYCLE_STATE_LOADING.
  @$pb.TagNumber(6)
  $core.bool get anyLoading => $_getBF(5);
  @$pb.TagNumber(6)
  set anyLoading($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAnyLoading() => $_has(5);
  @$pb.TagNumber(6)
  void clearAnyLoading() => $_clearField(6);

  @$pb.TagNumber(7)
  $0.ComponentLifecycleState get wakewordState => $_getN(6);
  @$pb.TagNumber(7)
  set wakewordState($0.ComponentLifecycleState value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasWakewordState() => $_has(6);
  @$pb.TagNumber(7)
  void clearWakewordState() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => $_clearField(8);
}

class VoiceSessionError extends $pb.GeneratedMessage {
  factory VoiceSessionError({
    $1.ErrorCode? code,
    $core.String? message,
    $core.String? failedComponent,
    $core.int? cAbiCode,
    $core.bool? recoverable,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (failedComponent != null) result.failedComponent = failedComponent;
    if (cAbiCode != null) result.cAbiCode = cAbiCode;
    if (recoverable != null) result.recoverable = recoverable;
    return result;
  }

  VoiceSessionError._();

  factory VoiceSessionError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceSessionError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceSessionError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<$1.ErrorCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: $1.ErrorCode.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'failedComponent')
    ..aI(4, _omitFieldNames ? '' : 'cAbiCode')
    ..aOB(5, _omitFieldNames ? '' : 'recoverable')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceSessionError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceSessionError copyWith(void Function(VoiceSessionError) updates) =>
      super.copyWith((message) => updates(message as VoiceSessionError))
          as VoiceSessionError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceSessionError create() => VoiceSessionError._();
  @$core.override
  VoiceSessionError createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceSessionError getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceSessionError>(create);
  static VoiceSessionError? _defaultInstance;

  @$pb.TagNumber(1)
  $1.ErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code($1.ErrorCode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get failedComponent => $_getSZ(2);
  @$pb.TagNumber(3)
  set failedComponent($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFailedComponent() => $_has(2);
  @$pb.TagNumber(3)
  void clearFailedComponent() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get cAbiCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set cAbiCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCAbiCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearCAbiCode() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get recoverable => $_getBF(4);
  @$pb.TagNumber(5)
  set recoverable($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecoverable() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecoverable() => $_clearField(5);
}

class SessionStartedEvent extends $pb.GeneratedMessage {
  factory SessionStartedEvent({
    $core.String? sessionId,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    return result;
  }

  SessionStartedEvent._();

  factory SessionStartedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionStartedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionStartedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionStartedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionStartedEvent copyWith(void Function(SessionStartedEvent) updates) =>
      super.copyWith((message) => updates(message as SessionStartedEvent))
          as SessionStartedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionStartedEvent create() => SessionStartedEvent._();
  @$core.override
  SessionStartedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionStartedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionStartedEvent>(create);
  static SessionStartedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);
}

class SessionStoppedEvent extends $pb.GeneratedMessage {
  factory SessionStoppedEvent({
    $core.String? sessionId,
    $core.String? reason,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (reason != null) result.reason = reason;
    return result;
  }

  SessionStoppedEvent._();

  factory SessionStoppedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionStoppedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionStoppedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionStoppedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionStoppedEvent copyWith(void Function(SessionStoppedEvent) updates) =>
      super.copyWith((message) => updates(message as SessionStoppedEvent))
          as SessionStoppedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionStoppedEvent create() => SessionStoppedEvent._();
  @$core.override
  SessionStoppedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionStoppedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionStoppedEvent>(create);
  static SessionStoppedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class AgentResponseStartedEvent extends $pb.GeneratedMessage {
  factory AgentResponseStartedEvent({
    $core.String? turnId,
  }) {
    final result = create();
    if (turnId != null) result.turnId = turnId;
    return result;
  }

  AgentResponseStartedEvent._();

  factory AgentResponseStartedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AgentResponseStartedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AgentResponseStartedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'turnId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AgentResponseStartedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AgentResponseStartedEvent copyWith(
          void Function(AgentResponseStartedEvent) updates) =>
      super.copyWith((message) => updates(message as AgentResponseStartedEvent))
          as AgentResponseStartedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AgentResponseStartedEvent create() => AgentResponseStartedEvent._();
  @$core.override
  AgentResponseStartedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AgentResponseStartedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AgentResponseStartedEvent>(create);
  static AgentResponseStartedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get turnId => $_getSZ(0);
  @$pb.TagNumber(1)
  set turnId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTurnId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTurnId() => $_clearField(1);
}

class AgentResponseCompletedEvent extends $pb.GeneratedMessage {
  factory AgentResponseCompletedEvent({
    $core.String? turnId,
    $fixnum.Int64? responseDurationMs,
  }) {
    final result = create();
    if (turnId != null) result.turnId = turnId;
    if (responseDurationMs != null)
      result.responseDurationMs = responseDurationMs;
    return result;
  }

  AgentResponseCompletedEvent._();

  factory AgentResponseCompletedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AgentResponseCompletedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AgentResponseCompletedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'turnId')
    ..aInt64(2, _omitFieldNames ? '' : 'responseDurationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AgentResponseCompletedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AgentResponseCompletedEvent copyWith(
          void Function(AgentResponseCompletedEvent) updates) =>
      super.copyWith(
              (message) => updates(message as AgentResponseCompletedEvent))
          as AgentResponseCompletedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AgentResponseCompletedEvent create() =>
      AgentResponseCompletedEvent._();
  @$core.override
  AgentResponseCompletedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AgentResponseCompletedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AgentResponseCompletedEvent>(create);
  static AgentResponseCompletedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get turnId => $_getSZ(0);
  @$pb.TagNumber(1)
  set turnId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTurnId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTurnId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get responseDurationMs => $_getI64(1);
  @$pb.TagNumber(2)
  set responseDurationMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasResponseDurationMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearResponseDurationMs() => $_clearField(2);
}

class SpeechTurnDetectionEvent extends $pb.GeneratedMessage {
  factory SpeechTurnDetectionEvent({
    SpeechTurnDetectionEventKind? kind,
    $core.String? speakerId,
    $fixnum.Int64? turnStartUs,
    $fixnum.Int64? turnEndUs,
    $core.double? confidence,
    $core.double? speechDurationMs,
    $core.double? silenceDurationMs,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (speakerId != null) result.speakerId = speakerId;
    if (turnStartUs != null) result.turnStartUs = turnStartUs;
    if (turnEndUs != null) result.turnEndUs = turnEndUs;
    if (confidence != null) result.confidence = confidence;
    if (speechDurationMs != null) result.speechDurationMs = speechDurationMs;
    if (silenceDurationMs != null) result.silenceDurationMs = silenceDurationMs;
    return result;
  }

  SpeechTurnDetectionEvent._();

  factory SpeechTurnDetectionEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SpeechTurnDetectionEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpeechTurnDetectionEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SpeechTurnDetectionEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: SpeechTurnDetectionEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'speakerId')
    ..aInt64(3, _omitFieldNames ? '' : 'turnStartUs')
    ..aInt64(4, _omitFieldNames ? '' : 'turnEndUs')
    ..aD(5, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'speechDurationMs')
    ..aD(7, _omitFieldNames ? '' : 'silenceDurationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeechTurnDetectionEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpeechTurnDetectionEvent copyWith(
          void Function(SpeechTurnDetectionEvent) updates) =>
      super.copyWith((message) => updates(message as SpeechTurnDetectionEvent))
          as SpeechTurnDetectionEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpeechTurnDetectionEvent create() => SpeechTurnDetectionEvent._();
  @$core.override
  SpeechTurnDetectionEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SpeechTurnDetectionEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SpeechTurnDetectionEvent>(create);
  static SpeechTurnDetectionEvent? _defaultInstance;

  @$pb.TagNumber(1)
  SpeechTurnDetectionEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(SpeechTurnDetectionEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get speakerId => $_getSZ(1);
  @$pb.TagNumber(2)
  set speakerId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSpeakerId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeakerId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get turnStartUs => $_getI64(2);
  @$pb.TagNumber(3)
  set turnStartUs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTurnStartUs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTurnStartUs() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get turnEndUs => $_getI64(3);
  @$pb.TagNumber(4)
  set turnEndUs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTurnEndUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTurnEndUs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get confidence => $_getN(4);
  @$pb.TagNumber(5)
  set confidence($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasConfidence() => $_has(4);
  @$pb.TagNumber(5)
  void clearConfidence() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get speechDurationMs => $_getN(5);
  @$pb.TagNumber(6)
  set speechDurationMs($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSpeechDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearSpeechDurationMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get silenceDurationMs => $_getN(6);
  @$pb.TagNumber(7)
  set silenceDurationMs($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSilenceDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearSilenceDurationMs() => $_clearField(7);
}

class TurnLifecycleEvent extends $pb.GeneratedMessage {
  factory TurnLifecycleEvent({
    TurnLifecycleEventKind? kind,
    $core.String? turnId,
    $core.String? sessionId,
    $core.String? transcript,
    $core.String? response,
    $core.String? error,
    $fixnum.Int64? startedAtMs,
    $fixnum.Int64? completedAtMs,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (turnId != null) result.turnId = turnId;
    if (sessionId != null) result.sessionId = sessionId;
    if (transcript != null) result.transcript = transcript;
    if (response != null) result.response = response;
    if (error != null) result.error = error;
    if (startedAtMs != null) result.startedAtMs = startedAtMs;
    if (completedAtMs != null) result.completedAtMs = completedAtMs;
    return result;
  }

  TurnLifecycleEvent._();

  factory TurnLifecycleEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TurnLifecycleEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TurnLifecycleEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<TurnLifecycleEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: TurnLifecycleEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'turnId')
    ..aOS(3, _omitFieldNames ? '' : 'sessionId')
    ..aOS(4, _omitFieldNames ? '' : 'transcript')
    ..aOS(5, _omitFieldNames ? '' : 'response')
    ..aOS(6, _omitFieldNames ? '' : 'error')
    ..aInt64(7, _omitFieldNames ? '' : 'startedAtMs')
    ..aInt64(8, _omitFieldNames ? '' : 'completedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnLifecycleEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TurnLifecycleEvent copyWith(void Function(TurnLifecycleEvent) updates) =>
      super.copyWith((message) => updates(message as TurnLifecycleEvent))
          as TurnLifecycleEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TurnLifecycleEvent create() => TurnLifecycleEvent._();
  @$core.override
  TurnLifecycleEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TurnLifecycleEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TurnLifecycleEvent>(create);
  static TurnLifecycleEvent? _defaultInstance;

  @$pb.TagNumber(1)
  TurnLifecycleEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(TurnLifecycleEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get turnId => $_getSZ(1);
  @$pb.TagNumber(2)
  set turnId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTurnId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTurnId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sessionId => $_getSZ(2);
  @$pb.TagNumber(3)
  set sessionId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get transcript => $_getSZ(3);
  @$pb.TagNumber(4)
  set transcript($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTranscript() => $_has(3);
  @$pb.TagNumber(4)
  void clearTranscript() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get response => $_getSZ(4);
  @$pb.TagNumber(5)
  set response($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasResponse() => $_has(4);
  @$pb.TagNumber(5)
  void clearResponse() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get error => $_getSZ(5);
  @$pb.TagNumber(6)
  set error($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get startedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set startedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStartedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearStartedAtMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get completedAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set completedAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCompletedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCompletedAtMs() => $_clearField(8);
}

class WakeWordDetectedEvent extends $pb.GeneratedMessage {
  factory WakeWordDetectedEvent({
    $core.String? wakeWord,
    $core.double? confidence,
    $fixnum.Int64? timestampMs,
    $core.String? modelId,
    $core.int? modelIndex,
    $fixnum.Int64? durationMs,
  }) {
    final result = create();
    if (wakeWord != null) result.wakeWord = wakeWord;
    if (confidence != null) result.confidence = confidence;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (modelId != null) result.modelId = modelId;
    if (modelIndex != null) result.modelIndex = modelIndex;
    if (durationMs != null) result.durationMs = durationMs;
    return result;
  }

  WakeWordDetectedEvent._();

  factory WakeWordDetectedEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WakeWordDetectedEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WakeWordDetectedEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'wakeWord')
    ..aD(2, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..aI(5, _omitFieldNames ? '' : 'modelIndex')
    ..aInt64(6, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WakeWordDetectedEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WakeWordDetectedEvent copyWith(
          void Function(WakeWordDetectedEvent) updates) =>
      super.copyWith((message) => updates(message as WakeWordDetectedEvent))
          as WakeWordDetectedEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WakeWordDetectedEvent create() => WakeWordDetectedEvent._();
  @$core.override
  WakeWordDetectedEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WakeWordDetectedEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WakeWordDetectedEvent>(create);
  static WakeWordDetectedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get wakeWord => $_getSZ(0);
  @$pb.TagNumber(1)
  set wakeWord($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWakeWord() => $_has(0);
  @$pb.TagNumber(1)
  void clearWakeWord() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set modelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearModelId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get modelIndex => $_getIZ(4);
  @$pb.TagNumber(5)
  set modelIndex($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelIndex() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelIndex() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get durationMs => $_getI64(5);
  @$pb.TagNumber(6)
  set durationMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearDurationMs() => $_clearField(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
