// This is a generated file - do not edit.
//
// Generated from embeddings_options.proto.

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

import 'embeddings_options.pbenum.dart';
import 'model_types.pbenum.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'embeddings_options.pbenum.dart';

/// ---------------------------------------------------------------------------
/// Component-level configuration applied at service creation. Mirrors the
/// transport-portable subset of rac_embeddings_config_t. Backend selection
/// (preferred_framework) and pooling strategy live outside the wire schema.
/// ---------------------------------------------------------------------------
class EmbeddingsConfiguration extends $pb.GeneratedMessage {
  factory EmbeddingsConfiguration({
    $core.String? modelId,
    $core.int? embeddingDimension,
    $core.int? maxSequenceLength,
    $core.bool? normalize,
    $0.InferenceFramework? preferredFramework,
    $core.int? maxTokens,
    EmbeddingsNormalizeMode? normalizeMode,
    EmbeddingsPoolingStrategy? pooling,
    $core.String? configJson,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (embeddingDimension != null)
      result.embeddingDimension = embeddingDimension;
    if (maxSequenceLength != null) result.maxSequenceLength = maxSequenceLength;
    if (normalize != null) result.normalize = normalize;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (normalizeMode != null) result.normalizeMode = normalizeMode;
    if (pooling != null) result.pooling = pooling;
    if (configJson != null) result.configJson = configJson;
    return result;
  }

  EmbeddingsConfiguration._();

  factory EmbeddingsConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aI(2, _omitFieldNames ? '' : 'embeddingDimension')
    ..aI(3, _omitFieldNames ? '' : 'maxSequenceLength')
    ..aOB(4, _omitFieldNames ? '' : 'normalize')
    ..aE<$0.InferenceFramework>(5, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $0.InferenceFramework.values)
    ..aI(6, _omitFieldNames ? '' : 'maxTokens')
    ..aE<EmbeddingsNormalizeMode>(7, _omitFieldNames ? '' : 'normalizeMode',
        enumValues: EmbeddingsNormalizeMode.values)
    ..aE<EmbeddingsPoolingStrategy>(8, _omitFieldNames ? '' : 'pooling',
        enumValues: EmbeddingsPoolingStrategy.values)
    ..aOS(9, _omitFieldNames ? '' : 'configJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsConfiguration copyWith(
          void Function(EmbeddingsConfiguration) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsConfiguration))
          as EmbeddingsConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsConfiguration create() => EmbeddingsConfiguration._();
  @$core.override
  EmbeddingsConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsConfiguration>(create);
  static EmbeddingsConfiguration? _defaultInstance;

  /// Model identifier (registry id or local path). Required.
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// Output vector dimension. Must match the loaded model's hidden size
  /// (e.g. 384 for all-MiniLM-L6-v2, 768 for bge-base, 1024 for bge-large).
  @$pb.TagNumber(2)
  $core.int get embeddingDimension => $_getIZ(1);
  @$pb.TagNumber(2)
  set embeddingDimension($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmbeddingDimension() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmbeddingDimension() => $_clearField(2);

  /// Maximum tokens per input. Truncation/sliding window is backend-decided
  /// when an input exceeds this length. C ABI default: 512.
  @$pb.TagNumber(3)
  $core.int get maxSequenceLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxSequenceLength($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxSequenceLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxSequenceLength() => $_clearField(3);

  /// Default L2 normalization for produced vectors. When unset the backend
  /// applies its default (RAC_EMBEDDINGS_NORMALIZE_L2 in the C ABI).
  @$pb.TagNumber(4)
  $core.bool get normalize => $_getBF(3);
  @$pb.TagNumber(4)
  set normalize($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNormalize() => $_has(3);
  @$pb.TagNumber(4)
  void clearNormalize() => $_clearField(4);

  /// Preferred framework for the component. Absent = auto.
  @$pb.TagNumber(5)
  $0.InferenceFramework get preferredFramework => $_getN(4);
  @$pb.TagNumber(5)
  set preferredFramework($0.InferenceFramework value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPreferredFramework() => $_has(4);
  @$pb.TagNumber(5)
  void clearPreferredFramework() => $_clearField(5);

  /// C ABI name for max_sequence_length. 0 = use max_sequence_length or
  /// backend default.
  @$pb.TagNumber(6)
  $core.int get maxTokens => $_getIZ(5);
  @$pb.TagNumber(6)
  set maxTokens($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMaxTokens() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxTokens() => $_clearField(6);

  /// Exact C ABI normalization/pooling modes for backends that need more
  /// than the bool normalize flag.
  @$pb.TagNumber(7)
  EmbeddingsNormalizeMode get normalizeMode => $_getN(6);
  @$pb.TagNumber(7)
  set normalizeMode(EmbeddingsNormalizeMode value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasNormalizeMode() => $_has(6);
  @$pb.TagNumber(7)
  void clearNormalizeMode() => $_clearField(7);

  @$pb.TagNumber(8)
  EmbeddingsPoolingStrategy get pooling => $_getN(7);
  @$pb.TagNumber(8)
  set pooling(EmbeddingsPoolingStrategy value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasPooling() => $_has(7);
  @$pb.TagNumber(8)
  void clearPooling() => $_clearField(8);

  /// Backend-specific JSON config (e.g. tokenizer/vocab companion paths).
  @$pb.TagNumber(9)
  $core.String get configJson => $_getSZ(8);
  @$pb.TagNumber(9)
  set configJson($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasConfigJson() => $_has(8);
  @$pb.TagNumber(9)
  void clearConfigJson() => $_clearField(9);
}

/// ---------------------------------------------------------------------------
/// Per-call generation options. Overrides for a single embed / embed_batch
/// invocation; any field left unset falls back to the configuration default.
/// ---------------------------------------------------------------------------
class EmbeddingsOptions extends $pb.GeneratedMessage {
  factory EmbeddingsOptions({
    $core.bool? normalize,
    $core.bool? truncate,
    $core.int? batchSize,
    EmbeddingsNormalizeMode? normalizeMode,
    EmbeddingsPoolingStrategy? pooling,
    $core.int? nThreads,
  }) {
    final result = create();
    if (normalize != null) result.normalize = normalize;
    if (truncate != null) result.truncate = truncate;
    if (batchSize != null) result.batchSize = batchSize;
    if (normalizeMode != null) result.normalizeMode = normalizeMode;
    if (pooling != null) result.pooling = pooling;
    if (nThreads != null) result.nThreads = nThreads;
    return result;
  }

  EmbeddingsOptions._();

  factory EmbeddingsOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'normalize')
    ..aOB(2, _omitFieldNames ? '' : 'truncate')
    ..aI(3, _omitFieldNames ? '' : 'batchSize')
    ..aE<EmbeddingsNormalizeMode>(4, _omitFieldNames ? '' : 'normalizeMode',
        enumValues: EmbeddingsNormalizeMode.values)
    ..aE<EmbeddingsPoolingStrategy>(5, _omitFieldNames ? '' : 'pooling',
        enumValues: EmbeddingsPoolingStrategy.values)
    ..aI(6, _omitFieldNames ? '' : 'nThreads')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsOptions copyWith(void Function(EmbeddingsOptions) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsOptions))
          as EmbeddingsOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsOptions create() => EmbeddingsOptions._();
  @$core.override
  EmbeddingsOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsOptions>(create);
  static EmbeddingsOptions? _defaultInstance;

  /// Apply L2 normalization to the produced vectors. Required so the wire
  /// form is unambiguous on the most common knob; backends may still defer
  /// to model defaults at load time.
  @$pb.TagNumber(1)
  $core.bool get normalize => $_getBF(0);
  @$pb.TagNumber(1)
  set normalize($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNormalize() => $_has(0);
  @$pb.TagNumber(1)
  void clearNormalize() => $_clearField(1);

  /// Truncate inputs longer than max_sequence_length instead of erroring.
  /// Unset = backend default (currently truncate-on-overflow for ONNX,
  /// sliding-window for llama.cpp).
  @$pb.TagNumber(2)
  $core.bool get truncate => $_getBF(1);
  @$pb.TagNumber(2)
  set truncate($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTruncate() => $_has(1);
  @$pb.TagNumber(2)
  void clearTruncate() => $_clearField(2);

  /// Override batch size for embed_batch. Unset = backend chooses
  /// (RAC_EMBEDDINGS_DEFAULT_BATCH_SIZE = 512, capped at 8192).
  @$pb.TagNumber(3)
  $core.int get batchSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set batchSize($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBatchSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearBatchSize() => $_clearField(3);

  /// Exact C ABI per-call overrides. UNSPECIFIED = use component config.
  @$pb.TagNumber(4)
  EmbeddingsNormalizeMode get normalizeMode => $_getN(3);
  @$pb.TagNumber(4)
  set normalizeMode(EmbeddingsNormalizeMode value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasNormalizeMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearNormalizeMode() => $_clearField(4);

  @$pb.TagNumber(5)
  EmbeddingsPoolingStrategy get pooling => $_getN(4);
  @$pb.TagNumber(5)
  set pooling(EmbeddingsPoolingStrategy value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPooling() => $_has(4);
  @$pb.TagNumber(5)
  void clearPooling() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get nThreads => $_getIZ(5);
  @$pb.TagNumber(6)
  set nThreads($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNThreads() => $_has(5);
  @$pb.TagNumber(6)
  void clearNThreads() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// A single embedding produced for one input text. The C ABI ships dense
/// floats with an associated dimension; we additionally carry the source text
/// (helps multi-input batch consumers correlate vectors with inputs without
/// holding the request side-by-side) and an optional pre-computed L2 norm
/// (lets clients short-circuit cosine-similarity when both sides know the
/// vectors are already unit-normalized).
/// ---------------------------------------------------------------------------
class EmbeddingVector extends $pb.GeneratedMessage {
  factory EmbeddingVector({
    $core.Iterable<$core.double>? values,
    $core.double? norm,
    $core.String? text,
    $core.int? dimension,
    $core.int? inputIndex,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (values != null) result.values.addAll(values);
    if (norm != null) result.norm = norm;
    if (text != null) result.text = text;
    if (dimension != null) result.dimension = dimension;
    if (inputIndex != null) result.inputIndex = inputIndex;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  EmbeddingVector._();

  factory EmbeddingVector.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingVector.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingVector',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'values', $pb.PbFieldType.KF)
    ..aD(2, _omitFieldNames ? '' : 'norm', fieldType: $pb.PbFieldType.OF)
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..aI(4, _omitFieldNames ? '' : 'dimension')
    ..aI(5, _omitFieldNames ? '' : 'inputIndex')
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'EmbeddingVector.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingVector clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingVector copyWith(void Function(EmbeddingVector) updates) =>
      super.copyWith((message) => updates(message as EmbeddingVector))
          as EmbeddingVector;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingVector create() => EmbeddingVector._();
  @$core.override
  EmbeddingVector createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingVector getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingVector>(create);
  static EmbeddingVector? _defaultInstance;

  /// Dense float vector. Length equals EmbeddingsResult.dimension.
  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get values => $_getList(0);

  /// L2 norm of `values`. Optional — populated when the backend computes
  /// it (typically when normalize=false and the consumer wants to score
  /// similarity without recomputing).
  @$pb.TagNumber(2)
  $core.double get norm => $_getN(1);
  @$pb.TagNumber(2)
  set norm($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNorm() => $_has(1);
  @$pb.TagNumber(2)
  void clearNorm() => $_clearField(2);

  /// Source text that produced this vector. Optional — preserved for
  /// multi-input batches where the caller wants to correlate without
  /// tracking ordering separately.
  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => $_clearField(3);

  /// Vector dimension for consumers that need per-vector sizing without
  /// inspecting EmbeddingsResult.dimension.
  @$pb.TagNumber(4)
  $core.int get dimension => $_getIZ(3);
  @$pb.TagNumber(4)
  set dimension($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDimension() => $_has(3);
  @$pb.TagNumber(4)
  void clearDimension() => $_clearField(4);

  /// Input index in the original request and optional caller metadata.
  @$pb.TagNumber(5)
  $core.int get inputIndex => $_getIZ(4);
  @$pb.TagNumber(5)
  set inputIndex($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasInputIndex() => $_has(4);
  @$pb.TagNumber(5)
  void clearInputIndex() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(5);
}

/// ---------------------------------------------------------------------------
/// Request envelope for service-handle APIs. One text = embed, multiple texts =
/// embed_batch.
/// ---------------------------------------------------------------------------
class EmbeddingsRequest extends $pb.GeneratedMessage {
  factory EmbeddingsRequest({
    $core.Iterable<$core.String>? texts,
    EmbeddingsOptions? options,
    $core.String? requestId,
    $core.String? modelId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (texts != null) result.texts.addAll(texts);
    if (options != null) result.options = options;
    if (requestId != null) result.requestId = requestId;
    if (modelId != null) result.modelId = modelId;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  EmbeddingsRequest._();

  factory EmbeddingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'texts')
    ..aOM<EmbeddingsOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: EmbeddingsOptions.create)
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'EmbeddingsRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsRequest copyWith(void Function(EmbeddingsRequest) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsRequest))
          as EmbeddingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsRequest create() => EmbeddingsRequest._();
  @$core.override
  EmbeddingsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsRequest>(create);
  static EmbeddingsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get texts => $_getList(0);

  @$pb.TagNumber(2)
  EmbeddingsOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(EmbeddingsOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  EmbeddingsOptions ensureOptions() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set modelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearModelId() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);
}

/// ---------------------------------------------------------------------------
/// Result of an embed / embed_batch call. Mirrors rac_embeddings_result_t
/// (which is array-of-vectors + dimension + processing_time_ms +
/// total_tokens). `dimension` is duplicated at the result level so consumers
/// can size buffers without inspecting an arbitrary vector first.
/// ---------------------------------------------------------------------------
class EmbeddingsResult extends $pb.GeneratedMessage {
  factory EmbeddingsResult({
    $core.Iterable<EmbeddingVector>? vectors,
    $core.int? dimension,
    $fixnum.Int64? processingTimeMs,
    $core.int? tokensUsed,
    $core.String? modelId,
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.String? requestId,
  }) {
    final result = create();
    if (vectors != null) result.vectors.addAll(vectors);
    if (dimension != null) result.dimension = dimension;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (tokensUsed != null) result.tokensUsed = tokensUsed;
    if (modelId != null) result.modelId = modelId;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (requestId != null) result.requestId = requestId;
    return result;
  }

  EmbeddingsResult._();

  factory EmbeddingsResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<EmbeddingVector>(1, _omitFieldNames ? '' : 'vectors',
        subBuilder: EmbeddingVector.create)
    ..aI(2, _omitFieldNames ? '' : 'dimension')
    ..aInt64(3, _omitFieldNames ? '' : 'processingTimeMs')
    ..aI(4, _omitFieldNames ? '' : 'tokensUsed')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aI(7, _omitFieldNames ? '' : 'errorCode')
    ..aOS(8, _omitFieldNames ? '' : 'requestId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsResult copyWith(void Function(EmbeddingsResult) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsResult))
          as EmbeddingsResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsResult create() => EmbeddingsResult._();
  @$core.override
  EmbeddingsResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsResult>(create);
  static EmbeddingsResult? _defaultInstance;

  /// One vector per input text, in input order.
  @$pb.TagNumber(1)
  $pb.PbList<EmbeddingVector> get vectors => $_getList(0);

  /// Vector dimension. Duplicated from each EmbeddingVector for O(1)
  /// sizing on the consumer side.
  @$pb.TagNumber(2)
  $core.int get dimension => $_getIZ(1);
  @$pb.TagNumber(2)
  set dimension($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDimension() => $_has(1);
  @$pb.TagNumber(2)
  void clearDimension() => $_clearField(2);

  /// Total wall-clock time for the embed / embed_batch call, in ms.
  @$pb.TagNumber(3)
  $fixnum.Int64 get processingTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProcessingTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearProcessingTimeMs() => $_clearField(3);

  /// Total tokens consumed across all inputs (post-truncation).
  @$pb.TagNumber(4)
  $core.int get tokensUsed => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokensUsed($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTokensUsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensUsed() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get errorCode => $_getIZ(6);
  @$pb.TagNumber(7)
  set errorCode($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorCode() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get requestId => $_getSZ(7);
  @$pb.TagNumber(8)
  set requestId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasRequestId() => $_has(7);
  @$pb.TagNumber(8)
  void clearRequestId() => $_clearField(8);
}

class EmbeddingsServiceState extends $pb.GeneratedMessage {
  factory EmbeddingsServiceState({
    $core.bool? isReady,
    $core.String? currentModel,
    $core.int? dimension,
    $core.int? maxTokens,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (isReady != null) result.isReady = isReady;
    if (currentModel != null) result.currentModel = currentModel;
    if (dimension != null) result.dimension = dimension;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  EmbeddingsServiceState._();

  factory EmbeddingsServiceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsServiceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsServiceState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isReady')
    ..aOS(2, _omitFieldNames ? '' : 'currentModel')
    ..aI(3, _omitFieldNames ? '' : 'dimension')
    ..aI(4, _omitFieldNames ? '' : 'maxTokens')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aI(6, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsServiceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsServiceState copyWith(
          void Function(EmbeddingsServiceState) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsServiceState))
          as EmbeddingsServiceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsServiceState create() => EmbeddingsServiceState._();
  @$core.override
  EmbeddingsServiceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsServiceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsServiceState>(create);
  static EmbeddingsServiceState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isReady => $_getBF(0);
  @$pb.TagNumber(1)
  set isReady($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsReady() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsReady() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get currentModel => $_getSZ(1);
  @$pb.TagNumber(2)
  set currentModel($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrentModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrentModel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get dimension => $_getIZ(2);
  @$pb.TagNumber(3)
  set dimension($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDimension() => $_has(2);
  @$pb.TagNumber(3)
  void clearDimension() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxTokens($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxTokens() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get errorCode => $_getIZ(5);
  @$pb.TagNumber(6)
  set errorCode($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorCode() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// Session/handle creation request envelope. Mirrors the public SDK
/// `embeddingsCreate(modelId, configJson?)` calls in RN/Web/Kotlin which
/// previously dropped down to the non-proto `rac_embeddings_create*` C ABI.
/// The result carries an opaque uint64 handle the SDK uses for subsequent
/// embed / embed_batch invocations.
/// ---------------------------------------------------------------------------
class EmbeddingsCreateRequest extends $pb.GeneratedMessage {
  factory EmbeddingsCreateRequest({
    $core.String? modelId,
    EmbeddingsConfiguration? configuration,
    $core.String? configJson,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (configuration != null) result.configuration = configuration;
    if (configJson != null) result.configJson = configJson;
    return result;
  }

  EmbeddingsCreateRequest._();

  factory EmbeddingsCreateRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsCreateRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsCreateRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOM<EmbeddingsConfiguration>(2, _omitFieldNames ? '' : 'configuration',
        subBuilder: EmbeddingsConfiguration.create)
    ..aOS(3, _omitFieldNames ? '' : 'configJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsCreateRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsCreateRequest copyWith(
          void Function(EmbeddingsCreateRequest) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsCreateRequest))
          as EmbeddingsCreateRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsCreateRequest create() => EmbeddingsCreateRequest._();
  @$core.override
  EmbeddingsCreateRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsCreateRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsCreateRequest>(create);
  static EmbeddingsCreateRequest? _defaultInstance;

  /// Required. Model identifier (registry id) or absolute model path.
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// Optional component configuration. When unset, commons applies its
  /// defaults (RAC_EMBEDDINGS_*); when set, the named fields override
  /// the per-component defaults at create time.
  @$pb.TagNumber(2)
  EmbeddingsConfiguration get configuration => $_getN(1);
  @$pb.TagNumber(2)
  set configuration(EmbeddingsConfiguration value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasConfiguration() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfiguration() => $_clearField(2);
  @$pb.TagNumber(2)
  EmbeddingsConfiguration ensureConfiguration() => $_ensure(1);

  /// Provider-specific JSON config. Mirrors the legacy
  /// rac_embeddings_create_with_config(config_json) parameter for backends
  /// that need companion file paths (e.g. {"vocab_path":"..."}).
  @$pb.TagNumber(3)
  $core.String get configJson => $_getSZ(2);
  @$pb.TagNumber(3)
  set configJson($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfigJson() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfigJson() => $_clearField(3);
}

class EmbeddingsCreateResult extends $pb.GeneratedMessage {
  factory EmbeddingsCreateResult({
    $fixnum.Int64? handle,
    $core.String? modelId,
    $core.int? dimension,
    $core.int? maxTokens,
    $core.int? errorCode,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (handle != null) result.handle = handle;
    if (modelId != null) result.modelId = modelId;
    if (dimension != null) result.dimension = dimension;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (errorCode != null) result.errorCode = errorCode;
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  EmbeddingsCreateResult._();

  factory EmbeddingsCreateResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EmbeddingsCreateResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EmbeddingsCreateResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'handle', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aI(3, _omitFieldNames ? '' : 'dimension')
    ..aI(4, _omitFieldNames ? '' : 'maxTokens')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsCreateResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EmbeddingsCreateResult copyWith(
          void Function(EmbeddingsCreateResult) updates) =>
      super.copyWith((message) => updates(message as EmbeddingsCreateResult))
          as EmbeddingsCreateResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmbeddingsCreateResult create() => EmbeddingsCreateResult._();
  @$core.override
  EmbeddingsCreateResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EmbeddingsCreateResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EmbeddingsCreateResult>(create);
  static EmbeddingsCreateResult? _defaultInstance;

  /// Opaque handle (rac_handle_t cast to u64). Zero on failure.
  @$pb.TagNumber(1)
  $fixnum.Int64 get handle => $_getI64(0);
  @$pb.TagNumber(1)
  set handle($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandle() => $_clearField(1);

  /// Echo of the model id the caller requested — so JS/Swift/Kotlin can
  /// store it next to the handle without re-parsing the request.
  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  /// Backend-resolved dimension/max_tokens after load. 0 = unknown until
  /// the first embed call.
  @$pb.TagNumber(3)
  $core.int get dimension => $_getIZ(2);
  @$pb.TagNumber(3)
  set dimension($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDimension() => $_has(2);
  @$pb.TagNumber(3)
  void clearDimension() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxTokens($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxTokens() => $_clearField(4);

  /// Negative on failure; mirrors rac_result_t. Empty error_message on
  /// success.
  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);
}

/// Logical Embeddings service contract. Tokenizer/model execution and native
/// file handles remain adapter/backend-owned; C++ consumes only serialized
/// request/result messages.
class EmbeddingsApi {
  final $pb.RpcClient _client;

  EmbeddingsApi(this._client);

  /// One-shot embedding for a single text carried in EmbeddingsRequest.texts.
  $async.Future<EmbeddingsResult> embed(
          $pb.ClientContext? ctx, EmbeddingsRequest request) =>
      _client.invoke<EmbeddingsResult>(
          ctx, 'Embeddings', 'Embed', request, EmbeddingsResult());

  /// Batch embedding for multiple input texts carried in request order.
  $async.Future<EmbeddingsResult> embedBatch(
          $pb.ClientContext? ctx, EmbeddingsRequest request) =>
      _client.invoke<EmbeddingsResult>(
          ctx, 'Embeddings', 'EmbedBatch', request, EmbeddingsResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
