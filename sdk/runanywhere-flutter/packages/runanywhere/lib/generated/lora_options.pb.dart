// This is a generated file - do not edit.
//
// Generated from lora_options.proto.

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

/// ---------------------------------------------------------------------------
/// Configuration for loading a LoRA adapter.
///
/// `adapter_path` is a path on disk to a LoRA GGUF file. `scale` controls the
/// adapter's effect strength (default 1.0; e.g. 0.3 for F16 adapters on
/// quantized bases). `adapter_id` is optional and, when present, links the
/// runtime config back to a `LoraAdapterCatalogEntry.id` — none of the current
/// SDK shapes carry it, so it is encoded as a `proto3 optional` field.
/// ---------------------------------------------------------------------------
class LoRAAdapterConfig extends $pb.GeneratedMessage {
  factory LoRAAdapterConfig({
    $core.String? adapterPath,
    $core.double? scale,
    $core.String? adapterId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.Iterable<$core.String>? targetModules,
  }) {
    final result = create();
    if (adapterPath != null) result.adapterPath = adapterPath;
    if (scale != null) result.scale = scale;
    if (adapterId != null) result.adapterId = adapterId;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (targetModules != null) result.targetModules.addAll(targetModules);
    return result;
  }

  LoRAAdapterConfig._();

  factory LoRAAdapterConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoRAAdapterConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoRAAdapterConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterPath')
    ..aD(2, _omitFieldNames ? '' : 'scale', fieldType: $pb.PbFieldType.OF)
    ..aOS(3, _omitFieldNames ? '' : 'adapterId')
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'LoRAAdapterConfig.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..pPS(5, _omitFieldNames ? '' : 'targetModules')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAAdapterConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAAdapterConfig copyWith(void Function(LoRAAdapterConfig) updates) =>
      super.copyWith((message) => updates(message as LoRAAdapterConfig))
          as LoRAAdapterConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAAdapterConfig create() => LoRAAdapterConfig._();
  @$core.override
  LoRAAdapterConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoRAAdapterConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoRAAdapterConfig>(create);
  static LoRAAdapterConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAdapterPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get scale => $_getN(1);
  @$pb.TagNumber(2)
  set scale($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScale() => $_has(1);
  @$pb.TagNumber(2)
  void clearScale() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get adapterId => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAdapterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterId() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get targetModules => $_getList(4);
}

/// ---------------------------------------------------------------------------
/// Info about a currently-loaded LoRA adapter (read-only snapshot).
///
/// `adapter_id` and `error_message` are not present in any current SDK shape;
/// they are encoded as `proto3 optional` so the existing fields (path, scale,
/// applied) round-trip exactly while reserving room for richer status reports.
/// ---------------------------------------------------------------------------
class LoRAAdapterInfo extends $pb.GeneratedMessage {
  factory LoRAAdapterInfo({
    $core.String? adapterId,
    $core.String? adapterPath,
    $core.double? scale,
    $core.bool? applied,
    $core.String? errorMessage,
    $core.int? errorCode,
    $fixnum.Int64? loadedAtMs,
  }) {
    final result = create();
    if (adapterId != null) result.adapterId = adapterId;
    if (adapterPath != null) result.adapterPath = adapterPath;
    if (scale != null) result.scale = scale;
    if (applied != null) result.applied = applied;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (loadedAtMs != null) result.loadedAtMs = loadedAtMs;
    return result;
  }

  LoRAAdapterInfo._();

  factory LoRAAdapterInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoRAAdapterInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoRAAdapterInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'adapterPath')
    ..aD(3, _omitFieldNames ? '' : 'scale', fieldType: $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'applied')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aI(6, _omitFieldNames ? '' : 'errorCode')
    ..aInt64(7, _omitFieldNames ? '' : 'loadedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAAdapterInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAAdapterInfo copyWith(void Function(LoRAAdapterInfo) updates) =>
      super.copyWith((message) => updates(message as LoRAAdapterInfo))
          as LoRAAdapterInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAAdapterInfo create() => LoRAAdapterInfo._();
  @$core.override
  LoRAAdapterInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoRAAdapterInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoRAAdapterInfo>(create);
  static LoRAAdapterInfo? _defaultInstance;

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

  @$pb.TagNumber(4)
  $core.bool get applied => $_getBF(3);
  @$pb.TagNumber(4)
  set applied($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasApplied() => $_has(3);
  @$pb.TagNumber(4)
  void clearApplied() => $_clearField(4);

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

  @$pb.TagNumber(7)
  $fixnum.Int64 get loadedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set loadedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLoadedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearLoadedAtMs() => $_clearField(7);
}

/// ---------------------------------------------------------------------------
/// Catalog entry for a LoRA adapter registered with the SDK.
/// Apps register entries at startup; SDKs query "which adapters work with this
/// model" without reinventing detection logic per platform.
///
/// `author` is not present in any current SDK shape (Swift, Kotlin, Dart, RN,
/// Web, C ABI) — it is encoded as `proto3 optional` so codegen produces a
/// nullable / has-bit-tracked field.
/// ---------------------------------------------------------------------------
class LoraAdapterCatalogEntry extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogEntry({
    $core.String? id,
    $core.String? name,
    $core.String? description,
    $core.String? url,
    $core.String? filename,
    $core.Iterable<$core.String>? compatibleModels,
    $fixnum.Int64? sizeBytes,
    $core.String? author,
    $core.double? defaultScale,
    $core.String? checksumSha256,
    $core.String? license,
    $core.Iterable<$core.String>? tags,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.String? localPath,
    $core.bool? isDownloaded,
    $fixnum.Int64? downloadedAtUnixMs,
    $core.bool? isImported,
    $core.String? statusMessage,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (url != null) result.url = url;
    if (filename != null) result.filename = filename;
    if (compatibleModels != null)
      result.compatibleModels.addAll(compatibleModels);
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (author != null) result.author = author;
    if (defaultScale != null) result.defaultScale = defaultScale;
    if (checksumSha256 != null) result.checksumSha256 = checksumSha256;
    if (license != null) result.license = license;
    if (tags != null) result.tags.addAll(tags);
    if (metadata != null) result.metadata.addEntries(metadata);
    if (localPath != null) result.localPath = localPath;
    if (isDownloaded != null) result.isDownloaded = isDownloaded;
    if (downloadedAtUnixMs != null)
      result.downloadedAtUnixMs = downloadedAtUnixMs;
    if (isImported != null) result.isImported = isImported;
    if (statusMessage != null) result.statusMessage = statusMessage;
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
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'url')
    ..aOS(5, _omitFieldNames ? '' : 'filename')
    ..pPS(6, _omitFieldNames ? '' : 'compatibleModels')
    ..aInt64(7, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(8, _omitFieldNames ? '' : 'author')
    ..aD(9, _omitFieldNames ? '' : 'defaultScale',
        fieldType: $pb.PbFieldType.OF)
    ..aOS(10, _omitFieldNames ? '' : 'checksumSha256')
    ..aOS(11, _omitFieldNames ? '' : 'license')
    ..pPS(12, _omitFieldNames ? '' : 'tags')
    ..m<$core.String, $core.String>(13, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'LoraAdapterCatalogEntry.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(14, _omitFieldNames ? '' : 'localPath')
    ..aOB(15, _omitFieldNames ? '' : 'isDownloaded')
    ..aInt64(16, _omitFieldNames ? '' : 'downloadedAtUnixMs')
    ..aOB(17, _omitFieldNames ? '' : 'isImported')
    ..aOS(18, _omitFieldNames ? '' : 'statusMessage')
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

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get url => $_getSZ(3);
  @$pb.TagNumber(4)
  set url($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearUrl() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get filename => $_getSZ(4);
  @$pb.TagNumber(5)
  set filename($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFilename() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilename() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get compatibleModels => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSizeBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get author => $_getSZ(7);
  @$pb.TagNumber(8)
  set author($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAuthor() => $_has(7);
  @$pb.TagNumber(8)
  void clearAuthor() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get defaultScale => $_getN(8);
  @$pb.TagNumber(9)
  set defaultScale($core.double value) => $_setFloat(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDefaultScale() => $_has(8);
  @$pb.TagNumber(9)
  void clearDefaultScale() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get checksumSha256 => $_getSZ(9);
  @$pb.TagNumber(10)
  set checksumSha256($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasChecksumSha256() => $_has(9);
  @$pb.TagNumber(10)
  void clearChecksumSha256() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get license => $_getSZ(10);
  @$pb.TagNumber(11)
  set license($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasLicense() => $_has(10);
  @$pb.TagNumber(11)
  void clearLicense() => $_clearField(11);

  @$pb.TagNumber(12)
  $pb.PbList<$core.String> get tags => $_getList(11);

  @$pb.TagNumber(13)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(12);

  /// Stable platform-normalized local artifact path after native/Web has
  /// completed download/import and reported the result back to commons.
  @$pb.TagNumber(14)
  $core.String get localPath => $_getSZ(13);
  @$pb.TagNumber(14)
  set localPath($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasLocalPath() => $_has(13);
  @$pb.TagNumber(14)
  void clearLocalPath() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.bool get isDownloaded => $_getBF(14);
  @$pb.TagNumber(15)
  set isDownloaded($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasIsDownloaded() => $_has(14);
  @$pb.TagNumber(15)
  void clearIsDownloaded() => $_clearField(15);

  @$pb.TagNumber(16)
  $fixnum.Int64 get downloadedAtUnixMs => $_getI64(15);
  @$pb.TagNumber(16)
  set downloadedAtUnixMs($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(16)
  $core.bool hasDownloadedAtUnixMs() => $_has(15);
  @$pb.TagNumber(16)
  void clearDownloadedAtUnixMs() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.bool get isImported => $_getBF(16);
  @$pb.TagNumber(17)
  set isImported($core.bool value) => $_setBool(16, value);
  @$pb.TagNumber(17)
  $core.bool hasIsImported() => $_has(16);
  @$pb.TagNumber(17)
  void clearIsImported() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get statusMessage => $_getSZ(17);
  @$pb.TagNumber(18)
  set statusMessage($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasStatusMessage() => $_has(17);
  @$pb.TagNumber(18)
  void clearStatusMessage() => $_clearField(18);
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
    $core.bool? includeCounts,
  }) {
    final result = create();
    if (query != null) result.query = query;
    if (includeCounts != null) result.includeCounts = includeCounts;
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
    ..aOB(2, _omitFieldNames ? '' : 'includeCounts')
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

  @$pb.TagNumber(2)
  $core.bool get includeCounts => $_getBF(1);
  @$pb.TagNumber(2)
  set includeCounts($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncludeCounts() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeCounts() => $_clearField(2);
}

class LoraAdapterCatalogListResult extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogListResult({
    $core.bool? success,
    $core.Iterable<LoraAdapterCatalogEntry>? entries,
    $core.String? errorMessage,
    $core.int? totalCount,
    $core.int? filteredCount,
    $core.int? downloadedCount,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (entries != null) result.entries.addAll(entries);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (totalCount != null) result.totalCount = totalCount;
    if (filteredCount != null) result.filteredCount = filteredCount;
    if (downloadedCount != null) result.downloadedCount = downloadedCount;
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
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pPM<LoraAdapterCatalogEntry>(2, _omitFieldNames ? '' : 'entries',
        subBuilder: LoraAdapterCatalogEntry.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aI(4, _omitFieldNames ? '' : 'totalCount')
    ..aI(5, _omitFieldNames ? '' : 'filteredCount')
    ..aI(6, _omitFieldNames ? '' : 'downloadedCount')
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
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<LoraAdapterCatalogEntry> get entries => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get totalCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get filteredCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set filteredCount($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFilteredCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilteredCount() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get downloadedCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set downloadedCount($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDownloadedCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearDownloadedCount() => $_clearField(6);
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
    $core.String? errorMessage,
  }) {
    final result = create();
    if (found != null) result.found = found;
    if (entry != null) result.entry = entry;
    if (errorMessage != null) result.errorMessage = errorMessage;
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
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
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

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);
}

class LoraAdapterDownloadCompletedRequest extends $pb.GeneratedMessage {
  factory LoraAdapterDownloadCompletedRequest({
    $core.String? adapterId,
    $core.String? localPath,
    $fixnum.Int64? sizeBytes,
    $core.String? checksumSha256,
    $fixnum.Int64? completedAtUnixMs,
    $core.bool? imported,
    $core.String? statusMessage,
  }) {
    final result = create();
    if (adapterId != null) result.adapterId = adapterId;
    if (localPath != null) result.localPath = localPath;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (checksumSha256 != null) result.checksumSha256 = checksumSha256;
    if (completedAtUnixMs != null) result.completedAtUnixMs = completedAtUnixMs;
    if (imported != null) result.imported = imported;
    if (statusMessage != null) result.statusMessage = statusMessage;
    return result;
  }

  LoraAdapterDownloadCompletedRequest._();

  factory LoraAdapterDownloadCompletedRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterDownloadCompletedRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterDownloadCompletedRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'localPath')
    ..aInt64(3, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(4, _omitFieldNames ? '' : 'checksumSha256')
    ..aInt64(5, _omitFieldNames ? '' : 'completedAtUnixMs')
    ..aOB(6, _omitFieldNames ? '' : 'imported')
    ..aOS(7, _omitFieldNames ? '' : 'statusMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterDownloadCompletedRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterDownloadCompletedRequest copyWith(
          void Function(LoraAdapterDownloadCompletedRequest) updates) =>
      super.copyWith((message) =>
              updates(message as LoraAdapterDownloadCompletedRequest))
          as LoraAdapterDownloadCompletedRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedRequest create() =>
      LoraAdapterDownloadCompletedRequest._();
  @$core.override
  LoraAdapterDownloadCompletedRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          LoraAdapterDownloadCompletedRequest>(create);
  static LoraAdapterDownloadCompletedRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get localPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set localPath($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLocalPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocalPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearSizeBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get checksumSha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set checksumSha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasChecksumSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearChecksumSha256() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get completedAtUnixMs => $_getI64(4);
  @$pb.TagNumber(5)
  set completedAtUnixMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCompletedAtUnixMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompletedAtUnixMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get imported => $_getBF(5);
  @$pb.TagNumber(6)
  set imported($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasImported() => $_has(5);
  @$pb.TagNumber(6)
  void clearImported() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get statusMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set statusMessage($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStatusMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearStatusMessage() => $_clearField(7);
}

class LoraAdapterDownloadCompletedResult extends $pb.GeneratedMessage {
  factory LoraAdapterDownloadCompletedResult({
    $core.bool? success,
    LoraAdapterCatalogEntry? entry,
    $core.String? errorMessage,
    $core.bool? persisted,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (entry != null) result.entry = entry;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (persisted != null) result.persisted = persisted;
    return result;
  }

  LoraAdapterDownloadCompletedResult._();

  factory LoraAdapterDownloadCompletedResult.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoraAdapterDownloadCompletedResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoraAdapterDownloadCompletedResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<LoraAdapterCatalogEntry>(2, _omitFieldNames ? '' : 'entry',
        subBuilder: LoraAdapterCatalogEntry.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aOB(4, _omitFieldNames ? '' : 'persisted')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterDownloadCompletedResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoraAdapterDownloadCompletedResult copyWith(
          void Function(LoraAdapterDownloadCompletedResult) updates) =>
      super.copyWith((message) =>
              updates(message as LoraAdapterDownloadCompletedResult))
          as LoraAdapterDownloadCompletedResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedResult create() =>
      LoraAdapterDownloadCompletedResult._();
  @$core.override
  LoraAdapterDownloadCompletedResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoraAdapterDownloadCompletedResult>(
          create);
  static LoraAdapterDownloadCompletedResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

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

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get persisted => $_getBF(3);
  @$pb.TagNumber(4)
  set persisted($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPersisted() => $_has(3);
  @$pb.TagNumber(4)
  void clearPersisted() => $_clearField(4);
}

/// ---------------------------------------------------------------------------
/// Result of a LoRA compatibility pre-check.
///
/// `base_model_required` is not present in any current SDK shape — it is
/// encoded as `proto3 optional` so a future implementation can surface "this
/// adapter requires base model X" without breaking wire compatibility.
/// ---------------------------------------------------------------------------
class LoraCompatibilityResult extends $pb.GeneratedMessage {
  factory LoraCompatibilityResult({
    $core.bool? isCompatible,
    $core.String? errorMessage,
    $core.String? baseModelRequired,
    $core.Iterable<$core.String>? warnings,
    $core.int? errorCode,
  }) {
    final result = create();
    if (isCompatible != null) result.isCompatible = isCompatible;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (baseModelRequired != null) result.baseModelRequired = baseModelRequired;
    if (warnings != null) result.warnings.addAll(warnings);
    if (errorCode != null) result.errorCode = errorCode;
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
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(3, _omitFieldNames ? '' : 'baseModelRequired')
    ..pPS(4, _omitFieldNames ? '' : 'warnings')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
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
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseModelRequired => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseModelRequired($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBaseModelRequired() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseModelRequired() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get warnings => $_getList(3);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);
}

class LoRAApplyRequest extends $pb.GeneratedMessage {
  factory LoRAApplyRequest({
    $core.String? requestId,
    $core.Iterable<LoRAAdapterConfig>? adapters,
    $core.bool? replaceExisting,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (adapters != null) result.adapters.addAll(adapters);
    if (replaceExisting != null) result.replaceExisting = replaceExisting;
    return result;
  }

  LoRAApplyRequest._();

  factory LoRAApplyRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoRAApplyRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoRAApplyRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPM<LoRAAdapterConfig>(2, _omitFieldNames ? '' : 'adapters',
        subBuilder: LoRAAdapterConfig.create)
    ..aOB(3, _omitFieldNames ? '' : 'replaceExisting')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAApplyRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAApplyRequest copyWith(void Function(LoRAApplyRequest) updates) =>
      super.copyWith((message) => updates(message as LoRAApplyRequest))
          as LoRAApplyRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAApplyRequest create() => LoRAApplyRequest._();
  @$core.override
  LoRAApplyRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoRAApplyRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoRAApplyRequest>(create);
  static LoRAApplyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<LoRAAdapterConfig> get adapters => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get replaceExisting => $_getBF(2);
  @$pb.TagNumber(3)
  set replaceExisting($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReplaceExisting() => $_has(2);
  @$pb.TagNumber(3)
  void clearReplaceExisting() => $_clearField(3);
}

class LoRAApplyResult extends $pb.GeneratedMessage {
  factory LoRAApplyResult({
    $core.String? requestId,
    $core.Iterable<LoRAAdapterInfo>? adapters,
    $core.bool? success,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (adapters != null) result.adapters.addAll(adapters);
    if (success != null) result.success = success;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  LoRAApplyResult._();

  factory LoRAApplyResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoRAApplyResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoRAApplyResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPM<LoRAAdapterInfo>(2, _omitFieldNames ? '' : 'adapters',
        subBuilder: LoRAAdapterInfo.create)
    ..aOB(3, _omitFieldNames ? '' : 'success')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAApplyResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAApplyResult copyWith(void Function(LoRAApplyResult) updates) =>
      super.copyWith((message) => updates(message as LoRAApplyResult))
          as LoRAApplyResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAApplyResult create() => LoRAApplyResult._();
  @$core.override
  LoRAApplyResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoRAApplyResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoRAApplyResult>(create);
  static LoRAApplyResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<LoRAAdapterInfo> get adapters => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get success => $_getBF(2);
  @$pb.TagNumber(3)
  set success($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSuccess() => $_has(2);
  @$pb.TagNumber(3)
  void clearSuccess() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);
}

class LoRARemoveRequest extends $pb.GeneratedMessage {
  factory LoRARemoveRequest({
    $core.String? requestId,
    $core.Iterable<$core.String>? adapterIds,
    $core.Iterable<$core.String>? adapterPaths,
    $core.bool? clearAll,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (adapterIds != null) result.adapterIds.addAll(adapterIds);
    if (adapterPaths != null) result.adapterPaths.addAll(adapterPaths);
    if (clearAll != null) result.clearAll = clearAll;
    return result;
  }

  LoRARemoveRequest._();

  factory LoRARemoveRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoRARemoveRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoRARemoveRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPS(2, _omitFieldNames ? '' : 'adapterIds')
    ..pPS(3, _omitFieldNames ? '' : 'adapterPaths')
    ..aOB(4, _omitFieldNames ? '' : 'clearAll')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRARemoveRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRARemoveRequest copyWith(void Function(LoRARemoveRequest) updates) =>
      super.copyWith((message) => updates(message as LoRARemoveRequest))
          as LoRARemoveRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRARemoveRequest create() => LoRARemoveRequest._();
  @$core.override
  LoRARemoveRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoRARemoveRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoRARemoveRequest>(create);
  static LoRARemoveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get adapterIds => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get adapterPaths => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get clearAll => $_getBF(3);
  @$pb.TagNumber(4)
  set clearAll($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasClearAll() => $_has(3);
  @$pb.TagNumber(4)
  void clearClearAll() => $_clearField(4);
}

class LoRAState extends $pb.GeneratedMessage {
  factory LoRAState({
    $core.Iterable<LoRAAdapterInfo>? loadedAdapters,
    $core.bool? hasActiveAdapters,
    $core.String? baseModelId,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (loadedAdapters != null) result.loadedAdapters.addAll(loadedAdapters);
    if (hasActiveAdapters != null) result.hasActiveAdapters = hasActiveAdapters;
    if (baseModelId != null) result.baseModelId = baseModelId;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  LoRAState._();

  factory LoRAState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoRAState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoRAState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<LoRAAdapterInfo>(1, _omitFieldNames ? '' : 'loadedAdapters',
        subBuilder: LoRAAdapterInfo.create)
    ..aOB(2, _omitFieldNames ? '' : 'hasActiveAdapters')
    ..aOS(3, _omitFieldNames ? '' : 'baseModelId')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aI(5, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoRAState copyWith(void Function(LoRAState) updates) =>
      super.copyWith((message) => updates(message as LoRAState)) as LoRAState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAState create() => LoRAState._();
  @$core.override
  LoRAState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoRAState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAState>(create);
  static LoRAState? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<LoRAAdapterInfo> get loadedAdapters => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get hasActiveAdapters => $_getBF(1);
  @$pb.TagNumber(2)
  set hasActiveAdapters($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHasActiveAdapters() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasActiveAdapters() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseModelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseModelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBaseModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => $_clearField(5);
}

/// Logical LoRA service contract. Adapter file acquisition, sandbox handles,
/// and backend-specific load/unload execution remain adapter/backend-owned;
/// C++ consumes only serialized request/result/state messages.
class LoRAApi {
  final $pb.RpcClient _client;

  LoRAApi(this._client);

  /// Register catalog metadata. Local artifact state is ignored here and is
  /// persisted only by MarkDownloadCompleted after native/Web reports success.
  $async.Future<LoraAdapterCatalogEntry> registerCatalogEntry(
          $pb.ClientContext? ctx, LoraAdapterCatalogEntry request) =>
      _client.invoke<LoraAdapterCatalogEntry>(ctx, 'LoRA',
          'RegisterCatalogEntry', request, LoraAdapterCatalogEntry());

  /// Return catalog entries, optionally filtered by query.
  $async.Future<LoraAdapterCatalogListResult> listCatalog(
          $pb.ClientContext? ctx, LoraAdapterCatalogListRequest request) =>
      _client.invoke<LoraAdapterCatalogListResult>(
          ctx, 'LoRA', 'ListCatalog', request, LoraAdapterCatalogListResult());

  /// Query catalog entries directly.
  $async.Future<LoraAdapterCatalogListResult> queryCatalog(
          $pb.ClientContext? ctx, LoraAdapterCatalogQuery request) =>
      _client.invoke<LoraAdapterCatalogListResult>(
          ctx, 'LoRA', 'QueryCatalog', request, LoraAdapterCatalogListResult());

  /// Return one catalog entry by id.
  $async.Future<LoraAdapterCatalogGetResult> getCatalogEntry(
          $pb.ClientContext? ctx, LoraAdapterCatalogGetRequest request) =>
      _client.invoke<LoraAdapterCatalogGetResult>(ctx, 'LoRA',
          'GetCatalogEntry', request, LoraAdapterCatalogGetResult());

  /// Persist platform-reported local path state after download/import.
  $async.Future<LoraAdapterDownloadCompletedResult> markDownloadCompleted(
          $pb.ClientContext? ctx,
          LoraAdapterDownloadCompletedRequest request) =>
      _client.invoke<LoraAdapterDownloadCompletedResult>(
          ctx,
          'LoRA',
          'MarkDownloadCompleted',
          request,
          LoraAdapterDownloadCompletedResult());

  /// Apply one or more adapters to the current logical model/session.
  $async.Future<LoRAApplyResult> apply(
          $pb.ClientContext? ctx, LoRAApplyRequest request) =>
      _client.invoke<LoRAApplyResult>(
          ctx, 'LoRA', 'Apply', request, LoRAApplyResult());

  /// Remove named/path adapters, or clear all when LoRARemoveRequest.clear_all is true.
  $async.Future<LoRAState> remove(
          $pb.ClientContext? ctx, LoRARemoveRequest request) =>
      _client.invoke<LoRAState>(ctx, 'LoRA', 'Remove', request, LoRAState());

  /// Check whether an adapter config is compatible with the current base model.
  $async.Future<LoraCompatibilityResult> checkCompatibility(
          $pb.ClientContext? ctx, LoRAAdapterConfig request) =>
      _client.invoke<LoraCompatibilityResult>(ctx, 'LoRA', 'CheckCompatibility',
          request, LoraCompatibilityResult());

  /// Return the current loaded-adapter snapshot. The request state can carry
  /// optional base_model_id filtering without introducing an empty request type.
  $async.Future<LoRAState> list($pb.ClientContext? ctx, LoRAState request) =>
      _client.invoke<LoRAState>(ctx, 'LoRA', 'List', request, LoRAState());

  /// Return the logical LoRA service state.
  $async.Future<LoRAState> state($pb.ClientContext? ctx, LoRAState request) =>
      _client.invoke<LoRAState>(ctx, 'LoRA', 'State', request, LoRAState());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
