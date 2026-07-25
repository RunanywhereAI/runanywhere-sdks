// This is a generated file - do not edit.
//
// Generated from rerank.proto.

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

/// A single candidate document/passage to be scored against the query. The id is
/// caller-supplied and echoed back on the scored item so callers can correlate
/// results with their own records without relying on ordering.
class RerankCandidate extends $pb.GeneratedMessage {
  factory RerankCandidate({
    $core.String? id,
    $core.String? text,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (text != null) result.text = text;
    return result;
  }

  RerankCandidate._();

  factory RerankCandidate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RerankCandidate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RerankCandidate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankCandidate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RerankCandidate copyWith(void Function(RerankCandidate) updates) =>
      super.copyWith((message) => updates(message as RerankCandidate))
          as RerankCandidate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RerankCandidate create() => RerankCandidate._();
  @$core.override
  RerankCandidate createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RerankCandidate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RerankCandidate>(create);
  static RerankCandidate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);
}

class RerankOptions extends $pb.GeneratedMessage {
  factory RerankOptions({
    $core.int? topN,
  }) {
    final result = create();
    if (topN != null) result.topN = topN;
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
  @$pb.TagNumber(1)
  $core.int get topN => $_getIZ(0);
  @$pb.TagNumber(1)
  set topN($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTopN() => $_has(0);
  @$pb.TagNumber(1)
  void clearTopN() => $_clearField(1);
}

class RerankRequest extends $pb.GeneratedMessage {
  factory RerankRequest({
    $core.String? query,
    $core.Iterable<RerankCandidate>? candidates,
    RerankOptions? options,
  }) {
    final result = create();
    if (query != null) result.query = query;
    if (candidates != null) result.candidates.addAll(candidates);
    if (options != null) result.options = options;
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
    ..pPM<RerankCandidate>(2, _omitFieldNames ? '' : 'candidates',
        subBuilder: RerankCandidate.create)
    ..aOM<RerankOptions>(3, _omitFieldNames ? '' : 'options',
        subBuilder: RerankOptions.create)
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

  @$pb.TagNumber(2)
  $pb.PbList<RerankCandidate> get candidates => $_getList(1);

  @$pb.TagNumber(3)
  RerankOptions get options => $_getN(2);
  @$pb.TagNumber(3)
  set options(RerankOptions value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOptions() => $_has(2);
  @$pb.TagNumber(3)
  void clearOptions() => $_clearField(3);
  @$pb.TagNumber(3)
  RerankOptions ensureOptions() => $_ensure(2);
}

class RerankScoredItem extends $pb.GeneratedMessage {
  factory RerankScoredItem({
    $core.String? id,
    $core.double? score,
    $core.int? originalIndex,
    $core.int? rank,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (score != null) result.score = score;
    if (originalIndex != null) result.originalIndex = originalIndex;
    if (rank != null) result.rank = rank;
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
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aD(2, _omitFieldNames ? '' : 'score', fieldType: $pb.PbFieldType.OF)
    ..aI(3, _omitFieldNames ? '' : 'originalIndex',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'rank', fieldType: $pb.PbFieldType.OU3)
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

  /// Echo of RerankCandidate.id for correlation.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Raw relevance score from the reranker (higher = more relevant). Not
  /// normalized to a fixed range; comparable only within one result set.
  @$pb.TagNumber(2)
  $core.double get score => $_getN(1);
  @$pb.TagNumber(2)
  set score($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScore() => $_has(1);
  @$pb.TagNumber(2)
  void clearScore() => $_clearField(2);

  /// Index of this candidate in the original RerankRequest.candidates list.
  @$pb.TagNumber(3)
  $core.int get originalIndex => $_getIZ(2);
  @$pb.TagNumber(3)
  set originalIndex($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOriginalIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearOriginalIndex() => $_clearField(3);

  /// 0-based position after sorting by score descending (0 = most relevant).
  @$pb.TagNumber(4)
  $core.int get rank => $_getIZ(3);
  @$pb.TagNumber(4)
  set rank($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRank() => $_has(3);
  @$pb.TagNumber(4)
  void clearRank() => $_clearField(4);
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

class RerankingApi {
  final $pb.RpcClient _client;

  RerankingApi(this._client);

  $async.Future<RerankResult> rerank(
          $pb.ClientContext? ctx, RerankRequest request) =>
      _client.invoke<RerankResult>(
          ctx, 'Reranking', 'Rerank', request, RerankResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
