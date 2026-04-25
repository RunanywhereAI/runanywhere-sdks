//
//  Generated code. Do not modify.
//  source: voice_events.proto
//
// @dart = 2.12

// ignore_for_file: always_use_package_imports
// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

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
  notSet
}

/// ---------------------------------------------------------------------------
/// Sum type emitted on the output edge of the VoiceAgent pipeline.
/// ---------------------------------------------------------------------------
class VoiceEvent extends $pb.GeneratedMessage {
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
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
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
    0 : VoiceEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17])
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOM<UserSaidEvent>(10, _omitFieldNames ? '' : 'userSaid', subBuilder: UserSaidEvent.create)
    ..aOM<AssistantTokenEvent>(11, _omitFieldNames ? '' : 'assistantToken', subBuilder: AssistantTokenEvent.create)
    ..aOM<AudioFrameEvent>(12, _omitFieldNames ? '' : 'audio', subBuilder: AudioFrameEvent.create)
    ..aOM<VADEvent>(13, _omitFieldNames ? '' : 'vad', subBuilder: VADEvent.create)
    ..aOM<InterruptedEvent>(14, _omitFieldNames ? '' : 'interrupted', subBuilder: InterruptedEvent.create)
    ..aOM<StateChangeEvent>(15, _omitFieldNames ? '' : 'state', subBuilder: StateChangeEvent.create)
    ..aOM<ErrorEvent>(16, _omitFieldNames ? '' : 'error', subBuilder: ErrorEvent.create)
    ..aOM<MetricsEvent>(17, _omitFieldNames ? '' : 'metrics', subBuilder: MetricsEvent.create)
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
}

/// User speech finalized by STT (is_final=false → partial hypothesis).
class UserSaidEvent extends $pb.GeneratedMessage {
  factory UserSaidEvent({
    $core.String? text,
    $core.bool? isFinal,
    $core.double? confidence,
    $fixnum.Int64? audioStartUs,
    $fixnum.Int64? audioEndUs,
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
}

/// Single token decoded by the LLM. is_final=true on the last token of a
/// response (end-of-stream marker).
class AssistantTokenEvent extends $pb.GeneratedMessage {
  factory AssistantTokenEvent({
    $core.String? text,
    $core.bool? isFinal,
    TokenKind? kind,
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
    return $result;
  }
  AssistantTokenEvent._() : super();
  factory AssistantTokenEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AssistantTokenEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AssistantTokenEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..e<TokenKind>(3, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: TokenKind.TOKEN_KIND_UNSPECIFIED, valueOf: TokenKind.valueOf, enumValues: TokenKind.values)
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
}

/// A chunk of synthesized PCM audio, ready for the sink. The frontend is
/// expected to copy the bytes out; the C ABI does NOT retain ownership.
class AudioFrameEvent extends $pb.GeneratedMessage {
  factory AudioFrameEvent({
    $core.List<$core.int>? pcm,
    $core.int? sampleRateHz,
    $core.int? channels,
    AudioEncoding? encoding,
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
}

/// Voice Activity Detection output. Frontends usually do not need this —
/// exposed for debugging and custom UIs (waveform highlighting, etc.).
class VADEvent extends $pb.GeneratedMessage {
  factory VADEvent({
    VADEventType? type,
    $fixnum.Int64? frameOffsetUs,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (frameOffsetUs != null) {
      $result.frameOffsetUs = frameOffsetUs;
    }
    return $result;
  }
  VADEvent._() : super();
  factory VADEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VADEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VADEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<VADEventType>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: VADEventType.VAD_EVENT_UNSPECIFIED, valueOf: VADEventType.valueOf, enumValues: VADEventType.values)
    ..aInt64(2, _omitFieldNames ? '' : 'frameOffsetUs')
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
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
