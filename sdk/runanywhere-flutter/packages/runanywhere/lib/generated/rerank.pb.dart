// This is a generated file - do not edit.
//
// Generated from rerank.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class RerankOptions extends $pb.GeneratedMessage {
  factory RerankOptions({
    $core.int? topN,
    $core.int? maxTokensPerDoc,
  }) {
    final result = create();
    if (topN != null) result.topN = topN;
    if (maxTokensPerDoc != null) result.maxTokensPerDoc = maxTokensPerDoc;
    return result;
  }

  RerankOptions._();

  factory RerankOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RerankOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RerankOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'topN', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'maxTokensPerDoc',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankOptions copyWith(void Function(RerankOptions) updates) =>
      super.copyWith((message) => updates(message as RerankOptions))
          as RerankOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RerankOptions create() => RerankOptions._();
  @$core.override
  RerankOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RerankOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RerankOptions>(create);
  static RerankOptions? _defaultInstance;

  /// When > 0, only the top_n highest-scoring candidates are returned (every
  /// candidate is still scored). 0 = return all candidates, ranked.
  /// Industry name (Cohere rerank `top_n`).
  @$pb.TagNumber(1)
  $core.int get topN => $_getIZ(0);
  @$pb.TagNumber(1)
  set topN($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTopN() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopN() => $_clearField(1);

  /// Per-document token budget; longer documents are truncated (tail
  /// dropped) before scoring. 0 = the SDK default budget. This is the
  /// direct knob on peak memory and per-pair latency on device.
  /// Industry name (Cohere v2 / vLLM `max_tokens_per_doc`).
  @$pb.TagNumber(2)
  $core.int get maxTokensPerDoc => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokensPerDoc($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaxTokensPerDoc() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokensPerDoc() => $_clearField(2);
}

class RerankRequest extends $pb.GeneratedMessage {
  factory RerankRequest({
    $core.String? query,
    RerankOptions? options,
    $core.Iterable<$core.String>? documents,
    $core.String? modelId,
  }) {
    final result = create();
    if (query != null) result.query = query;
    if (options != null) result.options = options;
    if (documents != null) result.documents.addAll(documents);
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  RerankRequest._();

  factory RerankRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RerankRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RerankRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..aOM<RerankOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: RerankOptions.create)
    ..pPS(4, _omitFieldNames ? '' : 'documents')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankRequest copyWith(void Function(RerankRequest) updates) =>
      super.copyWith((message) => updates(message as RerankRequest))
          as RerankRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RerankRequest create() => RerankRequest._();
  @$core.override
  RerankRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RerankRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RerankRequest>(create);
  static RerankRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);

  @$pb.TagNumber(3)
  RerankOptions get options => $_getN(1);
  @$pb.TagNumber(3)
  set options(RerankOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  RerankOptions ensureOptions() => $_ensure(1);

  /// The passages to score, in caller order. Results point back at these by
  /// index. Cost is LINEAR (one model pass per document), so this is a
  /// second-stage reranker over a retriever's output, not a corpus scan;
  /// commons rejects more than 100,000 entries with
  /// RAC_ERROR_INVALID_PARAMETER. Industry name (Cohere/Voyage/Jina `documents`).
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get documents => $_getList(2);

  /// Registry id of the reranker to score with. Unset = whatever model is
  /// already resident under the rerank component. Mirrors
  /// EmbeddingsRequest.model_id and the industry-universal `model` field.
  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);
}

class RerankScoredItem extends $pb.GeneratedMessage {
  factory RerankScoredItem({
    $core.double? relevanceScore,
    $core.int? index,
  }) {
    final result = create();
    if (relevanceScore != null) result.relevanceScore = relevanceScore;
    if (index != null) result.index = index;
    return result;
  }

  RerankScoredItem._();

  factory RerankScoredItem.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RerankScoredItem.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RerankScoredItem',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(2, _omitFieldNames ? '' : 'relevanceScore',
        fieldType: $pb.PbFieldType.OF)
    ..aI(3, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankScoredItem clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankScoredItem copyWith(void Function(RerankScoredItem) updates) =>
      super.copyWith((message) => updates(message as RerankScoredItem))
          as RerankScoredItem;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RerankScoredItem create() => RerankScoredItem._();
  @$core.override
  RerankScoredItem createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RerankScoredItem getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RerankScoredItem>(create);
  static RerankScoredItem? _defaultInstance;

  /// Relevance of this document to the query, normalized to [0, 1] (sigmoid
  /// of the cross-encoder logit). Ordinal, not cardinal: 0.9 is not "twice
  /// as relevant" as 0.45, and scores are not comparable across models.
  /// Industry name (Cohere/Voyage `relevance_score`).
  @$pb.TagNumber(2)
  $core.double get relevanceScore => $_getN(0);
  @$pb.TagNumber(2)
  set relevanceScore($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(2)
  $core.bool hasRelevanceScore() => $_has(0);
  @$pb.TagNumber(2)
  void clearRelevanceScore() => $_clearField(2);

  /// Index of this document in the original RerankRequest.documents list.
  /// Industry name (`index`).
  @$pb.TagNumber(3)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(3)
  set index($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(3)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(3)
  void clearIndex() => $_clearField(3);
}

class RerankResult extends $pb.GeneratedMessage {
  factory RerankResult({
    $core.Iterable<RerankScoredItem>? items,
    $fixnum.Int64? processingTimeMs,
    $core.String? modelId,
  }) {
    final result = create();
    if (items != null) result.items.addAll(items);
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  RerankResult._();

  factory RerankResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RerankResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RerankResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<RerankScoredItem>(1, _omitFieldNames ? '' : 'items',
        subBuilder: RerankScoredItem.create)
    ..aInt64(2, _omitFieldNames ? '' : 'processingTimeMs')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankResult copyWith(void Function(RerankResult) updates) =>
      super.copyWith((message) => updates(message as RerankResult))
          as RerankResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RerankResult create() => RerankResult._();
  @$core.override
  RerankResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RerankResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RerankResult>(create);
  static RerankResult? _defaultInstance;

  /// Sorted by score descending. When RerankOptions.top_n > 0, truncated to the
  /// top_n most relevant items.
  @$pb.TagNumber(1)
  $pb.PbList<RerankScoredItem> get items => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get processingTimeMs => $_getI64(1);
  @$pb.TagNumber(2)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasProcessingTimeMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearProcessingTimeMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
