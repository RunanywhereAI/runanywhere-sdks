///
//  Generated code. Do not modify.
//  source: voice_events.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

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
  notSet
}

class VoiceEvent extends $pb.GeneratedMessage {
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
    0 : VoiceEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23])
    ..a<$fixnum.Int64>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampUs')
    ..aOM<UserSaidEvent>(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'userSaid', subBuilder: UserSaidEvent.create)
    ..aOM<AssistantTokenEvent>(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'assistantToken', subBuilder: AssistantTokenEvent.create)
    ..aOM<AudioFrameEvent>(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audio', subBuilder: AudioFrameEvent.create)
    ..aOM<VADEvent>(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vad', subBuilder: VADEvent.create)
    ..aOM<InterruptedEvent>(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'interrupted', subBuilder: InterruptedEvent.create)
    ..aOM<StateChangeEvent>(15, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'state', subBuilder: StateChangeEvent.create)
    ..aOM<ErrorEvent>(16, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'error', subBuilder: ErrorEvent.create)
    ..aOM<MetricsEvent>(17, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'metrics', subBuilder: MetricsEvent.create)
    ..aOM<VoiceAgentComponentStates>(18, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'componentStateChanged', subBuilder: VoiceAgentComponentStates.create)
    ..aOM<VoiceSessionError>(19, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionError', subBuilder: VoiceSessionError.create)
    ..aOM<SessionStartedEvent>(20, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionStarted', subBuilder: SessionStartedEvent.create)
    ..aOM<SessionStoppedEvent>(21, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sessionStopped', subBuilder: SessionStoppedEvent.create)
    ..aOM<AgentResponseStartedEvent>(22, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'agentResponseStarted', subBuilder: AgentResponseStartedEvent.create)
    ..aOM<AgentResponseCompletedEvent>(23, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'agentResponseCompleted', subBuilder: AgentResponseCompletedEvent.create)
    ..hasRequiredFields = false
  ;

  VoiceEvent._() : super();
  factory VoiceEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
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
  }) {
    final _result = create();
    if (seq != null) {
      _result.seq = seq;
    }
    if (timestampUs != null) {
      _result.timestampUs = timestampUs;
    }
    if (userSaid != null) {
      _result.userSaid = userSaid;
    }
    if (assistantToken != null) {
      _result.assistantToken = assistantToken;
    }
    if (audio != null) {
      _result.audio = audio;
    }
    if (vad != null) {
      _result.vad = vad;
    }
    if (interrupted != null) {
      _result.interrupted = interrupted;
    }
    if (state != null) {
      _result.state = state;
    }
    if (error != null) {
      _result.error = error;
    }
    if (metrics != null) {
      _result.metrics = metrics;
    }
    if (componentStateChanged != null) {
      _result.componentStateChanged = componentStateChanged;
    }
    if (sessionError != null) {
      _result.sessionError = sessionError;
    }
    if (sessionStarted != null) {
      _result.sessionStarted = sessionStarted;
    }
    if (sessionStopped != null) {
      _result.sessionStopped = sessionStopped;
    }
    if (agentResponseStarted != null) {
      _result.agentResponseStarted = agentResponseStarted;
    }
    if (agentResponseCompleted != null) {
      _result.agentResponseCompleted = agentResponseCompleted;
    }
    return _result;
  }
  factory VoiceEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceEvent clone() => VoiceEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceEvent copyWith(void Function(VoiceEvent) updates) => super.copyWith((message) => updates(message as VoiceEvent)) as VoiceEvent; // ignore: deprecated_member_use
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

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(10)
  UserSaidEvent get userSaid => $_getN(2);
  @$pb.TagNumber(10)
  set userSaid(UserSaidEvent v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasUserSaid() => $_has(2);
  @$pb.TagNumber(10)
  void clearUserSaid() => clearField(10);
  @$pb.TagNumber(10)
  UserSaidEvent ensureUserSaid() => $_ensure(2);

  @$pb.TagNumber(11)
  AssistantTokenEvent get assistantToken => $_getN(3);
  @$pb.TagNumber(11)
  set assistantToken(AssistantTokenEvent v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasAssistantToken() => $_has(3);
  @$pb.TagNumber(11)
  void clearAssistantToken() => clearField(11);
  @$pb.TagNumber(11)
  AssistantTokenEvent ensureAssistantToken() => $_ensure(3);

  @$pb.TagNumber(12)
  AudioFrameEvent get audio => $_getN(4);
  @$pb.TagNumber(12)
  set audio(AudioFrameEvent v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasAudio() => $_has(4);
  @$pb.TagNumber(12)
  void clearAudio() => clearField(12);
  @$pb.TagNumber(12)
  AudioFrameEvent ensureAudio() => $_ensure(4);

  @$pb.TagNumber(13)
  VADEvent get vad => $_getN(5);
  @$pb.TagNumber(13)
  set vad(VADEvent v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasVad() => $_has(5);
  @$pb.TagNumber(13)
  void clearVad() => clearField(13);
  @$pb.TagNumber(13)
  VADEvent ensureVad() => $_ensure(5);

  @$pb.TagNumber(14)
  InterruptedEvent get interrupted => $_getN(6);
  @$pb.TagNumber(14)
  set interrupted(InterruptedEvent v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasInterrupted() => $_has(6);
  @$pb.TagNumber(14)
  void clearInterrupted() => clearField(14);
  @$pb.TagNumber(14)
  InterruptedEvent ensureInterrupted() => $_ensure(6);

  @$pb.TagNumber(15)
  StateChangeEvent get state => $_getN(7);
  @$pb.TagNumber(15)
  set state(StateChangeEvent v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasState() => $_has(7);
  @$pb.TagNumber(15)
  void clearState() => clearField(15);
  @$pb.TagNumber(15)
  StateChangeEvent ensureState() => $_ensure(7);

  @$pb.TagNumber(16)
  ErrorEvent get error => $_getN(8);
  @$pb.TagNumber(16)
  set error(ErrorEvent v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(16)
  void clearError() => clearField(16);
  @$pb.TagNumber(16)
  ErrorEvent ensureError() => $_ensure(8);

  @$pb.TagNumber(17)
  MetricsEvent get metrics => $_getN(9);
  @$pb.TagNumber(17)
  set metrics(MetricsEvent v) { setField(17, v); }
  @$pb.TagNumber(17)
  $core.bool hasMetrics() => $_has(9);
  @$pb.TagNumber(17)
  void clearMetrics() => clearField(17);
  @$pb.TagNumber(17)
  MetricsEvent ensureMetrics() => $_ensure(9);

  @$pb.TagNumber(18)
  VoiceAgentComponentStates get componentStateChanged => $_getN(10);
  @$pb.TagNumber(18)
  set componentStateChanged(VoiceAgentComponentStates v) { setField(18, v); }
  @$pb.TagNumber(18)
  $core.bool hasComponentStateChanged() => $_has(10);
  @$pb.TagNumber(18)
  void clearComponentStateChanged() => clearField(18);
  @$pb.TagNumber(18)
  VoiceAgentComponentStates ensureComponentStateChanged() => $_ensure(10);

  @$pb.TagNumber(19)
  VoiceSessionError get sessionError => $_getN(11);
  @$pb.TagNumber(19)
  set sessionError(VoiceSessionError v) { setField(19, v); }
  @$pb.TagNumber(19)
  $core.bool hasSessionError() => $_has(11);
  @$pb.TagNumber(19)
  void clearSessionError() => clearField(19);
  @$pb.TagNumber(19)
  VoiceSessionError ensureSessionError() => $_ensure(11);

  @$pb.TagNumber(20)
  SessionStartedEvent get sessionStarted => $_getN(12);
  @$pb.TagNumber(20)
  set sessionStarted(SessionStartedEvent v) { setField(20, v); }
  @$pb.TagNumber(20)
  $core.bool hasSessionStarted() => $_has(12);
  @$pb.TagNumber(20)
  void clearSessionStarted() => clearField(20);
  @$pb.TagNumber(20)
  SessionStartedEvent ensureSessionStarted() => $_ensure(12);

  @$pb.TagNumber(21)
  SessionStoppedEvent get sessionStopped => $_getN(13);
  @$pb.TagNumber(21)
  set sessionStopped(SessionStoppedEvent v) { setField(21, v); }
  @$pb.TagNumber(21)
  $core.bool hasSessionStopped() => $_has(13);
  @$pb.TagNumber(21)
  void clearSessionStopped() => clearField(21);
  @$pb.TagNumber(21)
  SessionStoppedEvent ensureSessionStopped() => $_ensure(13);

  @$pb.TagNumber(22)
  AgentResponseStartedEvent get agentResponseStarted => $_getN(14);
  @$pb.TagNumber(22)
  set agentResponseStarted(AgentResponseStartedEvent v) { setField(22, v); }
  @$pb.TagNumber(22)
  $core.bool hasAgentResponseStarted() => $_has(14);
  @$pb.TagNumber(22)
  void clearAgentResponseStarted() => clearField(22);
  @$pb.TagNumber(22)
  AgentResponseStartedEvent ensureAgentResponseStarted() => $_ensure(14);

  @$pb.TagNumber(23)
  AgentResponseCompletedEvent get agentResponseCompleted => $_getN(15);
  @$pb.TagNumber(23)
  set agentResponseCompleted(AgentResponseCompletedEvent v) { setField(23, v); }
  @$pb.TagNumber(23)
  $core.bool hasAgentResponseCompleted() => $_has(15);
  @$pb.TagNumber(23)
  void clearAgentResponseCompleted() => clearField(23);
  @$pb.TagNumber(23)
  AgentResponseCompletedEvent ensureAgentResponseCompleted() => $_ensure(15);
}

class UserSaidEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'UserSaidEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isFinal')
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'confidence', $pb.PbFieldType.OF)
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioStartUs')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioEndUs')
    ..hasRequiredFields = false
  ;

  UserSaidEvent._() : super();
  factory UserSaidEvent({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? confidence,
    $fixnum.Int64? audioStartUs,
    $fixnum.Int64? audioEndUs,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (isFinal != null) {
      _result.isFinal = isFinal;
    }
    if (confidence != null) {
      _result.confidence = confidence;
    }
    if (audioStartUs != null) {
      _result.audioStartUs = audioStartUs;
    }
    if (audioEndUs != null) {
      _result.audioEndUs = audioEndUs;
    }
    return _result;
  }
  factory UserSaidEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory UserSaidEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  UserSaidEvent clone() => UserSaidEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  UserSaidEvent copyWith(void Function(UserSaidEvent) updates) => super.copyWith((message) => updates(message as UserSaidEvent)) as UserSaidEvent; // ignore: deprecated_member_use
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
}

class AssistantTokenEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'AssistantTokenEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isFinal')
    ..e<TokenKind>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: TokenKind.TOKEN_KIND_UNSPECIFIED, valueOf: TokenKind.valueOf, enumValues: TokenKind.values)
    ..hasRequiredFields = false
  ;

  AssistantTokenEvent._() : super();
  factory AssistantTokenEvent({
    $core.String? text,
    $core.bool? isFinal,
    TokenKind? kind,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (isFinal != null) {
      _result.isFinal = isFinal;
    }
    if (kind != null) {
      _result.kind = kind;
    }
    return _result;
  }
  factory AssistantTokenEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AssistantTokenEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AssistantTokenEvent clone() => AssistantTokenEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AssistantTokenEvent copyWith(void Function(AssistantTokenEvent) updates) => super.copyWith((message) => updates(message as AssistantTokenEvent)) as AssistantTokenEvent; // ignore: deprecated_member_use
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
}

class AudioFrameEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'AudioFrameEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'pcm', $pb.PbFieldType.OY)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sampleRateHz', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'channels', $pb.PbFieldType.O3)
    ..e<AudioEncoding>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'encoding', $pb.PbFieldType.OE, defaultOrMaker: AudioEncoding.AUDIO_ENCODING_UNSPECIFIED, valueOf: AudioEncoding.valueOf, enumValues: AudioEncoding.values)
    ..hasRequiredFields = false
  ;

  AudioFrameEvent._() : super();
  factory AudioFrameEvent({
    $core.List<$core.int>? pcm,
    $core.int? sampleRateHz,
    $core.int? channels,
    AudioEncoding? encoding,
  }) {
    final _result = create();
    if (pcm != null) {
      _result.pcm = pcm;
    }
    if (sampleRateHz != null) {
      _result.sampleRateHz = sampleRateHz;
    }
    if (channels != null) {
      _result.channels = channels;
    }
    if (encoding != null) {
      _result.encoding = encoding;
    }
    return _result;
  }
  factory AudioFrameEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AudioFrameEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AudioFrameEvent clone() => AudioFrameEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AudioFrameEvent copyWith(void Function(AudioFrameEvent) updates) => super.copyWith((message) => updates(message as AudioFrameEvent)) as AudioFrameEvent; // ignore: deprecated_member_use
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
}

class VADEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VADEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<VADEventType>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: VADEventType.VAD_EVENT_UNSPECIFIED, valueOf: VADEventType.valueOf, enumValues: VADEventType.values)
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'frameOffsetUs')
    ..hasRequiredFields = false
  ;

  VADEvent._() : super();
  factory VADEvent({
    VADEventType? type,
    $fixnum.Int64? frameOffsetUs,
  }) {
    final _result = create();
    if (type != null) {
      _result.type = type;
    }
    if (frameOffsetUs != null) {
      _result.frameOffsetUs = frameOffsetUs;
    }
    return _result;
  }
  factory VADEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VADEvent clone() => VADEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VADEvent copyWith(void Function(VADEvent) updates) => super.copyWith((message) => updates(message as VADEvent)) as VADEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VADEvent create() => VADEvent._();
  VADEvent createEmptyInstance() => create();
  static $pb.PbList<VADEvent> createRepeated() => $pb.PbList<VADEvent>();
  @$core.pragma('dart2js:noInline')
  static VADEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VADEvent>(create);
  static VADEvent? _defaultInstance;

  @$pb.TagNumber(1)
  VADEventType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(VADEventType v) { setField(1, v); }
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
}

class InterruptedEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'InterruptedEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<InterruptReason>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'reason', $pb.PbFieldType.OE, defaultOrMaker: InterruptReason.INTERRUPT_REASON_UNSPECIFIED, valueOf: InterruptReason.valueOf, enumValues: InterruptReason.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'detail')
    ..hasRequiredFields = false
  ;

  InterruptedEvent._() : super();
  factory InterruptedEvent({
    InterruptReason? reason,
    $core.String? detail,
  }) {
    final _result = create();
    if (reason != null) {
      _result.reason = reason;
    }
    if (detail != null) {
      _result.detail = detail;
    }
    return _result;
  }
  factory InterruptedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory InterruptedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  InterruptedEvent clone() => InterruptedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  InterruptedEvent copyWith(void Function(InterruptedEvent) updates) => super.copyWith((message) => updates(message as InterruptedEvent)) as InterruptedEvent; // ignore: deprecated_member_use
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

class StateChangeEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StateChangeEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<PipelineState>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'previous', $pb.PbFieldType.OE, defaultOrMaker: PipelineState.PIPELINE_STATE_UNSPECIFIED, valueOf: PipelineState.valueOf, enumValues: PipelineState.values)
    ..e<PipelineState>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'current', $pb.PbFieldType.OE, defaultOrMaker: PipelineState.PIPELINE_STATE_UNSPECIFIED, valueOf: PipelineState.valueOf, enumValues: PipelineState.values)
    ..hasRequiredFields = false
  ;

  StateChangeEvent._() : super();
  factory StateChangeEvent({
    PipelineState? previous,
    PipelineState? current,
  }) {
    final _result = create();
    if (previous != null) {
      _result.previous = previous;
    }
    if (current != null) {
      _result.current = current;
    }
    return _result;
  }
  factory StateChangeEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StateChangeEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StateChangeEvent clone() => StateChangeEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StateChangeEvent copyWith(void Function(StateChangeEvent) updates) => super.copyWith((message) => updates(message as StateChangeEvent)) as StateChangeEvent; // ignore: deprecated_member_use
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

class ErrorEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ErrorEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'code', $pb.PbFieldType.O3)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'message')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'component')
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isRecoverable')
    ..hasRequiredFields = false
  ;

  ErrorEvent._() : super();
  factory ErrorEvent({
    $core.int? code,
    $core.String? message,
    $core.String? component,
    $core.bool? isRecoverable,
  }) {
    final _result = create();
    if (code != null) {
      _result.code = code;
    }
    if (message != null) {
      _result.message = message;
    }
    if (component != null) {
      _result.component = component;
    }
    if (isRecoverable != null) {
      _result.isRecoverable = isRecoverable;
    }
    return _result;
  }
  factory ErrorEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ErrorEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ErrorEvent clone() => ErrorEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ErrorEvent copyWith(void Function(ErrorEvent) updates) => super.copyWith((message) => updates(message as ErrorEvent)) as ErrorEvent; // ignore: deprecated_member_use
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
}

class MetricsEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'MetricsEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sttFinalMs', $pb.PbFieldType.OD)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'llmFirstTokenMs', $pb.PbFieldType.OD)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ttsFirstAudioMs', $pb.PbFieldType.OD)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'endToEndMs', $pb.PbFieldType.OD)
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensGenerated')
    ..aInt64(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'audioSamplesPlayed')
    ..aOB(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isOverBudget')
    ..aInt64(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'createdAtNs')
    ..hasRequiredFields = false
  ;

  MetricsEvent._() : super();
  factory MetricsEvent({
    $core.double? sttFinalMs,
    $core.double? llmFirstTokenMs,
    $core.double? ttsFirstAudioMs,
    $core.double? endToEndMs,
    $fixnum.Int64? tokensGenerated,
    $fixnum.Int64? audioSamplesPlayed,
    $core.bool? isOverBudget,
    $fixnum.Int64? createdAtNs,
  }) {
    final _result = create();
    if (sttFinalMs != null) {
      _result.sttFinalMs = sttFinalMs;
    }
    if (llmFirstTokenMs != null) {
      _result.llmFirstTokenMs = llmFirstTokenMs;
    }
    if (ttsFirstAudioMs != null) {
      _result.ttsFirstAudioMs = ttsFirstAudioMs;
    }
    if (endToEndMs != null) {
      _result.endToEndMs = endToEndMs;
    }
    if (tokensGenerated != null) {
      _result.tokensGenerated = tokensGenerated;
    }
    if (audioSamplesPlayed != null) {
      _result.audioSamplesPlayed = audioSamplesPlayed;
    }
    if (isOverBudget != null) {
      _result.isOverBudget = isOverBudget;
    }
    if (createdAtNs != null) {
      _result.createdAtNs = createdAtNs;
    }
    return _result;
  }
  factory MetricsEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory MetricsEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  MetricsEvent clone() => MetricsEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  MetricsEvent copyWith(void Function(MetricsEvent) updates) => super.copyWith((message) => updates(message as MetricsEvent)) as MetricsEvent; // ignore: deprecated_member_use
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

  @$pb.TagNumber(7)
  $core.bool get isOverBudget => $_getBF(6);
  @$pb.TagNumber(7)
  set isOverBudget($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsOverBudget() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsOverBudget() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtNs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtNs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtNs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtNs() => clearField(8);
}

class VoiceAgentComponentStates extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceAgentComponentStates', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ComponentLoadState>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sttState', $pb.PbFieldType.OE, defaultOrMaker: ComponentLoadState.COMPONENT_LOAD_STATE_UNSPECIFIED, valueOf: ComponentLoadState.valueOf, enumValues: ComponentLoadState.values)
    ..e<ComponentLoadState>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'llmState', $pb.PbFieldType.OE, defaultOrMaker: ComponentLoadState.COMPONENT_LOAD_STATE_UNSPECIFIED, valueOf: ComponentLoadState.valueOf, enumValues: ComponentLoadState.values)
    ..e<ComponentLoadState>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ttsState', $pb.PbFieldType.OE, defaultOrMaker: ComponentLoadState.COMPONENT_LOAD_STATE_UNSPECIFIED, valueOf: ComponentLoadState.valueOf, enumValues: ComponentLoadState.values)
    ..e<ComponentLoadState>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vadState', $pb.PbFieldType.OE, defaultOrMaker: ComponentLoadState.COMPONENT_LOAD_STATE_UNSPECIFIED, valueOf: ComponentLoadState.valueOf, enumValues: ComponentLoadState.values)
    ..aOB(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ready')
    ..aOB(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'anyLoading')
    ..hasRequiredFields = false
  ;

  VoiceAgentComponentStates._() : super();
  factory VoiceAgentComponentStates({
    ComponentLoadState? sttState,
    ComponentLoadState? llmState,
    ComponentLoadState? ttsState,
    ComponentLoadState? vadState,
    $core.bool? ready,
    $core.bool? anyLoading,
  }) {
    final _result = create();
    if (sttState != null) {
      _result.sttState = sttState;
    }
    if (llmState != null) {
      _result.llmState = llmState;
    }
    if (ttsState != null) {
      _result.ttsState = ttsState;
    }
    if (vadState != null) {
      _result.vadState = vadState;
    }
    if (ready != null) {
      _result.ready = ready;
    }
    if (anyLoading != null) {
      _result.anyLoading = anyLoading;
    }
    return _result;
  }
  factory VoiceAgentComponentStates.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentComponentStates.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentComponentStates clone() => VoiceAgentComponentStates()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentComponentStates copyWith(void Function(VoiceAgentComponentStates) updates) => super.copyWith((message) => updates(message as VoiceAgentComponentStates)) as VoiceAgentComponentStates; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComponentStates create() => VoiceAgentComponentStates._();
  VoiceAgentComponentStates createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentComponentStates> createRepeated() => $pb.PbList<VoiceAgentComponentStates>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentComponentStates getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentComponentStates>(create);
  static VoiceAgentComponentStates? _defaultInstance;

  @$pb.TagNumber(1)
  ComponentLoadState get sttState => $_getN(0);
  @$pb.TagNumber(1)
  set sttState(ComponentLoadState v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasSttState() => $_has(0);
  @$pb.TagNumber(1)
  void clearSttState() => clearField(1);

  @$pb.TagNumber(2)
  ComponentLoadState get llmState => $_getN(1);
  @$pb.TagNumber(2)
  set llmState(ComponentLoadState v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLlmState() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmState() => clearField(2);

  @$pb.TagNumber(3)
  ComponentLoadState get ttsState => $_getN(2);
  @$pb.TagNumber(3)
  set ttsState(ComponentLoadState v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtsState() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsState() => clearField(3);

  @$pb.TagNumber(4)
  ComponentLoadState get vadState => $_getN(3);
  @$pb.TagNumber(4)
  set vadState(ComponentLoadState v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasVadState() => $_has(3);
  @$pb.TagNumber(4)
  void clearVadState() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get ready => $_getBF(4);
  @$pb.TagNumber(5)
  set ready($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasReady() => $_has(4);
  @$pb.TagNumber(5)
  void clearReady() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get anyLoading => $_getBF(5);
  @$pb.TagNumber(6)
  set anyLoading($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAnyLoading() => $_has(5);
  @$pb.TagNumber(6)
  void clearAnyLoading() => clearField(6);
}

class VoiceSessionError extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'VoiceSessionError', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<VoiceSessionErrorCode>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'code', $pb.PbFieldType.OE, defaultOrMaker: VoiceSessionErrorCode.VOICE_SESSION_ERROR_CODE_UNSPECIFIED, valueOf: VoiceSessionErrorCode.valueOf, enumValues: VoiceSessionErrorCode.values)
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'message')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'failedComponent')
    ..hasRequiredFields = false
  ;

  VoiceSessionError._() : super();
  factory VoiceSessionError({
    VoiceSessionErrorCode? code,
    $core.String? message,
    $core.String? failedComponent,
  }) {
    final _result = create();
    if (code != null) {
      _result.code = code;
    }
    if (message != null) {
      _result.message = message;
    }
    if (failedComponent != null) {
      _result.failedComponent = failedComponent;
    }
    return _result;
  }
  factory VoiceSessionError.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceSessionError.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceSessionError clone() => VoiceSessionError()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceSessionError copyWith(void Function(VoiceSessionError) updates) => super.copyWith((message) => updates(message as VoiceSessionError)) as VoiceSessionError; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static VoiceSessionError create() => VoiceSessionError._();
  VoiceSessionError createEmptyInstance() => create();
  static $pb.PbList<VoiceSessionError> createRepeated() => $pb.PbList<VoiceSessionError>();
  @$core.pragma('dart2js:noInline')
  static VoiceSessionError getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceSessionError>(create);
  static VoiceSessionError? _defaultInstance;

  @$pb.TagNumber(1)
  VoiceSessionErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(VoiceSessionErrorCode v) { setField(1, v); }
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
}

class SessionStartedEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SessionStartedEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  SessionStartedEvent._() : super();
  factory SessionStartedEvent() => create();
  factory SessionStartedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SessionStartedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SessionStartedEvent clone() => SessionStartedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SessionStartedEvent copyWith(void Function(SessionStartedEvent) updates) => super.copyWith((message) => updates(message as SessionStartedEvent)) as SessionStartedEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SessionStartedEvent create() => SessionStartedEvent._();
  SessionStartedEvent createEmptyInstance() => create();
  static $pb.PbList<SessionStartedEvent> createRepeated() => $pb.PbList<SessionStartedEvent>();
  @$core.pragma('dart2js:noInline')
  static SessionStartedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SessionStartedEvent>(create);
  static SessionStartedEvent? _defaultInstance;
}

class SessionStoppedEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SessionStoppedEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  SessionStoppedEvent._() : super();
  factory SessionStoppedEvent() => create();
  factory SessionStoppedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SessionStoppedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SessionStoppedEvent clone() => SessionStoppedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SessionStoppedEvent copyWith(void Function(SessionStoppedEvent) updates) => super.copyWith((message) => updates(message as SessionStoppedEvent)) as SessionStoppedEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SessionStoppedEvent create() => SessionStoppedEvent._();
  SessionStoppedEvent createEmptyInstance() => create();
  static $pb.PbList<SessionStoppedEvent> createRepeated() => $pb.PbList<SessionStoppedEvent>();
  @$core.pragma('dart2js:noInline')
  static SessionStoppedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SessionStoppedEvent>(create);
  static SessionStoppedEvent? _defaultInstance;
}

class AgentResponseStartedEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'AgentResponseStartedEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  AgentResponseStartedEvent._() : super();
  factory AgentResponseStartedEvent() => create();
  factory AgentResponseStartedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AgentResponseStartedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AgentResponseStartedEvent clone() => AgentResponseStartedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AgentResponseStartedEvent copyWith(void Function(AgentResponseStartedEvent) updates) => super.copyWith((message) => updates(message as AgentResponseStartedEvent)) as AgentResponseStartedEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static AgentResponseStartedEvent create() => AgentResponseStartedEvent._();
  AgentResponseStartedEvent createEmptyInstance() => create();
  static $pb.PbList<AgentResponseStartedEvent> createRepeated() => $pb.PbList<AgentResponseStartedEvent>();
  @$core.pragma('dart2js:noInline')
  static AgentResponseStartedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AgentResponseStartedEvent>(create);
  static AgentResponseStartedEvent? _defaultInstance;
}

class AgentResponseCompletedEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'AgentResponseCompletedEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  AgentResponseCompletedEvent._() : super();
  factory AgentResponseCompletedEvent() => create();
  factory AgentResponseCompletedEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AgentResponseCompletedEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AgentResponseCompletedEvent clone() => AgentResponseCompletedEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AgentResponseCompletedEvent copyWith(void Function(AgentResponseCompletedEvent) updates) => super.copyWith((message) => updates(message as AgentResponseCompletedEvent)) as AgentResponseCompletedEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static AgentResponseCompletedEvent create() => AgentResponseCompletedEvent._();
  AgentResponseCompletedEvent createEmptyInstance() => create();
  static $pb.PbList<AgentResponseCompletedEvent> createRepeated() => $pb.PbList<AgentResponseCompletedEvent>();
  @$core.pragma('dart2js:noInline')
  static AgentResponseCompletedEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AgentResponseCompletedEvent>(create);
  static AgentResponseCompletedEvent? _defaultInstance;
}

