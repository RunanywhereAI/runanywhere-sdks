///
//  Generated code. Do not modify.
//  source: embeddings_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

class EmbeddingsConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'EmbeddingsConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'embeddingDimension', $pb.PbFieldType.O3)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxSequenceLength', $pb.PbFieldType.O3)
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'normalize')
    ..hasRequiredFields = false
  ;

  EmbeddingsConfiguration._() : super();
  factory EmbeddingsConfiguration({
    $core.String? modelId,
    $core.int? embeddingDimension,
    $core.int? maxSequenceLength,
    $core.bool? normalize,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (embeddingDimension != null) {
      _result.embeddingDimension = embeddingDimension;
    }
    if (maxSequenceLength != null) {
      _result.maxSequenceLength = maxSequenceLength;
    }
    if (normalize != null) {
      _result.normalize = normalize;
    }
    return _result;
  }
  factory EmbeddingsConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmbeddingsConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmbeddingsConfiguration clone() => EmbeddingsConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmbeddingsConfiguration copyWith(void Function(EmbeddingsConfiguration) updates) => super.copyWith((message) => updates(message as EmbeddingsConfiguration)) as EmbeddingsConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EmbeddingsConfiguration create() => EmbeddingsConfiguration._();
  EmbeddingsConfiguration createEmptyInstance() => create();
  static $pb.PbList<EmbeddingsConfiguration> createRepeated() => $pb.PbList<EmbeddingsConfiguration>();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmbeddingsConfiguration>(create);
  static EmbeddingsConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get embeddingDimension => $_getIZ(1);
  @$pb.TagNumber(2)
  set embeddingDimension($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEmbeddingDimension() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmbeddingDimension() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxSequenceLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxSequenceLength($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxSequenceLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxSequenceLength() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get normalize => $_getBF(3);
  @$pb.TagNumber(4)
  set normalize($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNormalize() => $_has(3);
  @$pb.TagNumber(4)
  void clearNormalize() => clearField(4);
}

class EmbeddingsOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'EmbeddingsOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'normalize')
    ..aOB(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'truncate')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'batchSize', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  EmbeddingsOptions._() : super();
  factory EmbeddingsOptions({
    $core.bool? normalize,
    $core.bool? truncate,
    $core.int? batchSize,
  }) {
    final _result = create();
    if (normalize != null) {
      _result.normalize = normalize;
    }
    if (truncate != null) {
      _result.truncate = truncate;
    }
    if (batchSize != null) {
      _result.batchSize = batchSize;
    }
    return _result;
  }
  factory EmbeddingsOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmbeddingsOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmbeddingsOptions clone() => EmbeddingsOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmbeddingsOptions copyWith(void Function(EmbeddingsOptions) updates) => super.copyWith((message) => updates(message as EmbeddingsOptions)) as EmbeddingsOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EmbeddingsOptions create() => EmbeddingsOptions._();
  EmbeddingsOptions createEmptyInstance() => create();
  static $pb.PbList<EmbeddingsOptions> createRepeated() => $pb.PbList<EmbeddingsOptions>();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmbeddingsOptions>(create);
  static EmbeddingsOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get normalize => $_getBF(0);
  @$pb.TagNumber(1)
  set normalize($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasNormalize() => $_has(0);
  @$pb.TagNumber(1)
  void clearNormalize() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get truncate => $_getBF(1);
  @$pb.TagNumber(2)
  set truncate($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTruncate() => $_has(1);
  @$pb.TagNumber(2)
  void clearTruncate() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get batchSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set batchSize($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBatchSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearBatchSize() => clearField(3);
}

class EmbeddingVector extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'EmbeddingVector', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..p<$core.double>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'values', $pb.PbFieldType.KF)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'norm', $pb.PbFieldType.OF)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..hasRequiredFields = false
  ;

  EmbeddingVector._() : super();
  factory EmbeddingVector({
    $core.Iterable<$core.double>? values,
    $core.double? norm,
    $core.String? text,
  }) {
    final _result = create();
    if (values != null) {
      _result.values.addAll(values);
    }
    if (norm != null) {
      _result.norm = norm;
    }
    if (text != null) {
      _result.text = text;
    }
    return _result;
  }
  factory EmbeddingVector.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmbeddingVector.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmbeddingVector clone() => EmbeddingVector()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmbeddingVector copyWith(void Function(EmbeddingVector) updates) => super.copyWith((message) => updates(message as EmbeddingVector)) as EmbeddingVector; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EmbeddingVector create() => EmbeddingVector._();
  EmbeddingVector createEmptyInstance() => create();
  static $pb.PbList<EmbeddingVector> createRepeated() => $pb.PbList<EmbeddingVector>();
  @$core.pragma('dart2js:noInline')
  static EmbeddingVector getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmbeddingVector>(create);
  static EmbeddingVector? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.double> get values => $_getList(0);

  @$pb.TagNumber(2)
  $core.double get norm => $_getN(1);
  @$pb.TagNumber(2)
  set norm($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasNorm() => $_has(1);
  @$pb.TagNumber(2)
  void clearNorm() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => clearField(3);
}

class EmbeddingsResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'EmbeddingsResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<EmbeddingVector>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'vectors', $pb.PbFieldType.PM, subBuilder: EmbeddingVector.create)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'dimension', $pb.PbFieldType.O3)
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'processingTimeMs')
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensUsed', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  EmbeddingsResult._() : super();
  factory EmbeddingsResult({
    $core.Iterable<EmbeddingVector>? vectors,
    $core.int? dimension,
    $fixnum.Int64? processingTimeMs,
    $core.int? tokensUsed,
  }) {
    final _result = create();
    if (vectors != null) {
      _result.vectors.addAll(vectors);
    }
    if (dimension != null) {
      _result.dimension = dimension;
    }
    if (processingTimeMs != null) {
      _result.processingTimeMs = processingTimeMs;
    }
    if (tokensUsed != null) {
      _result.tokensUsed = tokensUsed;
    }
    return _result;
  }
  factory EmbeddingsResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmbeddingsResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmbeddingsResult clone() => EmbeddingsResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmbeddingsResult copyWith(void Function(EmbeddingsResult) updates) => super.copyWith((message) => updates(message as EmbeddingsResult)) as EmbeddingsResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EmbeddingsResult create() => EmbeddingsResult._();
  EmbeddingsResult createEmptyInstance() => create();
  static $pb.PbList<EmbeddingsResult> createRepeated() => $pb.PbList<EmbeddingsResult>();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmbeddingsResult>(create);
  static EmbeddingsResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EmbeddingVector> get vectors => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get dimension => $_getIZ(1);
  @$pb.TagNumber(2)
  set dimension($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDimension() => $_has(1);
  @$pb.TagNumber(2)
  void clearDimension() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get processingTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set processingTimeMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasProcessingTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearProcessingTimeMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get tokensUsed => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokensUsed($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTokensUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensUsed() => clearField(4);
}

