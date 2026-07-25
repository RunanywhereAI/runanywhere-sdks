// This is a generated file - do not edit.
//
// Generated from diarization.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'diarization.pbenum.dart';
import 'errors.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'diarization.pbenum.dart';

class DiarizationOptions extends $pb.GeneratedMessage {
  factory DiarizationOptions({
    $core.int? sampleRateHz,
    $core.int? channelCount,
    DiarizationAudioEncoding? encoding,
    $core.double? threshold,
    $fixnum.Int64? minimumDurationMs,
    $fixnum.Int64? mergeGapMs,
  }) {
    final result = create();
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (channelCount != null) result.channelCount = channelCount;
    if (encoding != null) result.encoding = encoding;
    if (threshold != null) result.threshold = threshold;
    if (minimumDurationMs != null) result.minimumDurationMs = minimumDurationMs;
    if (mergeGapMs != null) result.mergeGapMs = mergeGapMs;
    return result;
  }

  DiarizationOptions._();

  factory DiarizationOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiarizationOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiarizationOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'sampleRateHz')
    ..aI(2, _omitFieldNames ? '' : 'channelCount')
    ..aE<DiarizationAudioEncoding>(3, _omitFieldNames ? '' : 'encoding',
        enumValues: DiarizationAudioEncoding.values)
    ..aD(4, _omitFieldNames ? '' : 'threshold', fieldType: $pb.PbFieldType.OF)
    ..aInt64(5, _omitFieldNames ? '' : 'minimumDurationMs')
    ..aInt64(6, _omitFieldNames ? '' : 'mergeGapMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationOptions copyWith(void Function(DiarizationOptions) updates) =>
      super.copyWith((message) => updates(message as DiarizationOptions))
          as DiarizationOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiarizationOptions create() => DiarizationOptions._();
  @$core.override
  DiarizationOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiarizationOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiarizationOptions>(create);
  static DiarizationOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get sampleRateHz => $_getIZ(0);
  @$pb.TagNumber(1)
  set sampleRateHz($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSampleRateHz() => $_has(0);
  @$pb.TagNumber(1)
  void clearSampleRateHz() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get channelCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set channelCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasChannelCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannelCount() => $_clearField(2);

  @$pb.TagNumber(3)
  DiarizationAudioEncoding get encoding => $_getN(2);
  @$pb.TagNumber(3)
  set encoding(DiarizationAudioEncoding value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasEncoding() => $_has(2);
  @$pb.TagNumber(3)
  void clearEncoding() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get threshold => $_getN(3);
  @$pb.TagNumber(4)
  set threshold($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasThreshold() => $_has(3);
  @$pb.TagNumber(4)
  void clearThreshold() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get minimumDurationMs => $_getI64(4);
  @$pb.TagNumber(5)
  set minimumDurationMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMinimumDurationMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearMinimumDurationMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get mergeGapMs => $_getI64(5);
  @$pb.TagNumber(6)
  set mergeGapMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMergeGapMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearMergeGapMs() => $_clearField(6);
}

class DiarizationRequest extends $pb.GeneratedMessage {
  factory DiarizationRequest({
    $core.List<$core.int>? audioData,
    DiarizationOptions? options,
  }) {
    final result = create();
    if (audioData != null) result.audioData = audioData;
    if (options != null) result.options = options;
    return result;
  }

  DiarizationRequest._();

  factory DiarizationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiarizationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiarizationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'audioData', $pb.PbFieldType.OY)
    ..aOM<DiarizationOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: DiarizationOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationRequest copyWith(void Function(DiarizationRequest) updates) =>
      super.copyWith((message) => updates(message as DiarizationRequest))
          as DiarizationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiarizationRequest create() => DiarizationRequest._();
  @$core.override
  DiarizationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiarizationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiarizationRequest>(create);
  static DiarizationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get audioData => $_getN(0);
  @$pb.TagNumber(1)
  set audioData($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAudioData() => $_has(0);
  @$pb.TagNumber(1)
  void clearAudioData() => $_clearField(1);

  @$pb.TagNumber(2)
  DiarizationOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(DiarizationOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  DiarizationOptions ensureOptions() => $_ensure(1);
}

class DiarizationSegment extends $pb.GeneratedMessage {
  factory DiarizationSegment({
    $fixnum.Int64? startMs,
    $fixnum.Int64? endMs,
    $core.int? speakerIndex,
    $core.String? speakerId,
  }) {
    final result = create();
    if (startMs != null) result.startMs = startMs;
    if (endMs != null) result.endMs = endMs;
    if (speakerIndex != null) result.speakerIndex = speakerIndex;
    if (speakerId != null) result.speakerId = speakerId;
    return result;
  }

  DiarizationSegment._();

  factory DiarizationSegment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiarizationSegment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiarizationSegment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'startMs')
    ..aInt64(2, _omitFieldNames ? '' : 'endMs')
    ..aI(3, _omitFieldNames ? '' : 'speakerIndex')
    ..aOS(4, _omitFieldNames ? '' : 'speakerId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationSegment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationSegment copyWith(void Function(DiarizationSegment) updates) =>
      super.copyWith((message) => updates(message as DiarizationSegment))
          as DiarizationSegment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiarizationSegment create() => DiarizationSegment._();
  @$core.override
  DiarizationSegment createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiarizationSegment getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiarizationSegment>(create);
  static DiarizationSegment? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get startMs => $_getI64(0);
  @$pb.TagNumber(1)
  set startMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStartMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get endMs => $_getI64(1);
  @$pb.TagNumber(2)
  set endMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEndMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearEndMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get speakerIndex => $_getIZ(2);
  @$pb.TagNumber(3)
  set speakerIndex($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSpeakerIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearSpeakerIndex() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get speakerId => $_getSZ(3);
  @$pb.TagNumber(4)
  set speakerId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSpeakerId() => $_has(3);
  @$pb.TagNumber(4)
  void clearSpeakerId() => $_clearField(4);
}

class DiarizationResult extends $pb.GeneratedMessage {
  factory DiarizationResult({
    $core.Iterable<DiarizationSegment>? segments,
    $core.int? speakerCount,
    $fixnum.Int64? audioDurationMs,
    $fixnum.Int64? processingTimeMs,
    $core.String? modelId,
  }) {
    final result = create();
    if (segments != null) result.segments.addAll(segments);
    if (speakerCount != null) result.speakerCount = speakerCount;
    if (audioDurationMs != null) result.audioDurationMs = audioDurationMs;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  DiarizationResult._();

  factory DiarizationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiarizationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiarizationResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<DiarizationSegment>(1, _omitFieldNames ? '' : 'segments',
        subBuilder: DiarizationSegment.create)
    ..aI(2, _omitFieldNames ? '' : 'speakerCount')
    ..aInt64(3, _omitFieldNames ? '' : 'audioDurationMs')
    ..aInt64(4, _omitFieldNames ? '' : 'processingTimeMs')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationResult copyWith(void Function(DiarizationResult) updates) =>
      super.copyWith((message) => updates(message as DiarizationResult))
          as DiarizationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiarizationResult create() => DiarizationResult._();
  @$core.override
  DiarizationResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiarizationResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiarizationResult>(create);
  static DiarizationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DiarizationSegment> get segments => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get speakerCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set speakerCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSpeakerCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearSpeakerCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get audioDurationMs => $_getI64(2);
  @$pb.TagNumber(3)
  set audioDurationMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAudioDurationMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearAudioDurationMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get processingTimeMs => $_getI64(3);
  @$pb.TagNumber(4)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProcessingTimeMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearProcessingTimeMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);
}

/// UPDATE and FINAL carry a complete snapshot of the session hypothesis, not a
/// delta. Speaker indices/IDs are stable only within one offline call or stream
/// session. Segments belonging to different speakers may overlap.
class DiarizationStreamEvent extends $pb.GeneratedMessage {
  factory DiarizationStreamEvent({
    $fixnum.Int64? sessionId,
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    DiarizationStreamEventKind? kind,
    DiarizationResult? result,
    $0.SDKError? error,
  }) {
    final result$ = create();
    if (sessionId != null) result$.sessionId = sessionId;
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (kind != null) result$.kind = kind;
    if (result != null) result$.result = result;
    if (error != null) result$.error = error;
    return result$;
  }

  DiarizationStreamEvent._();

  factory DiarizationStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DiarizationStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DiarizationStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sessionId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampUs')
    ..aE<DiarizationStreamEventKind>(4, _omitFieldNames ? '' : 'kind',
        enumValues: DiarizationStreamEventKind.values)
    ..aOM<DiarizationResult>(5, _omitFieldNames ? '' : 'result',
        subBuilder: DiarizationResult.create)
    ..aOM<$0.SDKError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DiarizationStreamEvent copyWith(
          void Function(DiarizationStreamEvent) updates) =>
      super.copyWith((message) => updates(message as DiarizationStreamEvent))
          as DiarizationStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DiarizationStreamEvent create() => DiarizationStreamEvent._();
  @$core.override
  DiarizationStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DiarizationStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DiarizationStreamEvent>(create);
  static DiarizationStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sessionId => $_getI64(0);
  @$pb.TagNumber(1)
  set sessionId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get seq => $_getI64(1);
  @$pb.TagNumber(2)
  set seq($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSeq() => $_has(1);
  @$pb.TagNumber(2)
  void clearSeq() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampUs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampUs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestampUs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampUs() => $_clearField(3);

  @$pb.TagNumber(4)
  DiarizationStreamEventKind get kind => $_getN(3);
  @$pb.TagNumber(4)
  set kind(DiarizationStreamEventKind value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(4)
  void clearKind() => $_clearField(4);

  @$pb.TagNumber(5)
  DiarizationResult get result => $_getN(4);
  @$pb.TagNumber(5)
  set result(DiarizationResult value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasResult() => $_has(4);
  @$pb.TagNumber(5)
  void clearResult() => $_clearField(5);
  @$pb.TagNumber(5)
  DiarizationResult ensureResult() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error($0.SDKError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.SDKError ensureError() => $_ensure(5);
}

/// Logical capability contract. Native SDKs use the proto-byte C ABI; this
/// declaration keeps generated API documentation and future transports aligned.
/// For Stream, each client message is one audio feed and closing the client side
/// requests the final snapshot; transport cancellation cancels the session.
class DiarizationApi {
  final $pb.RpcClient _client;

  DiarizationApi(this._client);

  $async.Future<DiarizationResult> diarize(
          $pb.ClientContext? ctx, DiarizationRequest request) =>
      _client.invoke<DiarizationResult>(
          ctx, 'Diarization', 'Diarize', request, DiarizationResult());
  $async.Future<DiarizationStreamEvent> stream(
          $pb.ClientContext? ctx, DiarizationRequest request) =>
      _client.invoke<DiarizationStreamEvent>(
          ctx, 'Diarization', 'Stream', request, DiarizationStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
