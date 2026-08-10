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

import 'component_types.pbenum.dart' as $1;
import 'errors.pb.dart' as $0;
import 'model_types.pbenum.dart' as $2;
import 'vad_options.pbenum.dart' as $3;
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
  metrics,
  componentStateChanged,
  sessionError,
  turnLifecycle,
  notSet
}

/// ---------------------------------------------------------------------------
/// Sum type emitted on the output edge of the VoiceAgent pipeline.
/// ---------------------------------------------------------------------------
class VoiceEvent extends $pb.GeneratedMessage {
  factory VoiceEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampMs,
    $1.EventCategory? category,
    $0.ErrorSeverity? severity,
    VoicePipelineComponent? component,
    UserSaidEvent? userSaid,
    AssistantTokenEvent? assistantToken,
    AudioFrameEvent? audio,
    VADEvent? vad,
    InterruptedEvent? interrupted,
    StateChangeEvent? state,
    MetricsEvent? metrics,
    VoiceAgentComponentStates? componentStateChanged,
    VoiceSessionError? sessionError,
    TurnLifecycleEvent? turnLifecycle,
    $core.String? sessionId,
    $core.String? turnId,
    $core.String? requestId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (seq != null) result.seq = seq;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (category != null) result.category = category;
    if (severity != null) result.severity = severity;
    if (component != null) result.component = component;
    if (userSaid != null) result.userSaid = userSaid;
    if (assistantToken != null) result.assistantToken = assistantToken;
    if (audio != null) result.audio = audio;
    if (vad != null) result.vad = vad;
    if (interrupted != null) result.interrupted = interrupted;
    if (state != null) result.state = state;
    if (metrics != null) result.metrics = metrics;
    if (componentStateChanged != null)
      result.componentStateChanged = componentStateChanged;
    if (sessionError != null) result.sessionError = sessionError;
    if (turnLifecycle != null) result.turnLifecycle = turnLifecycle;
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
    16: VoiceEvent_Payload.metrics,
    17: VoiceEvent_Payload.componentStateChanged,
    18: VoiceEvent_Payload.sessionError,
    19: VoiceEvent_Payload.turnLifecycle,
    0: VoiceEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..aE<$1.EventCategory>(3, _omitFieldNames ? '' : 'category',
        enumValues: $1.EventCategory.values)
    ..aE<$0.ErrorSeverity>(4, _omitFieldNames ? '' : 'severity',
        enumValues: $0.ErrorSeverity.values)
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
    ..aOM<MetricsEvent>(16, _omitFieldNames ? '' : 'metrics',
        subBuilder: MetricsEvent.create)
    ..aOM<VoiceAgentComponentStates>(
        17, _omitFieldNames ? '' : 'componentStateChanged',
        subBuilder: VoiceAgentComponentStates.create)
    ..aOM<VoiceSessionError>(18, _omitFieldNames ? '' : 'sessionError',
        subBuilder: VoiceSessionError.create)
    ..aOM<TurnLifecycleEvent>(19, _omitFieldNames ? '' : 'turnLifecycle',
        subBuilder: TurnLifecycleEvent.create)
    ..aOS(20, _omitFieldNames ? '' : 'sessionId')
    ..aOS(21, _omitFieldNames ? '' : 'turnId')
    ..aOS(22, _omitFieldNames ? '' : 'requestId')
    ..m<$core.String, $core.String>(23, _omitFieldNames ? '' : 'metadata',
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

  /// Wall-clock timestamp captured at the C++ edge, in milliseconds since
  /// Unix epoch. Frontends may re-timestamp for UI display.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $1.EventCategory get category => $_getN(2);
  @$pb.TagNumber(3)
  set category($1.EventCategory value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.ErrorSeverity get severity => $_getN(3);
  @$pb.TagNumber(4)
  set severity($0.ErrorSeverity value) => $_setField(4, value);
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
  MetricsEvent get metrics => $_getN(11);
  @$pb.TagNumber(16)
  set metrics(MetricsEvent value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasMetrics() => $_has(11);
  @$pb.TagNumber(16)
  void clearMetrics() => $_clearField(16);
  @$pb.TagNumber(16)
  MetricsEvent ensureMetrics() => $_ensure(11);

  @$pb.TagNumber(17)
  VoiceAgentComponentStates get componentStateChanged => $_getN(12);
  @$pb.TagNumber(17)
  set componentStateChanged(VoiceAgentComponentStates value) =>
      $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasComponentStateChanged() => $_has(12);
  @$pb.TagNumber(17)
  void clearComponentStateChanged() => $_clearField(17);
  @$pb.TagNumber(17)
  VoiceAgentComponentStates ensureComponentStateChanged() => $_ensure(12);

  /// The one error payload in this domain.
  @$pb.TagNumber(18)
  VoiceSessionError get sessionError => $_getN(13);
  @$pb.TagNumber(18)
  set sessionError(VoiceSessionError value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasSessionError() => $_has(13);
  @$pb.TagNumber(18)
  void clearSessionError() => $_clearField(18);
  @$pb.TagNumber(18)
  VoiceSessionError ensureSessionError() => $_ensure(13);

  /// Agent-response start/complete and user-speech start/end are
  /// TurnLifecycleEventKind values, not separate arms. Session start and
  /// stop are PipelineState transitions on StateChangeEvent.
  @$pb.TagNumber(19)
  TurnLifecycleEvent get turnLifecycle => $_getN(14);
  @$pb.TagNumber(19)
  set turnLifecycle(TurnLifecycleEvent value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasTurnLifecycle() => $_has(14);
  @$pb.TagNumber(19)
  void clearTurnLifecycle() => $_clearField(19);
  @$pb.TagNumber(19)
  TurnLifecycleEvent ensureTurnLifecycle() => $_ensure(14);

  /// Correlation fields shared by streaming and one-shot voice turns.
  @$pb.TagNumber(20)
  $core.String get sessionId => $_getSZ(15);
  @$pb.TagNumber(20)
  set sessionId($core.String value) => $_setString(15, value);
  @$pb.TagNumber(20)
  $core.bool hasSessionId() => $_has(15);
  @$pb.TagNumber(20)
  void clearSessionId() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.String get turnId => $_getSZ(16);
  @$pb.TagNumber(21)
  set turnId($core.String value) => $_setString(16, value);
  @$pb.TagNumber(21)
  $core.bool hasTurnId() => $_has(16);
  @$pb.TagNumber(21)
  void clearTurnId() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.String get requestId => $_getSZ(17);
  @$pb.TagNumber(22)
  set requestId($core.String value) => $_setString(17, value);
  @$pb.TagNumber(22)
  $core.bool hasRequestId() => $_has(17);
  @$pb.TagNumber(22)
  void clearRequestId() => $_clearField(22);

  @$pb.TagNumber(23)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(18);
}

/// User speech finalized by STT (is_final=false → partial hypothesis).
class UserSaidEvent extends $pb.GeneratedMessage {
  factory UserSaidEvent({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? confidence,
    $fixnum.Int64? audioStartMs,
    $fixnum.Int64? audioEndMs,
    $core.String? language,
    $core.int? segmentIndex,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (isFinal != null) result.isFinal = isFinal;
    if (confidence != null) result.confidence = confidence;
    if (audioStartMs != null) result.audioStartMs = audioStartMs;
    if (audioEndMs != null) result.audioEndMs = audioEndMs;
    if (language != null) result.language = language;
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
    ..aInt64(4, _omitFieldNames ? '' : 'audioStartMs')
    ..aInt64(5, _omitFieldNames ? '' : 'audioEndMs')
    ..aOS(6, _omitFieldNames ? '' : 'language')
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

  /// Milliseconds from the start of ALL audio fed this session, matching
  /// OpenAI input_audio_buffer.speech_started.audio_start_ms.
  @$pb.TagNumber(4)
  $fixnum.Int64 get audioStartMs => $_getI64(3);
  @$pb.TagNumber(4)
  set audioStartMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAudioStartMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearAudioStartMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get audioEndMs => $_getI64(4);
  @$pb.TagNumber(5)
  set audioEndMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAudioEndMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearAudioEndMs() => $_clearField(5);

  /// Detected language, BCP-47. One spelling across this domain and
  /// stt_options.proto.
  @$pb.TagNumber(6)
  $core.String get language => $_getSZ(5);
  @$pb.TagNumber(6)
  set language($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLanguage() => $_has(5);
  @$pb.TagNumber(6)
  void clearLanguage() => $_clearField(6);

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
    $2.AudioEncoding? encoding,
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
    ..aE<$2.AudioEncoding>(4, _omitFieldNames ? '' : 'encoding',
        enumValues: $2.AudioEncoding.values)
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
  $2.AudioEncoding get encoding => $_getN(3);
  @$pb.TagNumber(4)
  set encoding($2.AudioEncoding value) => $_setField(4, value);
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
    $3.VADStreamEventKind? type,
    $fixnum.Int64? frameOffsetMs,
    $core.double? probability,
    $core.bool? isSpeech,
    $core.int? speechDurationMs,
    $core.int? silenceDurationMs,
    $core.double? noiseFloorDb,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (frameOffsetMs != null) result.frameOffsetMs = frameOffsetMs;
    if (probability != null) result.probability = probability;
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
    ..aE<$3.VADStreamEventKind>(1, _omitFieldNames ? '' : 'type',
        enumValues: $3.VADStreamEventKind.values)
    ..aInt64(2, _omitFieldNames ? '' : 'frameOffsetMs')
    ..aD(3, _omitFieldNames ? '' : 'probability', fieldType: $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'isSpeech')
    ..aI(5, _omitFieldNames ? '' : 'speechDurationMs')
    ..aI(6, _omitFieldNames ? '' : 'silenceDurationMs')
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
  $3.VADStreamEventKind get type => $_getN(0);
  @$pb.TagNumber(1)
  set type($3.VADStreamEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  /// Position of the analyzed frame on the session timeline, in ms.
  @$pb.TagNumber(2)
  $fixnum.Int64 get frameOffsetMs => $_getI64(1);
  @$pb.TagNumber(2)
  set frameOffsetMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFrameOffsetMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrameOffsetMs() => $_clearField(2);

  /// Same scale and caveats as VADResult.probability.
  @$pb.TagNumber(3)
  $core.double get probability => $_getN(2);
  @$pb.TagNumber(3)
  set probability($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProbability() => $_has(2);
  @$pb.TagNumber(3)
  void clearProbability() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isSpeech => $_getBF(3);
  @$pb.TagNumber(4)
  set isSpeech($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsSpeech() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSpeech() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get speechDurationMs => $_getIZ(4);
  @$pb.TagNumber(5)
  set speechDurationMs($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSpeechDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearSpeechDurationMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get silenceDurationMs => $_getIZ(5);
  @$pb.TagNumber(6)
  set silenceDurationMs($core.int value) => $_setSignedInt32(5, value);
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
    ..aD(8, _omitFieldNames ? '' : 'vadFirstSpeechMs')
    ..aD(9, _omitFieldNames ? '' : 'sttFirstPartialMs')
    ..aD(10, _omitFieldNames ? '' : 'llmTotalMs')
    ..aD(11, _omitFieldNames ? '' : 'ttsTotalMs')
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

  @$pb.TagNumber(8)
  $core.double get vadFirstSpeechMs => $_getN(7);
  @$pb.TagNumber(8)
  set vadFirstSpeechMs($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasVadFirstSpeechMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearVadFirstSpeechMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get sttFirstPartialMs => $_getN(8);
  @$pb.TagNumber(9)
  set sttFirstPartialMs($core.double value) => $_setDouble(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSttFirstPartialMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearSttFirstPartialMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.double get llmTotalMs => $_getN(9);
  @$pb.TagNumber(10)
  set llmTotalMs($core.double value) => $_setDouble(9, value);
  @$pb.TagNumber(10)
  $core.bool hasLlmTotalMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearLlmTotalMs() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.double get ttsTotalMs => $_getN(10);
  @$pb.TagNumber(11)
  set ttsTotalMs($core.double value) => $_setDouble(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTtsTotalMs() => $_has(10);
  @$pb.TagNumber(11)
  void clearTtsTotalMs() => $_clearField(11);
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
    $1.ComponentLifecycleState? sttState,
    $1.ComponentLifecycleState? llmState,
    $1.ComponentLifecycleState? ttsState,
    $1.ComponentLifecycleState? vadState,
    $core.bool? ready,
    $core.bool? anyLoading,
    $1.ComponentLifecycleState? wakewordState,
    $0.SDKError? error,
  }) {
    final result = create();
    if (sttState != null) result.sttState = sttState;
    if (llmState != null) result.llmState = llmState;
    if (ttsState != null) result.ttsState = ttsState;
    if (vadState != null) result.vadState = vadState;
    if (ready != null) result.ready = ready;
    if (anyLoading != null) result.anyLoading = anyLoading;
    if (wakewordState != null) result.wakewordState = wakewordState;
    if (error != null) result.error = error;
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
    ..aE<$1.ComponentLifecycleState>(1, _omitFieldNames ? '' : 'sttState',
        enumValues: $1.ComponentLifecycleState.values)
    ..aE<$1.ComponentLifecycleState>(2, _omitFieldNames ? '' : 'llmState',
        enumValues: $1.ComponentLifecycleState.values)
    ..aE<$1.ComponentLifecycleState>(3, _omitFieldNames ? '' : 'ttsState',
        enumValues: $1.ComponentLifecycleState.values)
    ..aE<$1.ComponentLifecycleState>(4, _omitFieldNames ? '' : 'vadState',
        enumValues: $1.ComponentLifecycleState.values)
    ..aOB(5, _omitFieldNames ? '' : 'ready')
    ..aOB(6, _omitFieldNames ? '' : 'anyLoading')
    ..aE<$1.ComponentLifecycleState>(7, _omitFieldNames ? '' : 'wakewordState',
        enumValues: $1.ComponentLifecycleState.values)
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
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
  $1.ComponentLifecycleState get sttState => $_getN(0);
  @$pb.TagNumber(1)
  set sttState($1.ComponentLifecycleState value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSttState() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttState() => $_clearField(1);

  @$pb.TagNumber(2)
  $1.ComponentLifecycleState get llmState => $_getN(1);
  @$pb.TagNumber(2)
  set llmState($1.ComponentLifecycleState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasLlmState() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmState() => $_clearField(2);

  @$pb.TagNumber(3)
  $1.ComponentLifecycleState get ttsState => $_getN(2);
  @$pb.TagNumber(3)
  set ttsState($1.ComponentLifecycleState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTtsState() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsState() => $_clearField(3);

  @$pb.TagNumber(4)
  $1.ComponentLifecycleState get vadState => $_getN(3);
  @$pb.TagNumber(4)
  set vadState($1.ComponentLifecycleState value) => $_setField(4, value);
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
  $1.ComponentLifecycleState get wakewordState => $_getN(6);
  @$pb.TagNumber(7)
  set wakewordState($1.ComponentLifecycleState value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasWakewordState() => $_has(6);
  @$pb.TagNumber(7)
  void clearWakewordState() => $_clearField(7);

  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(7);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(7);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(7);
}

class VoiceSessionError extends $pb.GeneratedMessage {
  factory VoiceSessionError({
    $0.ErrorCode? code,
    $core.String? message,
    $core.String? failedComponent,
    $core.int? cAbiCode,
    $core.bool? recoverable,
    $core.String? operation,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (failedComponent != null) result.failedComponent = failedComponent;
    if (cAbiCode != null) result.cAbiCode = cAbiCode;
    if (recoverable != null) result.recoverable = recoverable;
    if (operation != null) result.operation = operation;
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
    ..aE<$0.ErrorCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: $0.ErrorCode.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'failedComponent')
    ..aI(4, _omitFieldNames ? '' : 'cAbiCode')
    ..aOB(5, _omitFieldNames ? '' : 'recoverable')
    ..aOS(6, _omitFieldNames ? '' : 'operation')
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
  $0.ErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code($0.ErrorCode value) => $_setField(1, value);
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

  /// The raw ra_status_t (core/abi/ra_primitives.h), preserved for
  /// diagnostics alongside the canonical `code`.
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

  /// The operation that failed, e.g. "transcribe", "generate", "synthesize".
  @$pb.TagNumber(6)
  $core.String get operation => $_getSZ(5);
  @$pb.TagNumber(6)
  set operation($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOperation() => $_has(5);
  @$pb.TagNumber(6)
  void clearOperation() => $_clearField(6);
}

class TurnLifecycleEvent extends $pb.GeneratedMessage {
  factory TurnLifecycleEvent({
    TurnLifecycleEventKind? kind,
    $core.String? turnId,
    $core.String? sessionId,
    $core.String? transcript,
    $core.String? response,
    VoiceSessionError? error,
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
    ..aOM<VoiceSessionError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: VoiceSessionError.create)
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

  /// Set on KIND_FAILED. Same payload as VoiceEvent.session_error.
  @$pb.TagNumber(6)
  VoiceSessionError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(VoiceSessionError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  VoiceSessionError ensureError() => $_ensure(5);

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

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
