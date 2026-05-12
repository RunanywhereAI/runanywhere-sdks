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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'component_types.pbenum.dart' as $12;
import 'errors.pbenum.dart' as $13;
import 'vad_options.pbenum.dart' as $11;
import 'voice_events.pbenum.dart';

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
    $12.EventCategory? category,
    $13.ErrorSeverity? severity,
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
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (category != null) {
      $result.category = category;
    }
    if (severity != null) {
      $result.severity = severity;
    }
    if (component != null) {
      $result.component = component;
    }
    if (userSaid != null) {
      $result.userSaid = userSaid;
    }
    if (assistantToken != null) {
      $result.assistantToken = assistantToken;
    }
    if (audio != null) {
      $result.audio = audio;
    }
    if (vad != null) {
      $result.vad = vad;
    }
    if (interrupted != null) {
      $result.interrupted = interrupted;
    }
    if (state != null) {
      $result.state = state;
    }
    if (error != null) {
      $result.error = error;
    }
    if (metrics != null) {
      $result.metrics = metrics;
    }
    if (componentStateChanged != null) {
      $result.componentStateChanged = componentStateChanged;
    }
    if (sessionError != null) {
      $result.sessionError = sessionError;
    }
    if (sessionStarted != null) {
      $result.sessionStarted = sessionStarted;
    }
    if (sessionStopped != null) {
      $result.sessionStopped = sessionStopped;
    }
    if (agentResponseStarted != null) {
      $result.agentResponseStarted = agentResponseStarted;
    }
    if (agentResponseCompleted != null) {
      $result.agentResponseCompleted = agentResponseCompleted;
    }
    if (speechTurnDetection != null) {
      $result.speechTurnDetection = speechTurnDetection;
    }
    if (turnLifecycle != null) {
      $result.turnLifecycle = turnLifecycle;
    }
    if (wakewordDetected != null) {
      $result.wakewordDetected = wakewordDetected;
    }
    if (audioLevel != null) {
      $result.audioLevel = audioLevel;
    }
    if (componentProgress != null) {
      $result.componentProgress = componentProgress;
    }
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    if (turnId != null) {
      $result.turnId = turnId;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  VoiceEvent._() : super();
  factory VoiceEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, VoiceEvent_Payload> _VoiceEvent_PayloadByTag = {
    10 : VoiceEvent_Payload.userSaid,
    11 : VoiceEvent_Payload.assistantToken,
    12 : VoiceEvent_Payload.audio,
    13 : VoiceEvent_Payload.vad,
    14 : VoiceEvent_Payload.interrupted,
    15 : VoiceEvent_Payload.state,
    16 : VoiceEvent_Payload.error,
    17 : VoiceEvent_Payload.metrics,
    18 : VoiceEvent_Payload.componentStateChanged,
    19 : VoiceEvent_Payload.sessionError,
    20 : VoiceEvent_Payload.sessionStarted,
    21 : VoiceEvent_Payload.sessionStopped,
    22 : VoiceEvent_Payload.agentResponseStarted,
    23 : VoiceEvent_Payload.agentResponseCompleted,
    24 : VoiceEvent_Payload.speechTurnDetection,
    25 : VoiceEvent_Payload.turnLifecycle,
    26 : VoiceEvent_Payload.wakewordDetected,
    27 : VoiceEvent_Payload.audioLevel,
    28 : VoiceEvent_Payload.componentProgress,
    0 : VoiceEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28])
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..e<$12.EventCategory>(3, _omitFieldNames ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: $12.EventCategory.EVENT_CATEGORY_UNSPECIFIED, valueOf: $12.EventCategory.valueOf, enumValues: $12.EventCategory.values)
    ..e<$13.ErrorSeverity>(4, _omitFieldNames ? '' : 'severity', $pb.PbFieldType.OE, defaultOrMaker: $13.ErrorSeverity.ERROR_SEVERITY_UNSPECIFIED, valueOf: $13.ErrorSeverity.valueOf, enumValues: $13.ErrorSeverity.values)
    ..e<VoicePipelineComponent>(5, _omitFieldNames ? '' : 'component', $pb.PbFieldType.OE, defaultOrMaker: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_UNSPECIFIED, valueOf: VoicePipelineComponent.valueOf, enumValues: VoicePipelineComponent.values)
    ..aOM<UserSaidEvent>(10, _omitFieldNames ? '' : 'userSaid', subBuilder: UserSaidEvent.create)
    ..aOM<AssistantTokenEvent>(11, _omitFieldNames ? '' : 'assistantToken', subBuilder: AssistantTokenEvent.create)
    ..aOM<AudioFrameEvent>(12, _omitFieldNames ? '' : 'audio', subBuilder: AudioFrameEvent.create)
    ..aOM<VADEvent>(13, _omitFieldNames ? '' : 'vad', subBuilder: VADEvent.create)
    ..aOM<InterruptedEvent>(14, _omitFieldNames ? '' : 'interrupted', subBuilder: InterruptedEvent.create)
    ..aOM<StateChangeEvent>(15, _omitFieldNames ? '' : 'state', subBuilder: StateChangeEvent.create)
    ..aOM<ErrorEvent>(16, _omitFieldNames ? '' : 'error', subBuilder: ErrorEvent.create)
    ..aOM<MetricsEvent>(17, _omitFieldNames ? '' : 'metrics', subBuilder: MetricsEvent.create)
    ..aOM<VoiceAgentComponentStates>(18, _omitFieldNames ? '' : 'componentStateChanged', subBuilder: VoiceAgentComponentStates.create)
    ..aOM<VoiceSessionError>(19, _omitFieldNames ? '' : 'sessionError', subBuilder: VoiceSessionError.create)
    ..aOM<SessionStartedEvent>(20, _omitFieldNames ? '' : 'sessionStarted', subBuilder: SessionStartedEvent.create)
    ..aOM<SessionStoppedEvent>(21, _omitFieldNames ? '' : 'sessionStopped', subBuilder: SessionStoppedEvent.create)
    ..aOM<AgentResponseStartedEvent>(22, _omitFieldNames ? '' : 'agentResponseStarted', subBuilder: AgentResponseStartedEvent.create)
    ..aOM<AgentResponseCompletedEvent>(23, _omitFieldNames ? '' : 'agentResponseCompleted', subBuilder: AgentResponseCompletedEvent.create)
    ..aOM<SpeechTurnDetectionEvent>(24, _omitFieldNames ? '' : 'speechTurnDetection', subBuilder: SpeechTurnDetectionEvent.create)
    ..aOM<TurnLifecycleEvent>(25, _omitFieldNames ? '' : 'turnLifecycle', subBuilder: TurnLifecycleEvent.create)
    ..aOM<WakeWordDetectedEvent>(26, _omitFieldNames ? '' : 'wakewordDetected', subBuilder: WakeWordDetectedEvent.create)
    ..aOM<AudioLevelEvent>(27, _omitFieldNames ? '' : 'audioLevel', subBuilder: AudioLevelEvent.create)
    ..aOM<ComponentProgressEvent>(28, _omitFieldNames ? '' : 'componentProgress', subBuilder: ComponentProgressEvent.create)
    ..aOS(30, _omitFieldNames ? '' : 'sessionId')
    ..aOS(31, _omitFieldNames ? '' : 'turnId')
    ..aOS(32, _omitFieldNames ? '' : 'requestId')
    ..m<$core.String, $core.String>(33, _omitFieldNames ? '' : 'metadata', entryClassName: 'VoiceEvent.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceEvent clone() => VoiceEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceEvent copyWith(void Function(VoiceEvent) updates) => super.copyWith((message) => updates(message as VoiceEvent)) as VoiceEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceEvent create() => VoiceEvent._();
  VoiceEvent createEmptyInstance() => create();
  static $pb.PbList<VoiceEvent> createRepeated() => $pb.PbList<VoiceEvent>();
  @$core.pragma('dart2js:noInline')
  static VoiceEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceEvent>(create);
  static VoiceEvent? _defaultInstance;

  VoiceEvent_Payload whichPayload() => _VoiceEvent_PayloadByTag[$_whichOneof(0)]!;
  void clearPayload() => clearField($_whichOneof(0));

  /// Monotonic pipeline-local sequence number. Useful for frontends that
  /// need to detect gaps after reconnection or out-of-order delivery.
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  /// Wall-clock timestamp captured at the C++ edge, in microseconds since
  /// Unix epoch. Frontends may re-timestamp for UI display.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $12.EventCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category($12.EventCategory v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => clearField(3);

  @$pb.TagNumber(4)
  $13.ErrorSeverity get severity => $_getN(3);
  @$pb.TagNumber(4)
  set severity($13.ErrorSeverity v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasSeverity() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeverity() => clearField(4);

  @$pb.TagNumber(5)
  VoicePipelineComponent get component => $_getN(4);
  @$pb.TagNumber(5)
  set component(VoicePipelineComponent v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasComponent() => $_has(4);
  @$pb.TagNumber(5)
  void clearComponent() => clearField(5);

  @$pb.TagNumber(10)
  UserSaidEvent get userSaid => $_getN(5);
  @$pb.TagNumber(10)
  set userSaid(UserSaidEvent v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasUserSaid() => $_has(5);
  @$pb.TagNumber(10)
  void clearUserSaid() => clearField(10);
  @$pb.TagNumber(10)
  UserSaidEvent ensureUserSaid() => $_ensure(5);

  @$pb.TagNumber(11)
  AssistantTokenEvent get assistantToken => $_getN(6);
  @$pb.TagNumber(11)
  set assistantToken(AssistantTokenEvent v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasAssistantToken() => $_has(6);
  @$pb.TagNumber(11)
  void clearAssistantToken() => clearField(11);
  @$pb.TagNumber(11)
  AssistantTokenEvent ensureAssistantToken() => $_ensure(6);

  @$pb.TagNumber(12)
  AudioFrameEvent get audio => $_getN(7);
  @$pb.TagNumber(12)
  set audio(AudioFrameEvent v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasAudio() => $_has(7);
  @$pb.TagNumber(12)
  void clearAudio() => clearField(12);
  @$pb.TagNumber(12)
  AudioFrameEvent ensureAudio() => $_ensure(7);

  @$pb.TagNumber(13)
  VADEvent get vad => $_getN(8);
  @$pb.TagNumber(13)
  set vad(VADEvent v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasVad() => $_has(8);
  @$pb.TagNumber(13)
  void clearVad() => clearField(13);
  @$pb.TagNumber(13)
  VADEvent ensureVad() => $_ensure(8);

  @$pb.TagNumber(14)
  InterruptedEvent get interrupted => $_getN(9);
  @$pb.TagNumber(14)
  set interrupted(InterruptedEvent v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasInterrupted() => $_has(9);
  @$pb.TagNumber(14)
  void clearInterrupted() => clearField(14);
  @$pb.TagNumber(14)
  InterruptedEvent ensureInterrupted() => $_ensure(9);

  @$pb.TagNumber(15)
  StateChangeEvent get state => $_getN(10);
  @$pb.TagNumber(15)
  set state(StateChangeEvent v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasState() => $_has(10);
  @$pb.TagNumber(15)
  void clearState() => clearField(15);
  @$pb.TagNumber(15)
  StateChangeEvent ensureState() => $_ensure(10);

  @$pb.TagNumber(16)
  ErrorEvent get error => $_getN(11);
  @$pb.TagNumber(16)
  set error(ErrorEvent v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasError() => $_has(11);
  @$pb.TagNumber(16)
  void clearError() => clearField(16);
  @$pb.TagNumber(16)
  ErrorEvent ensureError() => $_ensure(11);

  @$pb.TagNumber(17)
  MetricsEvent get metrics => $_getN(12);
  @$pb.TagNumber(17)
  set metrics(MetricsEvent v) { setField(17, v); }
  @$pb.TagNumber(17)
  $core.bool hasMetrics() => $_has(12);
  @$pb.TagNumber(17)
  void clearMetrics() => clearField(17);
  @$pb.TagNumber(17)
  MetricsEvent ensureMetrics() => $_ensure(12);

  /// v3.2: Voice agent lifecycle events. Mirror Swift VoiceSessionError /
  /// VoiceAgentComponentStates and the AsyncSequence-style lifecycle
  /// signals consumed by the cross-platform VoiceAgent extensions
  /// (Swift VoiceAgentTypes.swift, Kotlin VoiceAgentTypes.kt, RN
  /// VoiceAgentTypes.ts, Web VoiceAgentCTypes.ts, Flutter
  /// voice_agent_types.dart).
  @$pb.TagNumber(18)
  VoiceAgentComponentStates get componentStateChanged => $_getN(13);
  @$pb.TagNumber(18)
  set componentStateChanged(VoiceAgentComponentStates v) { setField(18, v); }
  @$pb.TagNumber(18)
  $core.bool hasComponentStateChanged() => $_has(13);
  @$pb.TagNumber(18)
  void clearComponentStateChanged() => clearField(18);
  @$pb.TagNumber(18)
  VoiceAgentComponentStates ensureComponentStateChanged() => $_ensure(13);

  @$pb.TagNumber(19)
  VoiceSessionError get sessionError => $_getN(14);
  @$pb.TagNumber(19)
  set sessionError(VoiceSessionError v) { setField(19, v); }
  @$pb.TagNumber(19)
  $core.bool hasSessionError() => $_has(14);
  @$pb.TagNumber(19)
  void clearSessionError() => clearField(19);
  @$pb.TagNumber(19)
  VoiceSessionError ensureSessionError() => $_ensure(14);

  @$pb.TagNumber(20)
  SessionStartedEvent get sessionStarted => $_getN(15);
  @$pb.TagNumber(20)
  set sessionStarted(SessionStartedEvent v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasSessionStarted() => $_has(15);
  @$pb.TagNumber(20)
  void clearSessionStarted() => clearField(20);
  @$pb.TagNumber(20)
  SessionStartedEvent ensureSessionStarted() => $_ensure(15);

  @$pb.TagNumber(21)
  SessionStoppedEvent get sessionStopped => $_getN(16);
  @$pb.TagNumber(21)
  set sessionStopped(SessionStoppedEvent v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasSessionStopped() => $_has(16);
  @$pb.TagNumber(21)
  void clearSessionStopped() => clearField(21);
  @$pb.TagNumber(21)
  SessionStoppedEvent ensureSessionStopped() => $_ensure(16);

  @$pb.TagNumber(22)
  AgentResponseStartedEvent get agentResponseStarted => $_getN(17);
  @$pb.TagNumber(22)
  set agentResponseStarted(AgentResponseStartedEvent v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasAgentResponseStarted() => $_has(17);
  @$pb.TagNumber(22)
  void clearAgentResponseStarted() => clearField(22);
  @$pb.TagNumber(22)
  AgentResponseStartedEvent ensureAgentResponseStarted() => $_ensure(17);

  @$pb.TagNumber(23)
  AgentResponseCompletedEvent get agentResponseCompleted => $_getN(18);
  @$pb.TagNumber(23)
  set agentResponseCompleted(AgentResponseCompletedEvent v) { setField(23, v); }
  @$pb.TagNumber(23)
  $core.bool hasAgentResponseCompleted() => $_has(18);
  @$pb.TagNumber(23)
  void clearAgentResponseCompleted() => clearField(23);
  @$pb.TagNumber(23)
  AgentResponseCompletedEvent ensureAgentResponseCompleted() => $_ensure(18);

  @$pb.TagNumber(24)
  SpeechTurnDetectionEvent get speechTurnDetection => $_getN(19);
  @$pb.TagNumber(24)
  set speechTurnDetection(SpeechTurnDetectionEvent v) { setField(24, v); }
  @$pb.TagNumber(24)
  $core.bool hasSpeechTurnDetection() => $_has(19);
  @$pb.TagNumber(24)
  void clearSpeechTurnDetection() => clearField(24);
  @$pb.TagNumber(24)
  SpeechTurnDetectionEvent ensureSpeechTurnDetection() => $_ensure(19);

  @$pb.TagNumber(25)
  TurnLifecycleEvent get turnLifecycle => $_getN(20);
  @$pb.TagNumber(25)
  set turnLifecycle(TurnLifecycleEvent v) { setField(25, v); }
  @$pb.TagNumber(25)
  $core.bool hasTurnLifecycle() => $_has(20);
  @$pb.TagNumber(25)
  void clearTurnLifecycle() => clearField(25);
  @$pb.TagNumber(25)
  TurnLifecycleEvent ensureTurnLifecycle() => $_ensure(20);

  @$pb.TagNumber(26)
  WakeWordDetectedEvent get wakewordDetected => $_getN(21);
  @$pb.TagNumber(26)
  set wakewordDetected(WakeWordDetectedEvent v) { setField(26, v); }
  @$pb.TagNumber(26)
  $core.bool hasWakewordDetected() => $_has(21);
  @$pb.TagNumber(26)
  void clearWakewordDetected() => clearField(26);
  @$pb.TagNumber(26)
  WakeWordDetectedEvent ensureWakewordDetected() => $_ensure(21);

  @$pb.TagNumber(27)
  AudioLevelEvent get audioLevel => $_getN(22);
  @$pb.TagNumber(27)
  set audioLevel(AudioLevelEvent v) { setField(27, v); }
  @$pb.TagNumber(27)
  $core.bool hasAudioLevel() => $_has(22);
  @$pb.TagNumber(27)
  void clearAudioLevel() => clearField(27);
  @$pb.TagNumber(27)
  AudioLevelEvent ensureAudioLevel() => $_ensure(22);

  @$pb.TagNumber(28)
  ComponentProgressEvent get componentProgress => $_getN(23);
  @$pb.TagNumber(28)
  set componentProgress(ComponentProgressEvent v) { setField(28, v); }
  @$pb.TagNumber(28)
  $core.bool hasComponentProgress() => $_has(23);
  @$pb.TagNumber(28)
  void clearComponentProgress() => clearField(28);
  @$pb.TagNumber(28)
  ComponentProgressEvent ensureComponentProgress() => $_ensure(23);

  /// Correlation fields shared by streaming and one-shot voice turns.
  @$pb.TagNumber(30)
  $core.String get sessionId => $_getSZ(24);
  @$pb.TagNumber(30)
  set sessionId($core.String v) { $_setString(24, v); }
  @$pb.TagNumber(30)
  $core.bool hasSessionId() => $_has(24);
  @$pb.TagNumber(30)
  void clearSessionId() => clearField(30);

  @$pb.TagNumber(31)
  $core.String get turnId => $_getSZ(25);
  @$pb.TagNumber(31)
  set turnId($core.String v) { $_setString(25, v); }
  @$pb.TagNumber(31)
  $core.bool hasTurnId() => $_has(25);
  @$pb.TagNumber(31)
  void clearTurnId() => clearField(31);

  @$pb.TagNumber(32)
  $core.String get requestId => $_getSZ(26);
  @$pb.TagNumber(32)
  set requestId($core.String v) { $_setString(26, v); }
  @$pb.TagNumber(32)
  $core.bool hasRequestId() => $_has(26);
  @$pb.TagNumber(32)
  void clearRequestId() => clearField(32);

  @$pb.TagNumber(33)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(27);
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
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (audioStartUs != null) {
      $result.audioStartUs = audioStartUs;
    }
    if (audioEndUs != null) {
      $result.audioEndUs = audioEndUs;
    }
    if (languageCode != null) {
      $result.languageCode = languageCode;
    }
    if (segmentIndex != null) {
      $result.segmentIndex = segmentIndex;
    }
    return $result;
  }
  UserSaidEvent._() : super();
  factory UserSaidEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UserSaidEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'UserSaidEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..aInt64(4, _omitFieldNames ? '' : 'audioStartUs')
    ..aInt64(5, _omitFieldNames ? '' : 'audioEndUs')
    ..aOS(6, _omitFieldNames ? '' : 'languageCode')
    ..a<$core.int>(7, _omitFieldNames ? '' : 'segmentIndex', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UserSaidEvent clone() => UserSaidEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UserSaidEvent copyWith(void Function(UserSaidEvent) updates) => super.copyWith((message) => updates(message as UserSaidEvent)) as UserSaidEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UserSaidEvent create() => UserSaidEvent._();
  UserSaidEvent createEmptyInstance() => create();
  static $pb.PbList<UserSaidEvent> createRepeated() => $pb.PbList<UserSaidEvent>();
  @$core.pragma('dart2js:noInline')
  static UserSaidEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserSaidEvent>(create);
  static UserSaidEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get confidence => $_getN(2);
  @$pb.TagNumber(3)
  set confidence($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasConfidence() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfidence() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get audioStartUs => $_getI64(3);
  @$pb.TagNumber(4)
  set audioStartUs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAudioStartUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearAudioStartUs() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get audioEndUs => $_getI64(4);
  @$pb.TagNumber(5)
  set audioEndUs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAudioEndUs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioEndUs() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get languageCode => $_getSZ(5);
  @$pb.TagNumber(6)
  set languageCode($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLanguageCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearLanguageCode() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get segmentIndex => $_getIZ(6);
  @$pb.TagNumber(7)
  set segmentIndex($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSegmentIndex() => $_has(6);
  @$pb.TagNumber(7)
  void clearSegmentIndex() => clearField(7);
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
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (tokenId != null) {
      $result.tokenId = tokenId;
    }
    if (logprob != null) {
      $result.logprob = logprob;
    }
    if (finishReason != null) {
      $result.finishReason = finishReason;
    }
    return $result;
  }
  AssistantTokenEvent._() : super();
  factory AssistantTokenEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AssistantTokenEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AssistantTokenEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..e<TokenKind>(3, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: TokenKind.TOKEN_KIND_UNSPECIFIED, valueOf: TokenKind.valueOf, enumValues: TokenKind.values)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'tokenId', $pb.PbFieldType.OU3)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'logprob', $pb.PbFieldType.OF)
    ..aOS(6, _omitFieldNames ? '' : 'finishReason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AssistantTokenEvent clone() => AssistantTokenEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AssistantTokenEvent copyWith(void Function(AssistantTokenEvent) updates) => super.copyWith((message) => updates(message as AssistantTokenEvent)) as AssistantTokenEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AssistantTokenEvent create() => AssistantTokenEvent._();
  AssistantTokenEvent createEmptyInstance() => create();
  static $pb.PbList<AssistantTokenEvent> createRepeated() => $pb.PbList<AssistantTokenEvent>();
  @$core.pragma('dart2js:noInline')
  static AssistantTokenEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AssistantTokenEvent>(create);
  static AssistantTokenEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => clearField(2);

  @$pb.TagNumber(3)
  TokenKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(TokenKind v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get tokenId => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokenId($core.int v) { $_setUnsignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTokenId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokenId() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get logprob => $_getN(4);
  @$pb.TagNumber(5)
  set logprob($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLogprob() => $_has(4);
  @$pb.TagNumber(5)
  void clearLogprob() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get finishReason => $_getSZ(5);
  @$pb.TagNumber(6)
  set finishReason($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasFinishReason() => $_has(5);
  @$pb.TagNumber(6)
  void clearFinishReason() => clearField(6);
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
    final $result = create();
    if (pcm != null) {
      $result.pcm = pcm;
    }
    if (sampleRateHz != null) {
      $result.sampleRateHz = sampleRateHz;
    }
    if (channels != null) {
      $result.channels = channels;
    }
    if (encoding != null) {
      $result.encoding = encoding;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (chunkIndex != null) {
      $result.chunkIndex = chunkIndex;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    return $result;
  }
  AudioFrameEvent._() : super();
  factory AudioFrameEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AudioFrameEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AudioFrameEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'pcm', $pb.PbFieldType.OY)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'sampleRateHz', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'channels', $pb.PbFieldType.O3)
    ..e<AudioEncoding>(4, _omitFieldNames ? '' : 'encoding', $pb.PbFieldType.OE, defaultOrMaker: AudioEncoding.AUDIO_ENCODING_UNSPECIFIED, valueOf: AudioEncoding.valueOf, enumValues: AudioEncoding.values)
    ..aOB(5, _omitFieldNames ? '' : 'isFinal')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'chunkIndex', $pb.PbFieldType.O3)
    ..aInt64(7, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AudioFrameEvent clone() => AudioFrameEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AudioFrameEvent copyWith(void Function(AudioFrameEvent) updates) => super.copyWith((message) => updates(message as AudioFrameEvent)) as AudioFrameEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioFrameEvent create() => AudioFrameEvent._();
  AudioFrameEvent createEmptyInstance() => create();
  static $pb.PbList<AudioFrameEvent> createRepeated() => $pb.PbList<AudioFrameEvent>();
  @$core.pragma('dart2js:noInline')
  static AudioFrameEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AudioFrameEvent>(create);
  static AudioFrameEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get pcm => $_getN(0);
  @$pb.TagNumber(1)
  set pcm($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPcm() => $_has(0);
  @$pb.TagNumber(1)
  void clearPcm() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get sampleRateHz => $_getIZ(1);
  @$pb.TagNumber(2)
  set sampleRateHz($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSampleRateHz() => $_has(1);
  @$pb.TagNumber(2)
  void clearSampleRateHz() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get channels => $_getIZ(2);
  @$pb.TagNumber(3)
  set channels($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasChannels() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannels() => clearField(3);

  @$pb.TagNumber(4)
  AudioEncoding get encoding => $_getN(3);
  @$pb.TagNumber(4)
  set encoding(AudioEncoding v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasEncoding() => $_has(3);
  @$pb.TagNumber(4)
  void clearEncoding() => clearField(4);

  /// True for the final audio chunk in a TTS/voice-agent audio stream.
  @$pb.TagNumber(5)
  $core.bool get isFinal => $_getBF(4);
  @$pb.TagNumber(5)
  set isFinal($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIsFinal() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsFinal() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get chunkIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkIndex($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasChunkIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkIndex() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get durationMs => $_getI64(6);
  @$pb.TagNumber(7)
  set durationMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearDurationMs() => clearField(7);
}

/// Voice Activity Detection output. Frontends usually do not need this —
/// exposed for debugging and custom UIs (waveform highlighting, etc.).
/// IDL-18: `type` uses the canonical VADStreamEventKind enum from
/// vad_options.proto (the hand-rolled VADEventType was deleted).
class VADEvent extends $pb.GeneratedMessage {
  factory VADEvent({
    $11.VADStreamEventKind? type,
    $fixnum.Int64? frameOffsetUs,
    $core.double? confidence,
    $core.bool? isSpeech,
    $core.double? speechDurationMs,
    $core.double? silenceDurationMs,
    $core.double? noiseFloorDb,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (frameOffsetUs != null) {
      $result.frameOffsetUs = frameOffsetUs;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (isSpeech != null) {
      $result.isSpeech = isSpeech;
    }
    if (speechDurationMs != null) {
      $result.speechDurationMs = speechDurationMs;
    }
    if (silenceDurationMs != null) {
      $result.silenceDurationMs = silenceDurationMs;
    }
    if (noiseFloorDb != null) {
      $result.noiseFloorDb = noiseFloorDb;
    }
    return $result;
  }
  VADEvent._() : super();
  factory VADEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VADEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<$11.VADStreamEventKind>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: $11.VADStreamEventKind.VAD_STREAM_EVENT_KIND_UNSPECIFIED, valueOf: $11.VADStreamEventKind.valueOf, enumValues: $11.VADStreamEventKind.values)
    ..aInt64(2, _omitFieldNames ? '' : 'frameOffsetUs')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'isSpeech')
    ..a<$core.double>(5, _omitFieldNames ? '' : 'speechDurationMs', $pb.PbFieldType.OD)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'silenceDurationMs', $pb.PbFieldType.OD)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'noiseFloorDb', $pb.PbFieldType.OD)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADEvent clone() => VADEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADEvent copyWith(void Function(VADEvent) updates) => super.copyWith((message) => updates(message as VADEvent)) as VADEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VADEvent create() => VADEvent._();
  VADEvent createEmptyInstance() => create();
  static $pb.PbList<VADEvent> createRepeated() => $pb.PbList<VADEvent>();
  @$core.pragma('dart2js:noInline')
  static VADEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADEvent>(create);
  static VADEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $11.VADStreamEventKind get type => $_getN(0);
  @$pb.TagNumber(1)
  set type($11.VADStreamEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get frameOffsetUs => $_getI64(1);
  @$pb.TagNumber(2)
  set frameOffsetUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFrameOffsetUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrameOffsetUs() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get confidence => $_getN(2);
  @$pb.TagNumber(3)
  set confidence($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasConfidence() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfidence() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isSpeech => $_getBF(3);
  @$pb.TagNumber(4)
  set isSpeech($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsSpeech() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSpeech() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get speechDurationMs => $_getN(4);
  @$pb.TagNumber(5)
  set speechDurationMs($core.double v) { $_setDouble(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSpeechDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeechDurationMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get silenceDurationMs => $_getN(5);
  @$pb.TagNumber(6)
  set silenceDurationMs($core.double v) { $_setDouble(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSilenceDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearSilenceDurationMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.double get noiseFloorDb => $_getN(6);
  @$pb.TagNumber(7)
  set noiseFloorDb($core.double v) { $_setDouble(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasNoiseFloorDb() => $_has(6);
  @$pb.TagNumber(7)
  void clearNoiseFloorDb() => clearField(7);
}

/// Assistant playback was interrupted by a barge-in. The reason distinguishes
/// user barge-in from app-initiated cancel.
class InterruptedEvent extends $pb.GeneratedMessage {
  factory InterruptedEvent({
    InterruptReason? reason,
    $core.String? detail,
  }) {
    final $result = create();
    if (reason != null) {
      $result.reason = reason;
    }
    if (detail != null) {
      $result.detail = detail;
    }
    return $result;
  }
  InterruptedEvent._() : super();
  factory InterruptedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory InterruptedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'InterruptedEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<InterruptReason>(1, _omitFieldNames ? '' : 'reason', $pb.PbFieldType.OE, defaultOrMaker: InterruptReason.INTERRUPT_REASON_UNSPECIFIED, valueOf: InterruptReason.valueOf, enumValues: InterruptReason.values)
    ..aOS(2, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  InterruptedEvent clone() => InterruptedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  InterruptedEvent copyWith(void Function(InterruptedEvent) updates) => super.copyWith((message) => updates(message as InterruptedEvent)) as InterruptedEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InterruptedEvent create() => InterruptedEvent._();
  InterruptedEvent createEmptyInstance() => create();
  static $pb.PbList<InterruptedEvent> createRepeated() => $pb.PbList<InterruptedEvent>();
  @$core.pragma('dart2js:noInline')
  static InterruptedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<InterruptedEvent>(create);
  static InterruptedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  InterruptReason get reason => $_getN(0);
  @$pb.TagNumber(1)
  set reason(InterruptReason v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get detail => $_getSZ(1);
  @$pb.TagNumber(2)
  set detail($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDetail() => $_has(1);
  @$pb.TagNumber(2)
  void clearDetail() => clearField(2);
}

/// Pipeline lifecycle state. Ordered — callers can compare numerically.
class StateChangeEvent extends $pb.GeneratedMessage {
  factory StateChangeEvent({
    PipelineState? previous,
    PipelineState? current,
  }) {
    final $result = create();
    if (previous != null) {
      $result.previous = previous;
    }
    if (current != null) {
      $result.current = current;
    }
    return $result;
  }
  StateChangeEvent._() : super();
  factory StateChangeEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StateChangeEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StateChangeEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<PipelineState>(1, _omitFieldNames ? '' : 'previous', $pb.PbFieldType.OE, defaultOrMaker: PipelineState.PIPELINE_STATE_UNSPECIFIED, valueOf: PipelineState.valueOf, enumValues: PipelineState.values)
    ..e<PipelineState>(2, _omitFieldNames ? '' : 'current', $pb.PbFieldType.OE, defaultOrMaker: PipelineState.PIPELINE_STATE_UNSPECIFIED, valueOf: PipelineState.valueOf, enumValues: PipelineState.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StateChangeEvent clone() => StateChangeEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StateChangeEvent copyWith(void Function(StateChangeEvent) updates) => super.copyWith((message) => updates(message as StateChangeEvent)) as StateChangeEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StateChangeEvent create() => StateChangeEvent._();
  StateChangeEvent createEmptyInstance() => create();
  static $pb.PbList<StateChangeEvent> createRepeated() => $pb.PbList<StateChangeEvent>();
  @$core.pragma('dart2js:noInline')
  static StateChangeEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StateChangeEvent>(create);
  static StateChangeEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PipelineState get previous => $_getN(0);
  @$pb.TagNumber(1)
  set previous(PipelineState v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrevious() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrevious() => clearField(1);

  @$pb.TagNumber(2)
  PipelineState get current => $_getN(1);
  @$pb.TagNumber(2)
  set current(PipelineState v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCurrent() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrent() => clearField(2);
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
    final $result = create();
    if (code != null) {
      $result.code = code;
    }
    if (message != null) {
      $result.message = message;
    }
    if (component != null) {
      $result.component = component;
    }
    if (isRecoverable != null) {
      $result.isRecoverable = isRecoverable;
    }
    if (operation != null) {
      $result.operation = operation;
    }
    if (detailsJson != null) {
      $result.detailsJson = detailsJson;
    }
    return $result;
  }
  ErrorEvent._() : super();
  factory ErrorEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ErrorEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ErrorEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'code', $pb.PbFieldType.O3)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'component')
    ..aOB(4, _omitFieldNames ? '' : 'isRecoverable')
    ..aOS(5, _omitFieldNames ? '' : 'operation')
    ..aOS(6, _omitFieldNames ? '' : 'detailsJson')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ErrorEvent clone() => ErrorEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ErrorEvent copyWith(void Function(ErrorEvent) updates) => super.copyWith((message) => updates(message as ErrorEvent)) as ErrorEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ErrorEvent create() => ErrorEvent._();
  ErrorEvent createEmptyInstance() => create();
  static $pb.PbList<ErrorEvent> createRepeated() => $pb.PbList<ErrorEvent>();
  @$core.pragma('dart2js:noInline')
  static ErrorEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorEvent>(create);
  static ErrorEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get component => $_getSZ(2);
  @$pb.TagNumber(3)
  set component($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasComponent() => $_has(2);
  @$pb.TagNumber(3)
  void clearComponent() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isRecoverable => $_getBF(3);
  @$pb.TagNumber(4)
  set isRecoverable($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsRecoverable() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsRecoverable() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get operation => $_getSZ(4);
  @$pb.TagNumber(5)
  set operation($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasOperation() => $_has(4);
  @$pb.TagNumber(5)
  void clearOperation() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get detailsJson => $_getSZ(5);
  @$pb.TagNumber(6)
  set detailsJson($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDetailsJson() => $_has(5);
  @$pb.TagNumber(6)
  void clearDetailsJson() => clearField(6);
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
    final $result = create();
    if (sttFinalMs != null) {
      $result.sttFinalMs = sttFinalMs;
    }
    if (llmFirstTokenMs != null) {
      $result.llmFirstTokenMs = llmFirstTokenMs;
    }
    if (ttsFirstAudioMs != null) {
      $result.ttsFirstAudioMs = ttsFirstAudioMs;
    }
    if (endToEndMs != null) {
      $result.endToEndMs = endToEndMs;
    }
    if (tokensGenerated != null) {
      $result.tokensGenerated = tokensGenerated;
    }
    if (audioSamplesPlayed != null) {
      $result.audioSamplesPlayed = audioSamplesPlayed;
    }
    if (isOverBudget != null) {
      $result.isOverBudget = isOverBudget;
    }
    if (createdAtNs != null) {
      $result.createdAtNs = createdAtNs;
    }
    if (vadFirstSpeechMs != null) {
      $result.vadFirstSpeechMs = vadFirstSpeechMs;
    }
    if (sttFirstPartialMs != null) {
      $result.sttFirstPartialMs = sttFirstPartialMs;
    }
    if (llmTotalMs != null) {
      $result.llmTotalMs = llmTotalMs;
    }
    if (ttsTotalMs != null) {
      $result.ttsTotalMs = ttsTotalMs;
    }
    return $result;
  }
  MetricsEvent._() : super();
  factory MetricsEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MetricsEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'MetricsEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'sttFinalMs', $pb.PbFieldType.OD)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'llmFirstTokenMs', $pb.PbFieldType.OD)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'ttsFirstAudioMs', $pb.PbFieldType.OD)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'endToEndMs', $pb.PbFieldType.OD)
    ..aInt64(5, _omitFieldNames ? '' : 'tokensGenerated')
    ..aInt64(6, _omitFieldNames ? '' : 'audioSamplesPlayed')
    ..aOB(7, _omitFieldNames ? '' : 'isOverBudget')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAtNs')
    ..a<$core.double>(9, _omitFieldNames ? '' : 'vadFirstSpeechMs', $pb.PbFieldType.OD)
    ..a<$core.double>(10, _omitFieldNames ? '' : 'sttFirstPartialMs', $pb.PbFieldType.OD)
    ..a<$core.double>(11, _omitFieldNames ? '' : 'llmTotalMs', $pb.PbFieldType.OD)
    ..a<$core.double>(12, _omitFieldNames ? '' : 'ttsTotalMs', $pb.PbFieldType.OD)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MetricsEvent clone() => MetricsEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MetricsEvent copyWith(void Function(MetricsEvent) updates) => super.copyWith((message) => updates(message as MetricsEvent)) as MetricsEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MetricsEvent create() => MetricsEvent._();
  MetricsEvent createEmptyInstance() => create();
  static $pb.PbList<MetricsEvent> createRepeated() => $pb.PbList<MetricsEvent>();
  @$core.pragma('dart2js:noInline')
  static MetricsEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MetricsEvent>(create);
  static MetricsEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get sttFinalMs => $_getN(0);
  @$pb.TagNumber(1)
  set sttFinalMs($core.double v) { $_setDouble(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSttFinalMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttFinalMs() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get llmFirstTokenMs => $_getN(1);
  @$pb.TagNumber(2)
  set llmFirstTokenMs($core.double v) { $_setDouble(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLlmFirstTokenMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmFirstTokenMs() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get ttsFirstAudioMs => $_getN(2);
  @$pb.TagNumber(3)
  set ttsFirstAudioMs($core.double v) { $_setDouble(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtsFirstAudioMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsFirstAudioMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get endToEndMs => $_getN(3);
  @$pb.TagNumber(4)
  set endToEndMs($core.double v) { $_setDouble(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEndToEndMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndToEndMs() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get tokensGenerated => $_getI64(4);
  @$pb.TagNumber(5)
  set tokensGenerated($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTokensGenerated() => $_has(4);
  @$pb.TagNumber(5)
  void clearTokensGenerated() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get audioSamplesPlayed => $_getI64(5);
  @$pb.TagNumber(6)
  set audioSamplesPlayed($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAudioSamplesPlayed() => $_has(5);
  @$pb.TagNumber(6)
  void clearAudioSamplesPlayed() => clearField(6);

  /// True when `end_to_end_ms` exceeded the `PipelineOptions.latency_budget_ms`
  /// configured for this run. Frontends can surface this to the UI for SLO
  /// dashboards without re-computing the threshold themselves.
  @$pb.TagNumber(7)
  $core.bool get isOverBudget => $_getBF(6);
  @$pb.TagNumber(7)
  set isOverBudget($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsOverBudget() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsOverBudget() => clearField(7);

  /// v3.1: monotonic producer-side timestamp in nanoseconds. Set by the
  /// producer (C++ dispatcher) at event-emit time; read by consumers
  /// (5-SDK perf_bench + p50 benchmark CI) to compute event-to-frontend
  /// latency without relying on wall-clock sync. Encoded as int64 so
  /// std::chrono::steady_clock::now().time_since_epoch() values fit
  /// directly (2^63 ns ≈ 292 years of runtime headroom).
  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtNs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtNs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtNs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtNs() => clearField(8);

  @$pb.TagNumber(9)
  $core.double get vadFirstSpeechMs => $_getN(8);
  @$pb.TagNumber(9)
  set vadFirstSpeechMs($core.double v) { $_setDouble(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasVadFirstSpeechMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearVadFirstSpeechMs() => clearField(9);

  @$pb.TagNumber(10)
  $core.double get sttFirstPartialMs => $_getN(9);
  @$pb.TagNumber(10)
  set sttFirstPartialMs($core.double v) { $_setDouble(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSttFirstPartialMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearSttFirstPartialMs() => clearField(10);

  @$pb.TagNumber(11)
  $core.double get llmTotalMs => $_getN(10);
  @$pb.TagNumber(11)
  set llmTotalMs($core.double v) { $_setDouble(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasLlmTotalMs() => $_has(10);
  @$pb.TagNumber(11)
  void clearLlmTotalMs() => clearField(11);

  @$pb.TagNumber(12)
  $core.double get ttsTotalMs => $_getN(11);
  @$pb.TagNumber(12)
  set ttsTotalMs($core.double v) { $_setDouble(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasTtsTotalMs() => $_has(11);
  @$pb.TagNumber(12)
  void clearTtsTotalMs() => clearField(12);
}

class AudioLevelEvent extends $pb.GeneratedMessage {
  factory AudioLevelEvent({
    $core.double? rms,
    $core.double? peak,
    $core.double? noiseFloorDb,
    $core.bool? isSpeech,
  }) {
    final $result = create();
    if (rms != null) {
      $result.rms = rms;
    }
    if (peak != null) {
      $result.peak = peak;
    }
    if (noiseFloorDb != null) {
      $result.noiseFloorDb = noiseFloorDb;
    }
    if (isSpeech != null) {
      $result.isSpeech = isSpeech;
    }
    return $result;
  }
  AudioLevelEvent._() : super();
  factory AudioLevelEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AudioLevelEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AudioLevelEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'rms', $pb.PbFieldType.OF)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'peak', $pb.PbFieldType.OF)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'noiseFloorDb', $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'isSpeech')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AudioLevelEvent clone() => AudioLevelEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AudioLevelEvent copyWith(void Function(AudioLevelEvent) updates) => super.copyWith((message) => updates(message as AudioLevelEvent)) as AudioLevelEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AudioLevelEvent create() => AudioLevelEvent._();
  AudioLevelEvent createEmptyInstance() => create();
  static $pb.PbList<AudioLevelEvent> createRepeated() => $pb.PbList<AudioLevelEvent>();
  @$core.pragma('dart2js:noInline')
  static AudioLevelEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AudioLevelEvent>(create);
  static AudioLevelEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get rms => $_getN(0);
  @$pb.TagNumber(1)
  set rms($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRms() => $_has(0);
  @$pb.TagNumber(1)
  void clearRms() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get peak => $_getN(1);
  @$pb.TagNumber(2)
  set peak($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPeak() => $_has(1);
  @$pb.TagNumber(2)
  void clearPeak() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get noiseFloorDb => $_getN(2);
  @$pb.TagNumber(3)
  set noiseFloorDb($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasNoiseFloorDb() => $_has(2);
  @$pb.TagNumber(3)
  void clearNoiseFloorDb() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isSpeech => $_getBF(3);
  @$pb.TagNumber(4)
  set isSpeech($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsSpeech() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSpeech() => clearField(4);
}

class ComponentProgressEvent extends $pb.GeneratedMessage {
  factory ComponentProgressEvent({
    VoicePipelineComponent? component,
    $core.String? operation,
    $core.double? progress,
    $core.String? message,
  }) {
    final $result = create();
    if (component != null) {
      $result.component = component;
    }
    if (operation != null) {
      $result.operation = operation;
    }
    if (progress != null) {
      $result.progress = progress;
    }
    if (message != null) {
      $result.message = message;
    }
    return $result;
  }
  ComponentProgressEvent._() : super();
  factory ComponentProgressEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ComponentProgressEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ComponentProgressEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<VoicePipelineComponent>(1, _omitFieldNames ? '' : 'component', $pb.PbFieldType.OE, defaultOrMaker: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_UNSPECIFIED, valueOf: VoicePipelineComponent.valueOf, enumValues: VoicePipelineComponent.values)
    ..aOS(2, _omitFieldNames ? '' : 'operation')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'progress', $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ComponentProgressEvent clone() => ComponentProgressEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ComponentProgressEvent copyWith(void Function(ComponentProgressEvent) updates) => super.copyWith((message) => updates(message as ComponentProgressEvent)) as ComponentProgressEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentProgressEvent create() => ComponentProgressEvent._();
  ComponentProgressEvent createEmptyInstance() => create();
  static $pb.PbList<ComponentProgressEvent> createRepeated() => $pb.PbList<ComponentProgressEvent>();
  @$core.pragma('dart2js:noInline')
  static ComponentProgressEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ComponentProgressEvent>(create);
  static ComponentProgressEvent? _defaultInstance;

  @$pb.TagNumber(1)
  VoicePipelineComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component(VoicePipelineComponent v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get operation => $_getSZ(1);
  @$pb.TagNumber(2)
  set operation($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOperation() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperation() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get progress => $_getN(2);
  @$pb.TagNumber(3)
  set progress($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasProgress() => $_has(2);
  @$pb.TagNumber(3)
  void clearProgress() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => clearField(4);
}

///  Aggregate load state across all four voice-agent components. Mirrors Swift
///  `VoiceAgentComponentStates`, Kotlin `VoiceAgentComponentStates`, RN
///  `VoiceAgentComponentStates`, Web `VoiceAgentComponentStates`, and Flutter
///  `VoiceAgentComponentStates`.
///
///  IDL-04: The former `ComponentLoadState` enum was consolidated into the
///  canonical richer `ComponentLifecycleState` (component_types.proto). Where
///  the old enum's `COMPONENT_LOAD_STATE_LOADED` value was used to mean "this
///  component is ready to use", callers now use
///  `COMPONENT_LIFECYCLE_STATE_READY`.
class VoiceAgentComponentStates extends $pb.GeneratedMessage {
  factory VoiceAgentComponentStates({
    $12.ComponentLifecycleState? sttState,
    $12.ComponentLifecycleState? llmState,
    $12.ComponentLifecycleState? ttsState,
    $12.ComponentLifecycleState? vadState,
    $core.bool? ready,
    $core.bool? anyLoading,
    $12.ComponentLifecycleState? wakewordState,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (sttState != null) {
      $result.sttState = sttState;
    }
    if (llmState != null) {
      $result.llmState = llmState;
    }
    if (ttsState != null) {
      $result.ttsState = ttsState;
    }
    if (vadState != null) {
      $result.vadState = vadState;
    }
    if (ready != null) {
      $result.ready = ready;
    }
    if (anyLoading != null) {
      $result.anyLoading = anyLoading;
    }
    if (wakewordState != null) {
      $result.wakewordState = wakewordState;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  VoiceAgentComponentStates._() : super();
  factory VoiceAgentComponentStates.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentComponentStates.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceAgentComponentStates', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<$12.ComponentLifecycleState>(1, _omitFieldNames ? '' : 'sttState', $pb.PbFieldType.OE, defaultOrMaker: $12.ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED, valueOf: $12.ComponentLifecycleState.valueOf, enumValues: $12.ComponentLifecycleState.values)
    ..e<$12.ComponentLifecycleState>(2, _omitFieldNames ? '' : 'llmState', $pb.PbFieldType.OE, defaultOrMaker: $12.ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED, valueOf: $12.ComponentLifecycleState.valueOf, enumValues: $12.ComponentLifecycleState.values)
    ..e<$12.ComponentLifecycleState>(3, _omitFieldNames ? '' : 'ttsState', $pb.PbFieldType.OE, defaultOrMaker: $12.ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED, valueOf: $12.ComponentLifecycleState.valueOf, enumValues: $12.ComponentLifecycleState.values)
    ..e<$12.ComponentLifecycleState>(4, _omitFieldNames ? '' : 'vadState', $pb.PbFieldType.OE, defaultOrMaker: $12.ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED, valueOf: $12.ComponentLifecycleState.valueOf, enumValues: $12.ComponentLifecycleState.values)
    ..aOB(5, _omitFieldNames ? '' : 'ready')
    ..aOB(6, _omitFieldNames ? '' : 'anyLoading')
    ..e<$12.ComponentLifecycleState>(7, _omitFieldNames ? '' : 'wakewordState', $pb.PbFieldType.OE, defaultOrMaker: $12.ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNSPECIFIED, valueOf: $12.ComponentLifecycleState.valueOf, enumValues: $12.ComponentLifecycleState.values)
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentComponentStates clone() => VoiceAgentComponentStates()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentComponentStates copyWith(void Function(VoiceAgentComponentStates) updates) => super.copyWith((message) => updates(message as VoiceAgentComponentStates)) as VoiceAgentComponentStates;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentComponentStates create() => VoiceAgentComponentStates._();
  VoiceAgentComponentStates createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentComponentStates> createRepeated() => $pb.PbList<VoiceAgentComponentStates>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComponentStates getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentComponentStates>(create);
  static VoiceAgentComponentStates? _defaultInstance;

  @$pb.TagNumber(1)
  $12.ComponentLifecycleState get sttState => $_getN(0);
  @$pb.TagNumber(1)
  set sttState($12.ComponentLifecycleState v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSttState() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttState() => clearField(1);

  @$pb.TagNumber(2)
  $12.ComponentLifecycleState get llmState => $_getN(1);
  @$pb.TagNumber(2)
  set llmState($12.ComponentLifecycleState v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLlmState() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmState() => clearField(2);

  @$pb.TagNumber(3)
  $12.ComponentLifecycleState get ttsState => $_getN(2);
  @$pb.TagNumber(3)
  set ttsState($12.ComponentLifecycleState v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtsState() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsState() => clearField(3);

  @$pb.TagNumber(4)
  $12.ComponentLifecycleState get vadState => $_getN(3);
  @$pb.TagNumber(4)
  set vadState($12.ComponentLifecycleState v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasVadState() => $_has(3);
  @$pb.TagNumber(4)
  void clearVadState() => clearField(4);

  /// Computed: true when stt_state, llm_state, tts_state, vad_state are all
  /// COMPONENT_LIFECYCLE_STATE_READY. Producer sets this; consumers must NOT
  /// recompute.
  @$pb.TagNumber(5)
  $core.bool get ready => $_getBF(4);
  @$pb.TagNumber(5)
  set ready($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasReady() => $_has(4);
  @$pb.TagNumber(5)
  void clearReady() => clearField(5);

  /// Computed: true when any of the four states is
  /// COMPONENT_LIFECYCLE_STATE_LOADING.
  @$pb.TagNumber(6)
  $core.bool get anyLoading => $_getBF(5);
  @$pb.TagNumber(6)
  set anyLoading($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAnyLoading() => $_has(5);
  @$pb.TagNumber(6)
  void clearAnyLoading() => clearField(6);

  @$pb.TagNumber(7)
  $12.ComponentLifecycleState get wakewordState => $_getN(6);
  @$pb.TagNumber(7)
  set wakewordState($12.ComponentLifecycleState v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasWakewordState() => $_has(6);
  @$pb.TagNumber(7)
  void clearWakewordState() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => clearField(8);
}

class VoiceSessionError extends $pb.GeneratedMessage {
  factory VoiceSessionError({
    $13.ErrorCode? code,
    $core.String? message,
    $core.String? failedComponent,
    $core.int? cAbiCode,
    $core.bool? recoverable,
  }) {
    final $result = create();
    if (code != null) {
      $result.code = code;
    }
    if (message != null) {
      $result.message = message;
    }
    if (failedComponent != null) {
      $result.failedComponent = failedComponent;
    }
    if (cAbiCode != null) {
      $result.cAbiCode = cAbiCode;
    }
    if (recoverable != null) {
      $result.recoverable = recoverable;
    }
    return $result;
  }
  VoiceSessionError._() : super();
  factory VoiceSessionError.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceSessionError.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceSessionError', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<$13.ErrorCode>(1, _omitFieldNames ? '' : 'code', $pb.PbFieldType.OE, defaultOrMaker: $13.ErrorCode.ERROR_CODE_UNSPECIFIED, valueOf: $13.ErrorCode.valueOf, enumValues: $13.ErrorCode.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'failedComponent')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'cAbiCode', $pb.PbFieldType.O3)
    ..aOB(5, _omitFieldNames ? '' : 'recoverable')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceSessionError clone() => VoiceSessionError()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceSessionError copyWith(void Function(VoiceSessionError) updates) => super.copyWith((message) => updates(message as VoiceSessionError)) as VoiceSessionError;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceSessionError create() => VoiceSessionError._();
  VoiceSessionError createEmptyInstance() => create();
  static $pb.PbList<VoiceSessionError> createRepeated() => $pb.PbList<VoiceSessionError>();
  @$core.pragma('dart2js:noInline')
  static VoiceSessionError getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceSessionError>(create);
  static VoiceSessionError? _defaultInstance;

  @$pb.TagNumber(1)
  $13.ErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code($13.ErrorCode v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get failedComponent => $_getSZ(2);
  @$pb.TagNumber(3)
  set failedComponent($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFailedComponent() => $_has(2);
  @$pb.TagNumber(3)
  void clearFailedComponent() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get cAbiCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set cAbiCode($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCAbiCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearCAbiCode() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get recoverable => $_getBF(4);
  @$pb.TagNumber(5)
  set recoverable($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRecoverable() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecoverable() => clearField(5);
}

class SessionStartedEvent extends $pb.GeneratedMessage {
  factory SessionStartedEvent({
    $core.String? sessionId,
  }) {
    final $result = create();
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    return $result;
  }
  SessionStartedEvent._() : super();
  factory SessionStartedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SessionStartedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SessionStartedEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SessionStartedEvent clone() => SessionStartedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SessionStartedEvent copyWith(void Function(SessionStartedEvent) updates) => super.copyWith((message) => updates(message as SessionStartedEvent)) as SessionStartedEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionStartedEvent create() => SessionStartedEvent._();
  SessionStartedEvent createEmptyInstance() => create();
  static $pb.PbList<SessionStartedEvent> createRepeated() => $pb.PbList<SessionStartedEvent>();
  @$core.pragma('dart2js:noInline')
  static SessionStartedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SessionStartedEvent>(create);
  static SessionStartedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => clearField(1);
}

class SessionStoppedEvent extends $pb.GeneratedMessage {
  factory SessionStoppedEvent({
    $core.String? sessionId,
    $core.String? reason,
  }) {
    final $result = create();
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    if (reason != null) {
      $result.reason = reason;
    }
    return $result;
  }
  SessionStoppedEvent._() : super();
  factory SessionStoppedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SessionStoppedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SessionStoppedEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SessionStoppedEvent clone() => SessionStoppedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SessionStoppedEvent copyWith(void Function(SessionStoppedEvent) updates) => super.copyWith((message) => updates(message as SessionStoppedEvent)) as SessionStoppedEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionStoppedEvent create() => SessionStoppedEvent._();
  SessionStoppedEvent createEmptyInstance() => create();
  static $pb.PbList<SessionStoppedEvent> createRepeated() => $pb.PbList<SessionStoppedEvent>();
  @$core.pragma('dart2js:noInline')
  static SessionStoppedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SessionStoppedEvent>(create);
  static SessionStoppedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => clearField(2);
}

class AgentResponseStartedEvent extends $pb.GeneratedMessage {
  factory AgentResponseStartedEvent({
    $core.String? turnId,
  }) {
    final $result = create();
    if (turnId != null) {
      $result.turnId = turnId;
    }
    return $result;
  }
  AgentResponseStartedEvent._() : super();
  factory AgentResponseStartedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AgentResponseStartedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AgentResponseStartedEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'turnId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AgentResponseStartedEvent clone() => AgentResponseStartedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AgentResponseStartedEvent copyWith(void Function(AgentResponseStartedEvent) updates) => super.copyWith((message) => updates(message as AgentResponseStartedEvent)) as AgentResponseStartedEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AgentResponseStartedEvent create() => AgentResponseStartedEvent._();
  AgentResponseStartedEvent createEmptyInstance() => create();
  static $pb.PbList<AgentResponseStartedEvent> createRepeated() => $pb.PbList<AgentResponseStartedEvent>();
  @$core.pragma('dart2js:noInline')
  static AgentResponseStartedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AgentResponseStartedEvent>(create);
  static AgentResponseStartedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get turnId => $_getSZ(0);
  @$pb.TagNumber(1)
  set turnId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTurnId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTurnId() => clearField(1);
}

class AgentResponseCompletedEvent extends $pb.GeneratedMessage {
  factory AgentResponseCompletedEvent({
    $core.String? turnId,
    $fixnum.Int64? responseDurationMs,
  }) {
    final $result = create();
    if (turnId != null) {
      $result.turnId = turnId;
    }
    if (responseDurationMs != null) {
      $result.responseDurationMs = responseDurationMs;
    }
    return $result;
  }
  AgentResponseCompletedEvent._() : super();
  factory AgentResponseCompletedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AgentResponseCompletedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AgentResponseCompletedEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'turnId')
    ..aInt64(2, _omitFieldNames ? '' : 'responseDurationMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AgentResponseCompletedEvent clone() => AgentResponseCompletedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AgentResponseCompletedEvent copyWith(void Function(AgentResponseCompletedEvent) updates) => super.copyWith((message) => updates(message as AgentResponseCompletedEvent)) as AgentResponseCompletedEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AgentResponseCompletedEvent create() => AgentResponseCompletedEvent._();
  AgentResponseCompletedEvent createEmptyInstance() => create();
  static $pb.PbList<AgentResponseCompletedEvent> createRepeated() => $pb.PbList<AgentResponseCompletedEvent>();
  @$core.pragma('dart2js:noInline')
  static AgentResponseCompletedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AgentResponseCompletedEvent>(create);
  static AgentResponseCompletedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get turnId => $_getSZ(0);
  @$pb.TagNumber(1)
  set turnId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTurnId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTurnId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get responseDurationMs => $_getI64(1);
  @$pb.TagNumber(2)
  set responseDurationMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasResponseDurationMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearResponseDurationMs() => clearField(2);
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
    final $result = create();
    if (kind != null) {
      $result.kind = kind;
    }
    if (speakerId != null) {
      $result.speakerId = speakerId;
    }
    if (turnStartUs != null) {
      $result.turnStartUs = turnStartUs;
    }
    if (turnEndUs != null) {
      $result.turnEndUs = turnEndUs;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (speechDurationMs != null) {
      $result.speechDurationMs = speechDurationMs;
    }
    if (silenceDurationMs != null) {
      $result.silenceDurationMs = silenceDurationMs;
    }
    return $result;
  }
  SpeechTurnDetectionEvent._() : super();
  factory SpeechTurnDetectionEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SpeechTurnDetectionEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SpeechTurnDetectionEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<SpeechTurnDetectionEventKind>(1, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: SpeechTurnDetectionEventKind.SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED, valueOf: SpeechTurnDetectionEventKind.valueOf, enumValues: SpeechTurnDetectionEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'speakerId')
    ..aInt64(3, _omitFieldNames ? '' : 'turnStartUs')
    ..aInt64(4, _omitFieldNames ? '' : 'turnEndUs')
    ..a<$core.double>(5, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'speechDurationMs', $pb.PbFieldType.OD)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'silenceDurationMs', $pb.PbFieldType.OD)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SpeechTurnDetectionEvent clone() => SpeechTurnDetectionEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SpeechTurnDetectionEvent copyWith(void Function(SpeechTurnDetectionEvent) updates) => super.copyWith((message) => updates(message as SpeechTurnDetectionEvent)) as SpeechTurnDetectionEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpeechTurnDetectionEvent create() => SpeechTurnDetectionEvent._();
  SpeechTurnDetectionEvent createEmptyInstance() => create();
  static $pb.PbList<SpeechTurnDetectionEvent> createRepeated() => $pb.PbList<SpeechTurnDetectionEvent>();
  @$core.pragma('dart2js:noInline')
  static SpeechTurnDetectionEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SpeechTurnDetectionEvent>(create);
  static SpeechTurnDetectionEvent? _defaultInstance;

  @$pb.TagNumber(1)
  SpeechTurnDetectionEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(SpeechTurnDetectionEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get speakerId => $_getSZ(1);
  @$pb.TagNumber(2)
  set speakerId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSpeakerId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeakerId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get turnStartUs => $_getI64(2);
  @$pb.TagNumber(3)
  set turnStartUs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTurnStartUs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTurnStartUs() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get turnEndUs => $_getI64(3);
  @$pb.TagNumber(4)
  set turnEndUs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTurnEndUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTurnEndUs() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get confidence => $_getN(4);
  @$pb.TagNumber(5)
  set confidence($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasConfidence() => $_has(4);
  @$pb.TagNumber(5)
  void clearConfidence() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get speechDurationMs => $_getN(5);
  @$pb.TagNumber(6)
  set speechDurationMs($core.double v) { $_setDouble(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSpeechDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearSpeechDurationMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.double get silenceDurationMs => $_getN(6);
  @$pb.TagNumber(7)
  set silenceDurationMs($core.double v) { $_setDouble(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSilenceDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearSilenceDurationMs() => clearField(7);
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
    final $result = create();
    if (kind != null) {
      $result.kind = kind;
    }
    if (turnId != null) {
      $result.turnId = turnId;
    }
    if (sessionId != null) {
      $result.sessionId = sessionId;
    }
    if (transcript != null) {
      $result.transcript = transcript;
    }
    if (response != null) {
      $result.response = response;
    }
    if (error != null) {
      $result.error = error;
    }
    if (startedAtMs != null) {
      $result.startedAtMs = startedAtMs;
    }
    if (completedAtMs != null) {
      $result.completedAtMs = completedAtMs;
    }
    return $result;
  }
  TurnLifecycleEvent._() : super();
  factory TurnLifecycleEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TurnLifecycleEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TurnLifecycleEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<TurnLifecycleEventKind>(1, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED, valueOf: TurnLifecycleEventKind.valueOf, enumValues: TurnLifecycleEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'turnId')
    ..aOS(3, _omitFieldNames ? '' : 'sessionId')
    ..aOS(4, _omitFieldNames ? '' : 'transcript')
    ..aOS(5, _omitFieldNames ? '' : 'response')
    ..aOS(6, _omitFieldNames ? '' : 'error')
    ..aInt64(7, _omitFieldNames ? '' : 'startedAtMs')
    ..aInt64(8, _omitFieldNames ? '' : 'completedAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TurnLifecycleEvent clone() => TurnLifecycleEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TurnLifecycleEvent copyWith(void Function(TurnLifecycleEvent) updates) => super.copyWith((message) => updates(message as TurnLifecycleEvent)) as TurnLifecycleEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TurnLifecycleEvent create() => TurnLifecycleEvent._();
  TurnLifecycleEvent createEmptyInstance() => create();
  static $pb.PbList<TurnLifecycleEvent> createRepeated() => $pb.PbList<TurnLifecycleEvent>();
  @$core.pragma('dart2js:noInline')
  static TurnLifecycleEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TurnLifecycleEvent>(create);
  static TurnLifecycleEvent? _defaultInstance;

  @$pb.TagNumber(1)
  TurnLifecycleEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(TurnLifecycleEventKind v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get turnId => $_getSZ(1);
  @$pb.TagNumber(2)
  set turnId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTurnId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTurnId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get sessionId => $_getSZ(2);
  @$pb.TagNumber(3)
  set sessionId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSessionId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get transcript => $_getSZ(3);
  @$pb.TagNumber(4)
  set transcript($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTranscript() => $_has(3);
  @$pb.TagNumber(4)
  void clearTranscript() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get response => $_getSZ(4);
  @$pb.TagNumber(5)
  set response($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasResponse() => $_has(4);
  @$pb.TagNumber(5)
  void clearResponse() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get error => $_getSZ(5);
  @$pb.TagNumber(6)
  set error($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get startedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set startedAtMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStartedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearStartedAtMs() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get completedAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set completedAtMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCompletedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCompletedAtMs() => clearField(8);
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
    final $result = create();
    if (wakeWord != null) {
      $result.wakeWord = wakeWord;
    }
    if (confidence != null) {
      $result.confidence = confidence;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (modelIndex != null) {
      $result.modelIndex = modelIndex;
    }
    if (durationMs != null) {
      $result.durationMs = durationMs;
    }
    return $result;
  }
  WakeWordDetectedEvent._() : super();
  factory WakeWordDetectedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WakeWordDetectedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WakeWordDetectedEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'wakeWord')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'confidence', $pb.PbFieldType.OF)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'modelIndex', $pb.PbFieldType.O3)
    ..aInt64(6, _omitFieldNames ? '' : 'durationMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WakeWordDetectedEvent clone() => WakeWordDetectedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WakeWordDetectedEvent copyWith(void Function(WakeWordDetectedEvent) updates) => super.copyWith((message) => updates(message as WakeWordDetectedEvent)) as WakeWordDetectedEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WakeWordDetectedEvent create() => WakeWordDetectedEvent._();
  WakeWordDetectedEvent createEmptyInstance() => create();
  static $pb.PbList<WakeWordDetectedEvent> createRepeated() => $pb.PbList<WakeWordDetectedEvent>();
  @$core.pragma('dart2js:noInline')
  static WakeWordDetectedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WakeWordDetectedEvent>(create);
  static WakeWordDetectedEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get wakeWord => $_getSZ(0);
  @$pb.TagNumber(1)
  set wakeWord($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasWakeWord() => $_has(0);
  @$pb.TagNumber(1)
  void clearWakeWord() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get confidence => $_getN(1);
  @$pb.TagNumber(2)
  set confidence($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConfidence() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfidence() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set modelId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearModelId() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get modelIndex => $_getIZ(4);
  @$pb.TagNumber(5)
  set modelIndex($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModelIndex() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelIndex() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get durationMs => $_getI64(5);
  @$pb.TagNumber(6)
  set durationMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDurationMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearDurationMs() => clearField(6);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
