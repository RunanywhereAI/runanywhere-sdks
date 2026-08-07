// This is a generated file - do not edit.
//
// Generated from embeddings_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'embeddings_options.pbenum.dart';
import 'errors.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'embeddings_options.pbenum.dart';

/// Per-call overrides. Unset fields fall back to the loaded bundle's defaults.
class EmbeddingsOptions extends $pb.GeneratedMessage {
  factory EmbeddingsOptions({
    $core.bool? truncate,
    $core.int? batchSize,
    $core.bool? normalize,
    EmbeddingsPoolingStrategy? pooling,
    $core.int? nThreads,
    EmbeddingsInputType? inputType,
    $core.int? dimensions,
  }) {
    final result = create();
    if (truncate != null) result.truncate = truncate;
    if (batchSize != null) result.batchSize = batchSize;
    if (normalize != null) result.normalize = normalize;
    if (pooling != null) result.pooling = pooling;
    if (nThreads != null) result.nThreads = nThreads;
    if (inputType != null) result.inputType = inputType;
    if (dimensions != null) result.dimensions = dimensions;
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
    ..aOB(2, _omitFieldNames ? '' : 'truncate')
    ..aI(3, _omitFieldNames ? '' : 'batchSize')
    ..aOB(4, _omitFieldNames ? '' : 'normalize')
    ..aE<EmbeddingsPoolingStrategy>(5, _omitFieldNames ? '' : 'pooling',
        enumValues: EmbeddingsPoolingStrategy.values)
    ..aI(6, _omitFieldNames ? '' : 'nThreads')
    ..aE<EmbeddingsInputType>(7, _omitFieldNames ? '' : 'inputType',
        enumValues: EmbeddingsInputType.values)
    ..aI(8, _omitFieldNames ? '' : 'dimensions')
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

  /// true  = clip an over-long input to the model's context and embed it.
  /// false = fail the call.
  /// Unset = true. A backend may instead aggregate over a sliding window,
  /// which embeds the whole document rather than discarding its tail.
  @$pb.TagNumber(2)
  $core.bool get truncate => $_getBF(0);
  @$pb.TagNumber(2)
  set truncate($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(2)
  $core.bool hasTruncate() => $_has(0);
  @$pb.TagNumber(2)
  void clearTruncate() => $_clearField(2);

  /// Unset = backend chooses (512, capped at 8192).
  @$pb.TagNumber(3)
  $core.int get batchSize => $_getIZ(1);
  @$pb.TagNumber(3)
  set batchSize($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(3)
  $core.bool hasBatchSize() => $_has(1);
  @$pb.TagNumber(3)
  void clearBatchSize() => $_clearField(3);

  /// L2-normalize every vector to unit length (what cosine search expects).
  /// Unset = true. false returns the raw pooled vector.
  @$pb.TagNumber(4)
  $core.bool get normalize => $_getBF(2);
  @$pb.TagNumber(4)
  set normalize($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasNormalize() => $_has(2);
  @$pb.TagNumber(4)
  void clearNormalize() => $_clearField(4);

  @$pb.TagNumber(5)
  EmbeddingsPoolingStrategy get pooling => $_getN(3);
  @$pb.TagNumber(5)
  set pooling(EmbeddingsPoolingStrategy value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasPooling() => $_has(3);
  @$pb.TagNumber(5)
  void clearPooling() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get nThreads => $_getIZ(4);
  @$pb.TagNumber(6)
  set nThreads($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(6)
  $core.bool hasNThreads() => $_has(4);
  @$pb.TagNumber(6)
  void clearNThreads() => $_clearField(6);

  /// What the vector will be used for. Asymmetric embedders (bge, e5,
  /// nomic-embed, gte, EmbeddingGemma) prepend a different prompt for a query
  /// than for a document. The prefix table must be added to the model manifest
  /// as part of honouring this field; it does not exist today. A bundle that
  /// declares no prompts ignores input_type and returns the identical vector
  /// for QUERY and DOCUMENT — it never errors.
  @$pb.TagNumber(7)
  EmbeddingsInputType get inputType => $_getN(5);
  @$pb.TagNumber(7)
  set inputType(EmbeddingsInputType value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasInputType() => $_has(5);
  @$pb.TagNumber(7)
  void clearInputType() => $_clearField(7);

  /// Matryoshka (MRL) output width: truncate each vector to this many floats
  /// and re-normalize. Unset = the model's native width. Accepts any width in
  /// [1, the native width]; a width the model was not MRL-trained at is
  /// silently worse. This is the request-side width — EmbeddingsResult.dimension
  /// reports the width actually produced.
  @$pb.TagNumber(8)
  $core.int get dimensions => $_getIZ(6);
  @$pb.TagNumber(8)
  set dimensions($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(8)
  $core.bool hasDimensions() => $_has(6);
  @$pb.TagNumber(8)
  void clearDimensions() => $_clearField(8);
}

class EmbeddingVector extends $pb.GeneratedMessage {
  factory EmbeddingVector({
    $core.Iterable<$core.double>? values,
    $core.int? inputIndex,
  }) {
    final result = create();
    if (values != null) result.values.addAll(values);
    if (inputIndex != null) result.inputIndex = inputIndex;
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
    ..aI(2, _omitFieldNames ? '' : 'inputIndex')
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

  /// Length equals EmbeddingsResult.dimension.
  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get values => $_getList(0);

  /// Zero-based position in the request batch. ALWAYS set, on every entry
  /// point, including index 0.
  @$pb.TagNumber(2)
  $core.int get inputIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set inputIndex($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInputIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearInputIndex() => $_clearField(2);
}

/// One text = embed, multiple texts = embed_batch.
class EmbeddingsRequest extends $pb.GeneratedMessage {
  factory EmbeddingsRequest({
    $core.Iterable<$core.String>? texts,
    EmbeddingsOptions? options,
    $core.String? requestId,
    $core.String? modelId,
  }) {
    final result = create();
    if (texts != null) result.texts.addAll(texts);
    if (options != null) result.options = options;
    if (requestId != null) result.requestId = requestId;
    if (modelId != null) result.modelId = modelId;
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
}

class EmbeddingsResult extends $pb.GeneratedMessage {
  factory EmbeddingsResult({
    $core.Iterable<EmbeddingVector>? vectors,
    $core.int? dimension,
    $fixnum.Int64? processingTimeMs,
    $core.int? tokensUsed,
    $core.String? modelId,
    $core.String? requestId,
  }) {
    final result = create();
    if (vectors != null) result.vectors.addAll(vectors);
    if (dimension != null) result.dimension = dimension;
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (tokensUsed != null) result.tokensUsed = tokensUsed;
    if (modelId != null) result.modelId = modelId;
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
    ..aOS(6, _omitFieldNames ? '' : 'requestId')
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

  /// The width of every vector above, so consumers can size buffers in O(1).
  @$pb.TagNumber(2)
  $core.int get dimension => $_getIZ(1);
  @$pb.TagNumber(2)
  set dimension($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDimension() => $_has(1);
  @$pb.TagNumber(2)
  void clearDimension() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get processingTimeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasProcessingTimeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearProcessingTimeMs() => $_clearField(3);

  /// Across all inputs, post-truncation.
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
  $core.String get requestId => $_getSZ(5);
  @$pb.TagNumber(6)
  set requestId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRequestId() => $_has(5);
  @$pb.TagNumber(6)
  void clearRequestId() => $_clearField(6);
}

class EmbeddingsCreateRequest extends $pb.GeneratedMessage {
  factory EmbeddingsCreateRequest({
    $core.String? modelId,
    $core.String? configJson,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
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
    ..aOS(2, _omitFieldNames ? '' : 'configJson')
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

  /// Registry id or absolute model path.
  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// For backends needing companion file paths, e.g. {"vocab_path":"..."}.
  @$pb.TagNumber(2)
  $core.String get configJson => $_getSZ(1);
  @$pb.TagNumber(2)
  set configJson($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConfigJson() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfigJson() => $_clearField(2);
}

class EmbeddingsCreateResult extends $pb.GeneratedMessage {
  factory EmbeddingsCreateResult({
    $fixnum.Int64? handle,
    $core.String? modelId,
    $core.int? dimension,
    $core.int? maxTokens,
    $0.SDKError? error,
  }) {
    final result = create();
    if (handle != null) result.handle = handle;
    if (modelId != null) result.modelId = modelId;
    if (dimension != null) result.dimension = dimension;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (error != null) result.error = error;
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
    ..aOM<$0.SDKError>(7, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
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

  /// rac_handle_t cast to u64. Zero on failure.
  @$pb.TagNumber(1)
  $fixnum.Int64 get handle => $_getI64(0);
  @$pb.TagNumber(1)
  set handle($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandle() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandle() => $_clearField(1);

  /// Echoed so callers can store it beside the handle.
  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  /// Backend-resolved after load. 0 = unknown until the first embed call.
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

  @$pb.TagNumber(7)
  $0.SDKError get error => $_getN(4);
  @$pb.TagNumber(7)
  set error($0.SDKError value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.SDKError ensureError() => $_ensure(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
