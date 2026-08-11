// This is a generated file - do not edit.
//
// Generated from lora_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class LoraAdapterConfig extends $pb.GeneratedMessage {
  factory LoraAdapterConfig({
    $core.String? adapterPath,
    $core.double? scale,
    $core.String? adapterId,
  }) {
    final result = create();
    if (adapterPath != null) result.adapterPath = adapterPath;
    if (scale != null) result.scale = scale;
    if (adapterId != null) result.adapterId = adapterId;
    return result;
  }

  LoraAdapterConfig._();

  factory LoraAdapterConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterPath')
    ..aD(2, _omitFieldNames ? '' : 'scale', fieldType: $pb.PbFieldType.OF)
    ..aOS(3, _omitFieldNames ? '' : 'adapterId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterConfig copyWith(void Function(LoraAdapterConfig) updates) =>
      super.copyWith((message) => updates(message as LoraAdapterConfig))
          as LoraAdapterConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterConfig create() => LoraAdapterConfig._();
  @$core.override
  LoraAdapterConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterConfig>(create);
  static LoraAdapterConfig? _defaultInstance;

  /// Escape hatch for a loose GGUF that was never registered. Commons still
  /// loads strictly from this path: there is no catalog id -> path resolver
  /// on the apply path yet.
  @$pb.TagNumber(1)
  $core.String get adapterPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAdapterPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterPath() => $_clearField(1);

  /// 1.0 = as trained, 0.0 = applied but contributing nothing, negatives
  /// subtract. Unbounded and signed. Presence is authoritative: an explicit
  /// 0.0 is honoured. Unset falls back to the catalog entry's default_scale
  /// (including an explicit catalog 0.0), then to 1.0. Commons owns this
  /// resolution — SDKs must not coerce unset/0 to 1.0 locally.
  @$pb.TagNumber(2)
  $core.double get scale => $_getN(1);
  @$pb.TagNumber(2)
  set scale($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScale() => $_has(1);
  @$pb.TagNumber(2)
  void clearScale() => $_clearField(2);

  /// The handle. apply, remove, list and per-request selection all key on
  /// this. Matches PEFT adapter_name / vLLM lora_name / Genie
  /// loraAdapterName.
  @$pb.TagNumber(3)
  $core.String get adapterId => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAdapterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterId() => $_clearField(3);
}

class LoraAdapterInfo extends $pb.GeneratedMessage {
  factory LoraAdapterInfo({
    $core.String? adapterId,
    $core.String? adapterPath,
    $core.double? scale,
    $core.bool? applied,
    $core.int? rank,
    $core.double? alpha,
    $fixnum.Int64? sizeBytes,
    $fixnum.Int64? loadedAtMs,
    $0.SDKError? error,
  }) {
    final result = create();
    if (adapterId != null) result.adapterId = adapterId;
    if (adapterPath != null) result.adapterPath = adapterPath;
    if (scale != null) result.scale = scale;
    if (applied != null) result.applied = applied;
    if (rank != null) result.rank = rank;
    if (alpha != null) result.alpha = alpha;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (loadedAtMs != null) result.loadedAtMs = loadedAtMs;
    if (error != null) result.error = error;
    return result;
  }

  LoraAdapterInfo._();

  factory LoraAdapterInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'adapterPath')
    ..aD(3, _omitFieldNames ? '' : 'scale', fieldType: $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'applied')
    ..aI(5, _omitFieldNames ? '' : 'rank')
    ..aD(6, _omitFieldNames ? '' : 'alpha', fieldType: $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'sizeBytes')
    ..aInt64(8, _omitFieldNames ? '' : 'loadedAtMs')
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterInfo copyWith(void Function(LoraAdapterInfo) updates) =>
      super.copyWith((message) => updates(message as LoraAdapterInfo))
          as LoraAdapterInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterInfo create() => LoraAdapterInfo._();
  @$core.override
  LoraAdapterInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterInfo>(create);
  static LoraAdapterInfo? _defaultInstance;

  /// Catalog id when known, else empty.
  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get adapterPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set adapterPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAdapterPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearAdapterPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get scale => $_getN(2);
  @$pb.TagNumber(3)
  set scale($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasScale() => $_has(2);
  @$pb.TagNumber(3)
  void clearScale() => $_clearField(3);

  /// Whether it is currently applied to the context.
  @$pb.TagNumber(4)
  $core.bool get applied => $_getBF(3);
  @$pb.TagNumber(4)
  set applied($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasApplied() => $_has(3);
  @$pb.TagNumber(4)
  void clearApplied() => $_clearField(4);

  /// Read from the adapter artifact at load time. Never settable.
  /// rank is PEFT's `r`, alpha is lora_alpha; effective strength is
  /// scale * (alpha / rank), which is why 1.0 is not portable between
  /// adapters trained with different alpha/rank.
  @$pb.TagNumber(5)
  $core.int get rank => $_getIZ(4);
  @$pb.TagNumber(5)
  set rank($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRank() => $_has(4);
  @$pb.TagNumber(5)
  void clearRank() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get alpha => $_getN(5);
  @$pb.TagNumber(6)
  set alpha($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAlpha() => $_has(5);
  @$pb.TagNumber(6)
  void clearAlpha() => $_clearField(6);

  /// Measured resident size of this adapter's weights. Absent when the
  /// backend does not report it.
  @$pb.TagNumber(7)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSizeBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get loadedAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set loadedAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLoadedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearLoadedAtMs() => $_clearField(8);

  /// Populated when applied is false.
  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(8);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(8);
}

/// The adapter-specific facts only. Everything generic about the artifact —
/// where it is fetched from, how large it is, how to verify it, who published
/// it, and whether it has been fetched — lives on the ModelInfo record for
/// this adapter.
class LoraAdapterCatalogEntry extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogEntry({
    $core.String? id,
    $core.String? name,
    $core.Iterable<$core.String>? compatibleModels,
    $core.double? defaultScale,
    $core.Iterable<$core.String>? tags,
    $core.String? localPath,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (compatibleModels != null)
      result.compatibleModels.addAll(compatibleModels);
    if (defaultScale != null) result.defaultScale = defaultScale;
    if (tags != null) result.tags.addAll(tags);
    if (localPath != null) result.localPath = localPath;
    return result;
  }

  LoraAdapterCatalogEntry._();

  factory LoraAdapterCatalogEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterCatalogEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterCatalogEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..pPS(3, _omitFieldNames ? '' : 'compatibleModels')
    ..aD(4, _omitFieldNames ? '' : 'defaultScale',
        fieldType: $pb.PbFieldType.OF)
    ..pPS(5, _omitFieldNames ? '' : 'tags')
    ..aOS(6, _omitFieldNames ? '' : 'localPath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogEntry copyWith(
          void Function(LoraAdapterCatalogEntry) updates) =>
      super.copyWith((message) => updates(message as LoraAdapterCatalogEntry))
          as LoraAdapterCatalogEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogEntry create() => LoraAdapterCatalogEntry._();
  @$core.override
  LoraAdapterCatalogEntry createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogEntry getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogEntry>(create);
  static LoraAdapterCatalogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// Explicit base model ids this adapter works with.
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get compatibleModels => $_getList(2);

  /// Publisher-recommended strength. Unset means 1.0.
  @$pb.TagNumber(4)
  $core.double get defaultScale => $_getN(3);
  @$pb.TagNumber(4)
  set defaultScale($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDefaultScale() => $_has(3);
  @$pb.TagNumber(4)
  void clearDefaultScale() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get tags => $_getList(4);

  /// Non-empty means the adapter file is on disk. This is the single
  /// definition of "downloaded".
  @$pb.TagNumber(6)
  $core.String get localPath => $_getSZ(5);
  @$pb.TagNumber(6)
  set localPath($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLocalPath() => $_has(5);
  @$pb.TagNumber(6)
  void clearLocalPath() => $_clearField(6);
}

class LoraAdapterCatalogQuery extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogQuery({
    $core.String? adapterId,
    $core.String? modelId,
    $core.bool? downloadedOnly,
    $core.String? searchQuery,
    $core.Iterable<$core.String>? tags,
  }) {
    final result = create();
    if (adapterId != null) result.adapterId = adapterId;
    if (modelId != null) result.modelId = modelId;
    if (downloadedOnly != null) result.downloadedOnly = downloadedOnly;
    if (searchQuery != null) result.searchQuery = searchQuery;
    if (tags != null) result.tags.addAll(tags);
    return result;
  }

  LoraAdapterCatalogQuery._();

  factory LoraAdapterCatalogQuery.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterCatalogQuery.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterCatalogQuery',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOB(3, _omitFieldNames ? '' : 'downloadedOnly')
    ..aOS(4, _omitFieldNames ? '' : 'searchQuery')
    ..pPS(5, _omitFieldNames ? '' : 'tags')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogQuery clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogQuery copyWith(
          void Function(LoraAdapterCatalogQuery) updates) =>
      super.copyWith((message) => updates(message as LoraAdapterCatalogQuery))
          as LoraAdapterCatalogQuery;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogQuery create() => LoraAdapterCatalogQuery._();
  @$core.override
  LoraAdapterCatalogQuery createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogQuery getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogQuery>(create);
  static LoraAdapterCatalogQuery? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get downloadedOnly => $_getBF(2);
  @$pb.TagNumber(3)
  set downloadedOnly($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDownloadedOnly() => $_has(2);
  @$pb.TagNumber(3)
  void clearDownloadedOnly() => $_clearField(3);

  /// Substring match against name.
  @$pb.TagNumber(4)
  $core.String get searchQuery => $_getSZ(3);
  @$pb.TagNumber(4)
  set searchQuery($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSearchQuery() => $_has(3);
  @$pb.TagNumber(4)
  void clearSearchQuery() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get tags => $_getList(4);
}

class LoraAdapterCatalogListRequest extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogListRequest({
    LoraAdapterCatalogQuery? query,
  }) {
    final result = create();
    if (query != null) result.query = query;
    return result;
  }

  LoraAdapterCatalogListRequest._();

  factory LoraAdapterCatalogListRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterCatalogListRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterCatalogListRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<LoraAdapterCatalogQuery>(1, _omitFieldNames ? '' : 'query',
        subBuilder: LoraAdapterCatalogQuery.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogListRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogListRequest copyWith(
          void Function(LoraAdapterCatalogListRequest) updates) =>
      super.copyWith(
              (message) => updates(message as LoraAdapterCatalogListRequest))
          as LoraAdapterCatalogListRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListRequest create() =>
      LoraAdapterCatalogListRequest._();
  @$core.override
  LoraAdapterCatalogListRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogListRequest>(create);
  static LoraAdapterCatalogListRequest? _defaultInstance;

  @$pb.TagNumber(1)
  LoraAdapterCatalogQuery get query => $_getN(0);
  @$pb.TagNumber(1)
  set query(LoraAdapterCatalogQuery value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => $_clearField(1);
  @$pb.TagNumber(1)
  LoraAdapterCatalogQuery ensureQuery() => $_ensure(0);
}

class LoraAdapterCatalogListResult extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogListResult({
    $core.Iterable<LoraAdapterCatalogEntry>? entries,
    $core.int? totalCount,
    $core.int? downloadedCount,
    $0.SDKError? error,
  }) {
    final result = create();
    if (entries != null) result.entries.addAll(entries);
    if (totalCount != null) result.totalCount = totalCount;
    if (downloadedCount != null) result.downloadedCount = downloadedCount;
    if (error != null) result.error = error;
    return result;
  }

  LoraAdapterCatalogListResult._();

  factory LoraAdapterCatalogListResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterCatalogListResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterCatalogListResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<LoraAdapterCatalogEntry>(1, _omitFieldNames ? '' : 'entries',
        subBuilder: LoraAdapterCatalogEntry.create)
    ..aI(2, _omitFieldNames ? '' : 'totalCount')
    ..aI(3, _omitFieldNames ? '' : 'downloadedCount')
    ..aOM<$0.SDKError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogListResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogListResult copyWith(
          void Function(LoraAdapterCatalogListResult) updates) =>
      super.copyWith(
              (message) => updates(message as LoraAdapterCatalogListResult))
          as LoraAdapterCatalogListResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListResult create() =>
      LoraAdapterCatalogListResult._();
  @$core.override
  LoraAdapterCatalogListResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogListResult>(create);
  static LoraAdapterCatalogListResult? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LoraAdapterCatalogEntry> get entries => $_getList(0);

  /// total_count is unfiltered. Callers that want a filtered count read
  /// entries.size(); a downloaded count is entries with a local_path.
  @$pb.TagNumber(2)
  $core.int get totalCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalCount($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotalCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get downloadedCount => $_getIZ(2);
  @$pb.TagNumber(3)
  set downloadedCount($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDownloadedCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearDownloadedCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $0.SDKError get error => $_getN(3);
  @$pb.TagNumber(4)
  set error($0.SDKError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.SDKError ensureError() => $_ensure(3);
}

class LoraAdapterCatalogGetRequest extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogGetRequest({
    $core.String? adapterId,
  }) {
    final result = create();
    if (adapterId != null) result.adapterId = adapterId;
    return result;
  }

  LoraAdapterCatalogGetRequest._();

  factory LoraAdapterCatalogGetRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterCatalogGetRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterCatalogGetRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogGetRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogGetRequest copyWith(
          void Function(LoraAdapterCatalogGetRequest) updates) =>
      super.copyWith(
              (message) => updates(message as LoraAdapterCatalogGetRequest))
          as LoraAdapterCatalogGetRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetRequest create() =>
      LoraAdapterCatalogGetRequest._();
  @$core.override
  LoraAdapterCatalogGetRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogGetRequest>(create);
  static LoraAdapterCatalogGetRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => $_clearField(1);
}

class LoraAdapterCatalogGetResult extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogGetResult({
    $core.bool? found,
    LoraAdapterCatalogEntry? entry,
    $0.SDKError? error,
  }) {
    final result = create();
    if (found != null) result.found = found;
    if (entry != null) result.entry = entry;
    if (error != null) result.error = error;
    return result;
  }

  LoraAdapterCatalogGetResult._();

  factory LoraAdapterCatalogGetResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterCatalogGetResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterCatalogGetResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'found')
    ..aOM<LoraAdapterCatalogEntry>(2, _omitFieldNames ? '' : 'entry',
        subBuilder: LoraAdapterCatalogEntry.create)
    ..aOM<$0.SDKError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogGetResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterCatalogGetResult copyWith(
          void Function(LoraAdapterCatalogGetResult) updates) =>
      super.copyWith(
              (message) => updates(message as LoraAdapterCatalogGetResult))
          as LoraAdapterCatalogGetResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetResult create() =>
      LoraAdapterCatalogGetResult._();
  @$core.override
  LoraAdapterCatalogGetResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogGetResult>(create);
  static LoraAdapterCatalogGetResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get found => $_getBF(0);
  @$pb.TagNumber(1)
  set found($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFound() => $_has(0);
  @$pb.TagNumber(1)
  void clearFound() => $_clearField(1);

  @$pb.TagNumber(2)
  LoraAdapterCatalogEntry get entry => $_getN(1);
  @$pb.TagNumber(2)
  set entry(LoraAdapterCatalogEntry value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEntry() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntry() => $_clearField(2);
  @$pb.TagNumber(2)
  LoraAdapterCatalogEntry ensureEntry() => $_ensure(1);

  @$pb.TagNumber(4)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(4)
  set error($0.SDKError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.SDKError ensureError() => $_ensure(2);
}

class LoraCompatibilityResult extends $pb.GeneratedMessage {
  factory LoraCompatibilityResult({
    $core.bool? isCompatible,
    $core.String? baseModelRequired,
    $0.SDKError? error,
  }) {
    final result = create();
    if (isCompatible != null) result.isCompatible = isCompatible;
    if (baseModelRequired != null) result.baseModelRequired = baseModelRequired;
    if (error != null) result.error = error;
    return result;
  }

  LoraCompatibilityResult._();

  factory LoraCompatibilityResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraCompatibilityResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraCompatibilityResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isCompatible')
    ..aOS(2, _omitFieldNames ? '' : 'baseModelRequired')
    ..aOM<$0.SDKError>(3, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraCompatibilityResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraCompatibilityResult copyWith(
          void Function(LoraCompatibilityResult) updates) =>
      super.copyWith((message) => updates(message as LoraCompatibilityResult))
          as LoraCompatibilityResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraCompatibilityResult create() => LoraCompatibilityResult._();
  @$core.override
  LoraCompatibilityResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraCompatibilityResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraCompatibilityResult>(create);
  static LoraCompatibilityResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isCompatible => $_getBF(0);
  @$pb.TagNumber(1)
  set isCompatible($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsCompatible() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsCompatible() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get baseModelRequired => $_getSZ(1);
  @$pb.TagNumber(2)
  set baseModelRequired($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBaseModelRequired() => $_has(1);
  @$pb.TagNumber(2)
  void clearBaseModelRequired() => $_clearField(2);

  /// Populated when is_compatible is false.
  @$pb.TagNumber(3)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error($0.SDKError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.SDKError ensureError() => $_ensure(2);
}

class LoraApplyRequest extends $pb.GeneratedMessage {
  factory LoraApplyRequest({
    $core.String? requestId,
    $core.Iterable<LoraAdapterConfig>? adapters,
    $core.bool? keepExisting,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (adapters != null) result.adapters.addAll(adapters);
    if (keepExisting != null) result.keepExisting = keepExisting;
    return result;
  }

  LoraApplyRequest._();

  factory LoraApplyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraApplyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraApplyRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPM<LoraAdapterConfig>(2, _omitFieldNames ? '' : 'adapters',
        subBuilder: LoraAdapterConfig.create)
    ..aOB(3, _omitFieldNames ? '' : 'keepExisting')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraApplyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraApplyRequest copyWith(void Function(LoraApplyRequest) updates) =>
      super.copyWith((message) => updates(message as LoraApplyRequest))
          as LoraApplyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraApplyRequest create() => LoraApplyRequest._();
  @$core.override
  LoraApplyRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraApplyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraApplyRequest>(create);
  static LoraApplyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  /// SET semantics, matching Diffusers set_adapters and
  /// llama_set_adapters_lora: `adapters` becomes the complete active set and
  /// anything not listed is detached.
  @$pb.TagNumber(2)
  $pb.PbList<LoraAdapterConfig> get adapters => $_getList(1);

  /// Stack on top of the currently-applied set instead of replacing it.
  @$pb.TagNumber(3)
  $core.bool get keepExisting => $_getBF(2);
  @$pb.TagNumber(3)
  set keepExisting($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasKeepExisting() => $_has(2);
  @$pb.TagNumber(3)
  void clearKeepExisting() => $_clearField(3);
}

class LoraApplyResult extends $pb.GeneratedMessage {
  factory LoraApplyResult({
    $core.String? requestId,
    $core.Iterable<LoraAdapterInfo>? adapters,
    $0.SDKError? error,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (adapters != null) result.adapters.addAll(adapters);
    if (error != null) result.error = error;
    return result;
  }

  LoraApplyResult._();

  factory LoraApplyResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraApplyResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraApplyResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPM<LoraAdapterInfo>(2, _omitFieldNames ? '' : 'adapters',
        subBuilder: LoraAdapterInfo.create)
    ..aOM<$0.SDKError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraApplyResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraApplyResult copyWith(void Function(LoraApplyResult) updates) =>
      super.copyWith((message) => updates(message as LoraApplyResult))
          as LoraApplyResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraApplyResult create() => LoraApplyResult._();
  @$core.override
  LoraApplyResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraApplyResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraApplyResult>(create);
  static LoraApplyResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<LoraAdapterInfo> get adapters => $_getList(1);

  @$pb.TagNumber(6)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(6)
  set error($0.SDKError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.SDKError ensureError() => $_ensure(2);
}

class LoraRemoveRequest extends $pb.GeneratedMessage {
  factory LoraRemoveRequest({
    $core.Iterable<$core.String>? adapterIds,
    $core.bool? clearAll,
  }) {
    final result = create();
    if (adapterIds != null) result.adapterIds.addAll(adapterIds);
    if (clearAll != null) result.clearAll = clearAll;
    return result;
  }

  LoraRemoveRequest._();

  factory LoraRemoveRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraRemoveRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraRemoveRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'adapterIds')
    ..aOB(2, _omitFieldNames ? '' : 'clearAll')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraRemoveRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraRemoveRequest copyWith(void Function(LoraRemoveRequest) updates) =>
      super.copyWith((message) => updates(message as LoraRemoveRequest))
          as LoraRemoveRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraRemoveRequest create() => LoraRemoveRequest._();
  @$core.override
  LoraRemoveRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraRemoveRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraRemoveRequest>(create);
  static LoraRemoveRequest? _defaultInstance;

  /// Remove the named adapters; clear_all ignores the list.
  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get adapterIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get clearAll => $_getBF(1);
  @$pb.TagNumber(2)
  set clearAll($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClearAll() => $_has(1);
  @$pb.TagNumber(2)
  void clearClearAll() => $_clearField(2);
}

/// Response only. The state read takes no arguments; base_model_id is
/// reported, never a filter.
class LoraState extends $pb.GeneratedMessage {
  factory LoraState({
    $core.Iterable<LoraAdapterInfo>? loadedAdapters,
    $core.String? baseModelId,
    $0.SDKError? error,
  }) {
    final result = create();
    if (loadedAdapters != null) result.loadedAdapters.addAll(loadedAdapters);
    if (baseModelId != null) result.baseModelId = baseModelId;
    if (error != null) result.error = error;
    return result;
  }

  LoraState._();

  factory LoraState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<LoraAdapterInfo>(1, _omitFieldNames ? '' : 'loadedAdapters',
        subBuilder: LoraAdapterInfo.create)
    ..aOS(2, _omitFieldNames ? '' : 'baseModelId')
    ..aOM<$0.SDKError>(3, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraState copyWith(void Function(LoraState) updates) =>
      super.copyWith((message) => updates(message as LoraState)) as LoraState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraState create() => LoraState._();
  @$core.override
  LoraState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraState>(create);
  static LoraState? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LoraAdapterInfo> get loadedAdapters => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get baseModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set baseModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBaseModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearBaseModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error($0.SDKError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  $0.SDKError ensureError() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
