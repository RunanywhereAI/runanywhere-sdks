// This is a generated file - do not edit.
//
// Generated from vocoder.proto.

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

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class VocoderRequest extends $pb.GeneratedMessage {
  factory VocoderRequest({
    $core.List<$core.int>? melSpectrogramF32Le,
    $core.int? batchSize,
    $core.int? melBinCount,
    $core.int? frameCount,
  }) {
    final result = create();
    if (melSpectrogramF32Le != null)
      result.melSpectrogramF32Le = melSpectrogramF32Le;
    if (batchSize != null) result.batchSize = batchSize;
    if (melBinCount != null) result.melBinCount = melBinCount;
    if (frameCount != null) result.frameCount = frameCount;
    return result;
  }

  VocoderRequest._();

  factory VocoderRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VocoderRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VocoderRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'melSpectrogramF32Le', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'batchSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'melBinCount',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'frameCount', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VocoderRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VocoderRequest copyWith(void Function(VocoderRequest) updates) =>
      super.copyWith((message) => updates(message as VocoderRequest))
          as VocoderRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VocoderRequest create() => VocoderRequest._();
  @$core.override
  VocoderRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VocoderRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VocoderRequest>(create);
  static VocoderRequest? _defaultInstance;

  /// Contiguous IEEE-754 float32 little-endian data in [B, M, T] order.
  @$pb.TagNumber(1)
  $core.List<$core.int> get melSpectrogramF32Le => $_getN(0);
  @$pb.TagNumber(1)
  set melSpectrogramF32Le($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMelSpectrogramF32Le() => $_has(0);
  @$pb.TagNumber(1)
  void clearMelSpectrogramF32Le() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get batchSize => $_getIZ(1);
  @$pb.TagNumber(2)
  set batchSize($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBatchSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearBatchSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get melBinCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set melBinCount($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMelBinCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearMelBinCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get frameCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set frameCount($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFrameCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearFrameCount() => $_clearField(4);
}

class VocoderResult extends $pb.GeneratedMessage {
  factory VocoderResult({
    $core.List<$core.int>? samplesF32Le,
    $core.int? batchSize,
    $core.int? channelCount,
    $core.int? sampleCount,
    $core.int? sampleRateHz,
    $core.int? hopLength,
    $fixnum.Int64? processingTimeMs,
    $core.String? modelId,
  }) {
    final result = create();
    if (samplesF32Le != null) result.samplesF32Le = samplesF32Le;
    if (batchSize != null) result.batchSize = batchSize;
    if (channelCount != null) result.channelCount = channelCount;
    if (sampleCount != null) result.sampleCount = sampleCount;
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (hopLength != null) result.hopLength = hopLength;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  VocoderResult._();

  factory VocoderResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VocoderResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VocoderResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'samplesF32Le', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'batchSize', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'channelCount',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'sampleCount',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'sampleRateHz',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'hopLength', fieldType: $pb.PbFieldType.OU3)
    ..aInt64(7, _omitFieldNames ? '' : 'processingTimeMs')
    ..aOS(8, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VocoderResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VocoderResult copyWith(void Function(VocoderResult) updates) =>
      super.copyWith((message) => updates(message as VocoderResult))
          as VocoderResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VocoderResult create() => VocoderResult._();
  @$core.override
  VocoderResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VocoderResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VocoderResult>(create);
  static VocoderResult? _defaultInstance;

  /// Contiguous IEEE-754 float32 little-endian data in [B, C, S] order.
  @$pb.TagNumber(1)
  $core.List<$core.int> get samplesF32Le => $_getN(0);
  @$pb.TagNumber(1)
  set samplesF32Le($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSamplesF32Le() => $_has(0);
  @$pb.TagNumber(1)
  void clearSamplesF32Le() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get batchSize => $_getIZ(1);
  @$pb.TagNumber(2)
  set batchSize($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBatchSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearBatchSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get channelCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set channelCount($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChannelCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannelCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get sampleCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set sampleCount($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSampleCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearSampleCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get sampleRateHz => $_getIZ(4);
  @$pb.TagNumber(5)
  set sampleRateHz($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSampleRateHz() => $_has(4);
  @$pb.TagNumber(5)
  void clearSampleRateHz() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get hopLength => $_getIZ(5);
  @$pb.TagNumber(6)
  set hopLength($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHopLength() => $_has(5);
  @$pb.TagNumber(6)
  void clearHopLength() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get processingTimeMs => $_getI64(6);
  @$pb.TagNumber(7)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasProcessingTimeMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearProcessingTimeMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get modelId => $_getSZ(7);
  @$pb.TagNumber(8)
  set modelId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasModelId() => $_has(7);
  @$pb.TagNumber(8)
  void clearModelId() => $_clearField(8);
}

class VocoderApi {
  final $pb.RpcClient _client;

  VocoderApi(this._client);

  $async.Future<VocoderResult> vocode(
          $pb.ClientContext? ctx, VocoderRequest request) =>
      _client.invoke<VocoderResult>(
          ctx, 'Vocoder', 'Vocode', request, VocoderResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
