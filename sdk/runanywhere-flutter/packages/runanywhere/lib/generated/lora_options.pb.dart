//
//  Generated code. Do not modify.
//  source: lora_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

///  ---------------------------------------------------------------------------
///  Configuration for loading a LoRA adapter.
///
///  `adapter_path` is a path on disk to a LoRA GGUF file. `scale` controls the
///  adapter's effect strength (default 1.0; e.g. 0.3 for F16 adapters on
///  quantized bases). `adapter_id` is optional and, when present, links the
///  runtime config back to a `LoraAdapterCatalogEntry.id` — none of the current
///  SDK shapes carry it, so it is encoded as a `proto3 optional` field.
///  ---------------------------------------------------------------------------
class LoRAAdapterConfig extends $pb.GeneratedMessage {
  factory LoRAAdapterConfig({
    $core.String? adapterPath,
    $core.double? scale,
    $core.String? adapterId,
    $core.Map<$core.String, $core.String>? metadata,
    $core.Iterable<$core.String>? targetModules,
  }) {
    final $result = create();
    if (adapterPath != null) {
      $result.adapterPath = adapterPath;
    }
    if (scale != null) {
      $result.scale = scale;
    }
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    if (targetModules != null) {
      $result.targetModules.addAll(targetModules);
    }
    return $result;
  }
  LoRAAdapterConfig._() : super();
  factory LoRAAdapterConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAAdapterConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAAdapterConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterPath')
    ..a<$core.double>(2, _omitFieldNames ? '' : 'scale', $pb.PbFieldType.OF)
    ..aOS(3, _omitFieldNames ? '' : 'adapterId')
    ..m<$core.String, $core.String>(4, _omitFieldNames ? '' : 'metadata', entryClassName: 'LoRAAdapterConfig.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..pPS(5, _omitFieldNames ? '' : 'targetModules')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAAdapterConfig clone() => LoRAAdapterConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAAdapterConfig copyWith(void Function(LoRAAdapterConfig) updates) => super.copyWith((message) => updates(message as LoRAAdapterConfig)) as LoRAAdapterConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAAdapterConfig create() => LoRAAdapterConfig._();
  LoRAAdapterConfig createEmptyInstance() => create();
  static $pb.PbList<LoRAAdapterConfig> createRepeated() => $pb.PbList<LoRAAdapterConfig>();
  @$core.pragma('dart2js:noInline')
  static LoRAAdapterConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAAdapterConfig>(create);
  static LoRAAdapterConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterPath($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterPath() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get scale => $_getN(1);
  @$pb.TagNumber(2)
  set scale($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasScale() => $_has(1);
  @$pb.TagNumber(2)
  void clearScale() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get adapterId => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAdapterId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterId() => clearField(3);

  @$pb.TagNumber(4)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(3);

  @$pb.TagNumber(5)
  $core.List<$core.String> get targetModules => $_getList(4);
}

///  ---------------------------------------------------------------------------
///  Info about a currently-loaded LoRA adapter (read-only snapshot).
///
///  `adapter_id` and `error_message` are not present in any current SDK shape;
///  they are encoded as `proto3 optional` so the existing fields (path, scale,
///  applied) round-trip exactly while reserving room for richer status reports.
///  ---------------------------------------------------------------------------
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
    final $result = create();
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    if (adapterPath != null) {
      $result.adapterPath = adapterPath;
    }
    if (scale != null) {
      $result.scale = scale;
    }
    if (applied != null) {
      $result.applied = applied;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    if (loadedAtMs != null) {
      $result.loadedAtMs = loadedAtMs;
    }
    return $result;
  }
  LoRAAdapterInfo._() : super();
  factory LoRAAdapterInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAAdapterInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAAdapterInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'adapterPath')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'scale', $pb.PbFieldType.OF)
    ..aOB(4, _omitFieldNames ? '' : 'applied')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..aInt64(7, _omitFieldNames ? '' : 'loadedAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAAdapterInfo clone() => LoRAAdapterInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAAdapterInfo copyWith(void Function(LoRAAdapterInfo) updates) => super.copyWith((message) => updates(message as LoRAAdapterInfo)) as LoRAAdapterInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAAdapterInfo create() => LoRAAdapterInfo._();
  LoRAAdapterInfo createEmptyInstance() => create();
  static $pb.PbList<LoRAAdapterInfo> createRepeated() => $pb.PbList<LoRAAdapterInfo>();
  @$core.pragma('dart2js:noInline')
  static LoRAAdapterInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAAdapterInfo>(create);
  static LoRAAdapterInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get adapterPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set adapterPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAdapterPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearAdapterPath() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get scale => $_getN(2);
  @$pb.TagNumber(3)
  set scale($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasScale() => $_has(2);
  @$pb.TagNumber(3)
  void clearScale() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get applied => $_getBF(3);
  @$pb.TagNumber(4)
  set applied($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasApplied() => $_has(3);
  @$pb.TagNumber(4)
  void clearApplied() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get errorCode => $_getIZ(5);
  @$pb.TagNumber(6)
  set errorCode($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorCode() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorCode() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get loadedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set loadedAtMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLoadedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearLoadedAtMs() => clearField(7);
}

///  ---------------------------------------------------------------------------
///  Catalog entry for a LoRA adapter registered with the SDK.
///  Apps register entries at startup; SDKs query "which adapters work with this
///  model" without reinventing detection logic per platform.
///
///  `author` is not present in any current SDK shape (Swift, Kotlin, Dart, RN,
///  Web, C ABI) — it is encoded as `proto3 optional` so codegen produces a
///  nullable / has-bit-tracked field.
///  ---------------------------------------------------------------------------
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
    $core.Map<$core.String, $core.String>? metadata,
    $core.String? localPath,
    $core.bool? isDownloaded,
    $fixnum.Int64? downloadedAtUnixMs,
    $core.bool? isImported,
    $core.String? statusMessage,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (url != null) {
      $result.url = url;
    }
    if (filename != null) {
      $result.filename = filename;
    }
    if (compatibleModels != null) {
      $result.compatibleModels.addAll(compatibleModels);
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (author != null) {
      $result.author = author;
    }
    if (defaultScale != null) {
      $result.defaultScale = defaultScale;
    }
    if (checksumSha256 != null) {
      $result.checksumSha256 = checksumSha256;
    }
    if (license != null) {
      $result.license = license;
    }
    if (tags != null) {
      $result.tags.addAll(tags);
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (isDownloaded != null) {
      $result.isDownloaded = isDownloaded;
    }
    if (downloadedAtUnixMs != null) {
      $result.downloadedAtUnixMs = downloadedAtUnixMs;
    }
    if (isImported != null) {
      $result.isImported = isImported;
    }
    if (statusMessage != null) {
      $result.statusMessage = statusMessage;
    }
    return $result;
  }
  LoraAdapterCatalogEntry._() : super();
  factory LoraAdapterCatalogEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aOS(4, _omitFieldNames ? '' : 'url')
    ..aOS(5, _omitFieldNames ? '' : 'filename')
    ..pPS(6, _omitFieldNames ? '' : 'compatibleModels')
    ..aInt64(7, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(8, _omitFieldNames ? '' : 'author')
    ..a<$core.double>(9, _omitFieldNames ? '' : 'defaultScale', $pb.PbFieldType.OF)
    ..aOS(10, _omitFieldNames ? '' : 'checksumSha256')
    ..aOS(11, _omitFieldNames ? '' : 'license')
    ..pPS(12, _omitFieldNames ? '' : 'tags')
    ..m<$core.String, $core.String>(13, _omitFieldNames ? '' : 'metadata', entryClassName: 'LoraAdapterCatalogEntry.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(14, _omitFieldNames ? '' : 'localPath')
    ..aOB(15, _omitFieldNames ? '' : 'isDownloaded')
    ..aInt64(16, _omitFieldNames ? '' : 'downloadedAtUnixMs')
    ..aOB(17, _omitFieldNames ? '' : 'isImported')
    ..aOS(18, _omitFieldNames ? '' : 'statusMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogEntry clone() => LoraAdapterCatalogEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogEntry copyWith(void Function(LoraAdapterCatalogEntry) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogEntry)) as LoraAdapterCatalogEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogEntry create() => LoraAdapterCatalogEntry._();
  LoraAdapterCatalogEntry createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogEntry> createRepeated() => $pb.PbList<LoraAdapterCatalogEntry>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogEntry>(create);
  static LoraAdapterCatalogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get url => $_getSZ(3);
  @$pb.TagNumber(4)
  set url($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearUrl() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get filename => $_getSZ(4);
  @$pb.TagNumber(5)
  set filename($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasFilename() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilename() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.String> get compatibleModels => $_getList(5);

  @$pb.TagNumber(7)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSizeBytes() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get author => $_getSZ(7);
  @$pb.TagNumber(8)
  set author($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasAuthor() => $_has(7);
  @$pb.TagNumber(8)
  void clearAuthor() => clearField(8);

  @$pb.TagNumber(9)
  $core.double get defaultScale => $_getN(8);
  @$pb.TagNumber(9)
  set defaultScale($core.double v) { $_setFloat(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDefaultScale() => $_has(8);
  @$pb.TagNumber(9)
  void clearDefaultScale() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get checksumSha256 => $_getSZ(9);
  @$pb.TagNumber(10)
  set checksumSha256($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasChecksumSha256() => $_has(9);
  @$pb.TagNumber(10)
  void clearChecksumSha256() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get license => $_getSZ(10);
  @$pb.TagNumber(11)
  set license($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasLicense() => $_has(10);
  @$pb.TagNumber(11)
  void clearLicense() => clearField(11);

  @$pb.TagNumber(12)
  $core.List<$core.String> get tags => $_getList(11);

  @$pb.TagNumber(13)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(12);

  /// Stable platform-normalized local artifact path after native/Web has
  /// completed download/import and reported the result back to commons.
  @$pb.TagNumber(14)
  $core.String get localPath => $_getSZ(13);
  @$pb.TagNumber(14)
  set localPath($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasLocalPath() => $_has(13);
  @$pb.TagNumber(14)
  void clearLocalPath() => clearField(14);

  @$pb.TagNumber(15)
  $core.bool get isDownloaded => $_getBF(14);
  @$pb.TagNumber(15)
  set isDownloaded($core.bool v) { $_setBool(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasIsDownloaded() => $_has(14);
  @$pb.TagNumber(15)
  void clearIsDownloaded() => clearField(15);

  @$pb.TagNumber(16)
  $fixnum.Int64 get downloadedAtUnixMs => $_getI64(15);
  @$pb.TagNumber(16)
  set downloadedAtUnixMs($fixnum.Int64 v) { $_setInt64(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasDownloadedAtUnixMs() => $_has(15);
  @$pb.TagNumber(16)
  void clearDownloadedAtUnixMs() => clearField(16);

  @$pb.TagNumber(17)
  $core.bool get isImported => $_getBF(16);
  @$pb.TagNumber(17)
  set isImported($core.bool v) { $_setBool(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasIsImported() => $_has(16);
  @$pb.TagNumber(17)
  void clearIsImported() => clearField(17);

  @$pb.TagNumber(18)
  $core.String get statusMessage => $_getSZ(17);
  @$pb.TagNumber(18)
  set statusMessage($core.String v) { $_setString(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasStatusMessage() => $_has(17);
  @$pb.TagNumber(18)
  void clearStatusMessage() => clearField(18);
}

class LoraAdapterCatalogQuery extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogQuery({
    $core.String? adapterId,
    $core.String? modelId,
    $core.bool? downloadedOnly,
    $core.String? searchQuery,
    $core.Iterable<$core.String>? tags,
  }) {
    final $result = create();
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (downloadedOnly != null) {
      $result.downloadedOnly = downloadedOnly;
    }
    if (searchQuery != null) {
      $result.searchQuery = searchQuery;
    }
    if (tags != null) {
      $result.tags.addAll(tags);
    }
    return $result;
  }
  LoraAdapterCatalogQuery._() : super();
  factory LoraAdapterCatalogQuery.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogQuery.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogQuery', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOB(3, _omitFieldNames ? '' : 'downloadedOnly')
    ..aOS(4, _omitFieldNames ? '' : 'searchQuery')
    ..pPS(5, _omitFieldNames ? '' : 'tags')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogQuery clone() => LoraAdapterCatalogQuery()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogQuery copyWith(void Function(LoraAdapterCatalogQuery) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogQuery)) as LoraAdapterCatalogQuery;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogQuery create() => LoraAdapterCatalogQuery._();
  LoraAdapterCatalogQuery createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogQuery> createRepeated() => $pb.PbList<LoraAdapterCatalogQuery>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogQuery getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogQuery>(create);
  static LoraAdapterCatalogQuery? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get downloadedOnly => $_getBF(2);
  @$pb.TagNumber(3)
  set downloadedOnly($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDownloadedOnly() => $_has(2);
  @$pb.TagNumber(3)
  void clearDownloadedOnly() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get searchQuery => $_getSZ(3);
  @$pb.TagNumber(4)
  set searchQuery($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSearchQuery() => $_has(3);
  @$pb.TagNumber(4)
  void clearSearchQuery() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.String> get tags => $_getList(4);
}

class LoraAdapterCatalogListRequest extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogListRequest({
    LoraAdapterCatalogQuery? query,
    $core.bool? includeCounts,
  }) {
    final $result = create();
    if (query != null) {
      $result.query = query;
    }
    if (includeCounts != null) {
      $result.includeCounts = includeCounts;
    }
    return $result;
  }
  LoraAdapterCatalogListRequest._() : super();
  factory LoraAdapterCatalogListRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogListRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogListRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<LoraAdapterCatalogQuery>(1, _omitFieldNames ? '' : 'query', subBuilder: LoraAdapterCatalogQuery.create)
    ..aOB(2, _omitFieldNames ? '' : 'includeCounts')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogListRequest clone() => LoraAdapterCatalogListRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogListRequest copyWith(void Function(LoraAdapterCatalogListRequest) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogListRequest)) as LoraAdapterCatalogListRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListRequest create() => LoraAdapterCatalogListRequest._();
  LoraAdapterCatalogListRequest createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogListRequest> createRepeated() => $pb.PbList<LoraAdapterCatalogListRequest>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogListRequest>(create);
  static LoraAdapterCatalogListRequest? _defaultInstance;

  @$pb.TagNumber(1)
  LoraAdapterCatalogQuery get query => $_getN(0);
  @$pb.TagNumber(1)
  set query(LoraAdapterCatalogQuery v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => clearField(1);
  @$pb.TagNumber(1)
  LoraAdapterCatalogQuery ensureQuery() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get includeCounts => $_getBF(1);
  @$pb.TagNumber(2)
  set includeCounts($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIncludeCounts() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeCounts() => clearField(2);
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
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (entries != null) {
      $result.entries.addAll(entries);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (totalCount != null) {
      $result.totalCount = totalCount;
    }
    if (filteredCount != null) {
      $result.filteredCount = filteredCount;
    }
    if (downloadedCount != null) {
      $result.downloadedCount = downloadedCount;
    }
    return $result;
  }
  LoraAdapterCatalogListResult._() : super();
  factory LoraAdapterCatalogListResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogListResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogListResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pc<LoraAdapterCatalogEntry>(2, _omitFieldNames ? '' : 'entries', $pb.PbFieldType.PM, subBuilder: LoraAdapterCatalogEntry.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'totalCount', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'filteredCount', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'downloadedCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogListResult clone() => LoraAdapterCatalogListResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogListResult copyWith(void Function(LoraAdapterCatalogListResult) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogListResult)) as LoraAdapterCatalogListResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListResult create() => LoraAdapterCatalogListResult._();
  LoraAdapterCatalogListResult createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogListResult> createRepeated() => $pb.PbList<LoraAdapterCatalogListResult>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogListResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogListResult>(create);
  static LoraAdapterCatalogListResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<LoraAdapterCatalogEntry> get entries => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get totalCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get filteredCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set filteredCount($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasFilteredCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilteredCount() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get downloadedCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set downloadedCount($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDownloadedCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearDownloadedCount() => clearField(6);
}

class LoraAdapterCatalogGetRequest extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogGetRequest({
    $core.String? adapterId,
  }) {
    final $result = create();
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    return $result;
  }
  LoraAdapterCatalogGetRequest._() : super();
  factory LoraAdapterCatalogGetRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogGetRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogGetRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogGetRequest clone() => LoraAdapterCatalogGetRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogGetRequest copyWith(void Function(LoraAdapterCatalogGetRequest) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogGetRequest)) as LoraAdapterCatalogGetRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetRequest create() => LoraAdapterCatalogGetRequest._();
  LoraAdapterCatalogGetRequest createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogGetRequest> createRepeated() => $pb.PbList<LoraAdapterCatalogGetRequest>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogGetRequest>(create);
  static LoraAdapterCatalogGetRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => clearField(1);
}

class LoraAdapterCatalogGetResult extends $pb.GeneratedMessage {
  factory LoraAdapterCatalogGetResult({
    $core.bool? found,
    LoraAdapterCatalogEntry? entry,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (found != null) {
      $result.found = found;
    }
    if (entry != null) {
      $result.entry = entry;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  LoraAdapterCatalogGetResult._() : super();
  factory LoraAdapterCatalogGetResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterCatalogGetResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterCatalogGetResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'found')
    ..aOM<LoraAdapterCatalogEntry>(2, _omitFieldNames ? '' : 'entry', subBuilder: LoraAdapterCatalogEntry.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogGetResult clone() => LoraAdapterCatalogGetResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterCatalogGetResult copyWith(void Function(LoraAdapterCatalogGetResult) updates) => super.copyWith((message) => updates(message as LoraAdapterCatalogGetResult)) as LoraAdapterCatalogGetResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetResult create() => LoraAdapterCatalogGetResult._();
  LoraAdapterCatalogGetResult createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterCatalogGetResult> createRepeated() => $pb.PbList<LoraAdapterCatalogGetResult>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterCatalogGetResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterCatalogGetResult>(create);
  static LoraAdapterCatalogGetResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get found => $_getBF(0);
  @$pb.TagNumber(1)
  set found($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFound() => $_has(0);
  @$pb.TagNumber(1)
  void clearFound() => clearField(1);

  @$pb.TagNumber(2)
  LoraAdapterCatalogEntry get entry => $_getN(1);
  @$pb.TagNumber(2)
  set entry(LoraAdapterCatalogEntry v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasEntry() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntry() => clearField(2);
  @$pb.TagNumber(2)
  LoraAdapterCatalogEntry ensureEntry() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);
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
    final $result = create();
    if (adapterId != null) {
      $result.adapterId = adapterId;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (checksumSha256 != null) {
      $result.checksumSha256 = checksumSha256;
    }
    if (completedAtUnixMs != null) {
      $result.completedAtUnixMs = completedAtUnixMs;
    }
    if (imported != null) {
      $result.imported = imported;
    }
    if (statusMessage != null) {
      $result.statusMessage = statusMessage;
    }
    return $result;
  }
  LoraAdapterDownloadCompletedRequest._() : super();
  factory LoraAdapterDownloadCompletedRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterDownloadCompletedRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterDownloadCompletedRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'adapterId')
    ..aOS(2, _omitFieldNames ? '' : 'localPath')
    ..aInt64(3, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(4, _omitFieldNames ? '' : 'checksumSha256')
    ..aInt64(5, _omitFieldNames ? '' : 'completedAtUnixMs')
    ..aOB(6, _omitFieldNames ? '' : 'imported')
    ..aOS(7, _omitFieldNames ? '' : 'statusMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterDownloadCompletedRequest clone() => LoraAdapterDownloadCompletedRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterDownloadCompletedRequest copyWith(void Function(LoraAdapterDownloadCompletedRequest) updates) => super.copyWith((message) => updates(message as LoraAdapterDownloadCompletedRequest)) as LoraAdapterDownloadCompletedRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedRequest create() => LoraAdapterDownloadCompletedRequest._();
  LoraAdapterDownloadCompletedRequest createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterDownloadCompletedRequest> createRepeated() => $pb.PbList<LoraAdapterDownloadCompletedRequest>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterDownloadCompletedRequest>(create);
  static LoraAdapterDownloadCompletedRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get adapterId => $_getSZ(0);
  @$pb.TagNumber(1)
  set adapterId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAdapterId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAdapterId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get localPath => $_getSZ(1);
  @$pb.TagNumber(2)
  set localPath($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLocalPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocalPath() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearSizeBytes() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get checksumSha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set checksumSha256($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasChecksumSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearChecksumSha256() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get completedAtUnixMs => $_getI64(4);
  @$pb.TagNumber(5)
  set completedAtUnixMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCompletedAtUnixMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompletedAtUnixMs() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get imported => $_getBF(5);
  @$pb.TagNumber(6)
  set imported($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasImported() => $_has(5);
  @$pb.TagNumber(6)
  void clearImported() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get statusMessage => $_getSZ(6);
  @$pb.TagNumber(7)
  set statusMessage($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStatusMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearStatusMessage() => clearField(7);
}

class LoraAdapterDownloadCompletedResult extends $pb.GeneratedMessage {
  factory LoraAdapterDownloadCompletedResult({
    $core.bool? success,
    LoraAdapterCatalogEntry? entry,
    $core.String? errorMessage,
    $core.bool? persisted,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (entry != null) {
      $result.entry = entry;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (persisted != null) {
      $result.persisted = persisted;
    }
    return $result;
  }
  LoraAdapterDownloadCompletedResult._() : super();
  factory LoraAdapterDownloadCompletedResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraAdapterDownloadCompletedResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraAdapterDownloadCompletedResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<LoraAdapterCatalogEntry>(2, _omitFieldNames ? '' : 'entry', subBuilder: LoraAdapterCatalogEntry.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aOB(4, _omitFieldNames ? '' : 'persisted')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraAdapterDownloadCompletedResult clone() => LoraAdapterDownloadCompletedResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraAdapterDownloadCompletedResult copyWith(void Function(LoraAdapterDownloadCompletedResult) updates) => super.copyWith((message) => updates(message as LoraAdapterDownloadCompletedResult)) as LoraAdapterDownloadCompletedResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedResult create() => LoraAdapterDownloadCompletedResult._();
  LoraAdapterDownloadCompletedResult createEmptyInstance() => create();
  static $pb.PbList<LoraAdapterDownloadCompletedResult> createRepeated() => $pb.PbList<LoraAdapterDownloadCompletedResult>();
  @$core.pragma('dart2js:noInline')
  static LoraAdapterDownloadCompletedResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraAdapterDownloadCompletedResult>(create);
  static LoraAdapterDownloadCompletedResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  LoraAdapterCatalogEntry get entry => $_getN(1);
  @$pb.TagNumber(2)
  set entry(LoraAdapterCatalogEntry v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasEntry() => $_has(1);
  @$pb.TagNumber(2)
  void clearEntry() => clearField(2);
  @$pb.TagNumber(2)
  LoraAdapterCatalogEntry ensureEntry() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get persisted => $_getBF(3);
  @$pb.TagNumber(4)
  set persisted($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPersisted() => $_has(3);
  @$pb.TagNumber(4)
  void clearPersisted() => clearField(4);
}

///  ---------------------------------------------------------------------------
///  Result of a LoRA compatibility pre-check.
///
///  `base_model_required` is not present in any current SDK shape — it is
///  encoded as `proto3 optional` so a future implementation can surface "this
///  adapter requires base model X" without breaking wire compatibility.
///  ---------------------------------------------------------------------------
class LoraCompatibilityResult extends $pb.GeneratedMessage {
  factory LoraCompatibilityResult({
    $core.bool? isCompatible,
    $core.String? errorMessage,
    $core.String? baseModelRequired,
    $core.Iterable<$core.String>? warnings,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (isCompatible != null) {
      $result.isCompatible = isCompatible;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (baseModelRequired != null) {
      $result.baseModelRequired = baseModelRequired;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  LoraCompatibilityResult._() : super();
  factory LoraCompatibilityResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoraCompatibilityResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoraCompatibilityResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isCompatible')
    ..aOS(2, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(3, _omitFieldNames ? '' : 'baseModelRequired')
    ..pPS(4, _omitFieldNames ? '' : 'warnings')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoraCompatibilityResult clone() => LoraCompatibilityResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoraCompatibilityResult copyWith(void Function(LoraCompatibilityResult) updates) => super.copyWith((message) => updates(message as LoraCompatibilityResult)) as LoraCompatibilityResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoraCompatibilityResult create() => LoraCompatibilityResult._();
  LoraCompatibilityResult createEmptyInstance() => create();
  static $pb.PbList<LoraCompatibilityResult> createRepeated() => $pb.PbList<LoraCompatibilityResult>();
  @$core.pragma('dart2js:noInline')
  static LoraCompatibilityResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoraCompatibilityResult>(create);
  static LoraCompatibilityResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isCompatible => $_getBF(0);
  @$pb.TagNumber(1)
  set isCompatible($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsCompatible() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsCompatible() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get errorMessage => $_getSZ(1);
  @$pb.TagNumber(2)
  set errorMessage($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasErrorMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearErrorMessage() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseModelRequired => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseModelRequired($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBaseModelRequired() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseModelRequired() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.String> get warnings => $_getList(3);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => clearField(5);
}

class LoRAApplyRequest extends $pb.GeneratedMessage {
  factory LoRAApplyRequest({
    $core.String? requestId,
    $core.Iterable<LoRAAdapterConfig>? adapters,
    $core.bool? replaceExisting,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (adapters != null) {
      $result.adapters.addAll(adapters);
    }
    if (replaceExisting != null) {
      $result.replaceExisting = replaceExisting;
    }
    return $result;
  }
  LoRAApplyRequest._() : super();
  factory LoRAApplyRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAApplyRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAApplyRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pc<LoRAAdapterConfig>(2, _omitFieldNames ? '' : 'adapters', $pb.PbFieldType.PM, subBuilder: LoRAAdapterConfig.create)
    ..aOB(3, _omitFieldNames ? '' : 'replaceExisting')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAApplyRequest clone() => LoRAApplyRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAApplyRequest copyWith(void Function(LoRAApplyRequest) updates) => super.copyWith((message) => updates(message as LoRAApplyRequest)) as LoRAApplyRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAApplyRequest create() => LoRAApplyRequest._();
  LoRAApplyRequest createEmptyInstance() => create();
  static $pb.PbList<LoRAApplyRequest> createRepeated() => $pb.PbList<LoRAApplyRequest>();
  @$core.pragma('dart2js:noInline')
  static LoRAApplyRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAApplyRequest>(create);
  static LoRAApplyRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<LoRAAdapterConfig> get adapters => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get replaceExisting => $_getBF(2);
  @$pb.TagNumber(3)
  set replaceExisting($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReplaceExisting() => $_has(2);
  @$pb.TagNumber(3)
  void clearReplaceExisting() => clearField(3);
}

class LoRAApplyResult extends $pb.GeneratedMessage {
  factory LoRAApplyResult({
    $core.String? requestId,
    $core.Iterable<LoRAAdapterInfo>? adapters,
    $core.bool? success,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (adapters != null) {
      $result.adapters.addAll(adapters);
    }
    if (success != null) {
      $result.success = success;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  LoRAApplyResult._() : super();
  factory LoRAApplyResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAApplyResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAApplyResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pc<LoRAAdapterInfo>(2, _omitFieldNames ? '' : 'adapters', $pb.PbFieldType.PM, subBuilder: LoRAAdapterInfo.create)
    ..aOB(3, _omitFieldNames ? '' : 'success')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAApplyResult clone() => LoRAApplyResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAApplyResult copyWith(void Function(LoRAApplyResult) updates) => super.copyWith((message) => updates(message as LoRAApplyResult)) as LoRAApplyResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAApplyResult create() => LoRAApplyResult._();
  LoRAApplyResult createEmptyInstance() => create();
  static $pb.PbList<LoRAApplyResult> createRepeated() => $pb.PbList<LoRAApplyResult>();
  @$core.pragma('dart2js:noInline')
  static LoRAApplyResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAApplyResult>(create);
  static LoRAApplyResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<LoRAAdapterInfo> get adapters => $_getList(1);

  @$pb.TagNumber(3)
  $core.bool get success => $_getBF(2);
  @$pb.TagNumber(3)
  set success($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSuccess() => $_has(2);
  @$pb.TagNumber(3)
  void clearSuccess() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => clearField(5);
}

class LoRARemoveRequest extends $pb.GeneratedMessage {
  factory LoRARemoveRequest({
    $core.String? requestId,
    $core.Iterable<$core.String>? adapterIds,
    $core.Iterable<$core.String>? adapterPaths,
    $core.bool? clearAll,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (adapterIds != null) {
      $result.adapterIds.addAll(adapterIds);
    }
    if (adapterPaths != null) {
      $result.adapterPaths.addAll(adapterPaths);
    }
    if (clearAll != null) {
      $result.clearAll = clearAll;
    }
    return $result;
  }
  LoRARemoveRequest._() : super();
  factory LoRARemoveRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRARemoveRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRARemoveRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..pPS(2, _omitFieldNames ? '' : 'adapterIds')
    ..pPS(3, _omitFieldNames ? '' : 'adapterPaths')
    ..aOB(4, _omitFieldNames ? '' : 'clearAll')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRARemoveRequest clone() => LoRARemoveRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRARemoveRequest copyWith(void Function(LoRARemoveRequest) updates) => super.copyWith((message) => updates(message as LoRARemoveRequest)) as LoRARemoveRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRARemoveRequest create() => LoRARemoveRequest._();
  LoRARemoveRequest createEmptyInstance() => create();
  static $pb.PbList<LoRARemoveRequest> createRepeated() => $pb.PbList<LoRARemoveRequest>();
  @$core.pragma('dart2js:noInline')
  static LoRARemoveRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRARemoveRequest>(create);
  static LoRARemoveRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.String> get adapterIds => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<$core.String> get adapterPaths => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get clearAll => $_getBF(3);
  @$pb.TagNumber(4)
  set clearAll($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasClearAll() => $_has(3);
  @$pb.TagNumber(4)
  void clearClearAll() => clearField(4);
}

class LoRAState extends $pb.GeneratedMessage {
  factory LoRAState({
    $core.Iterable<LoRAAdapterInfo>? loadedAdapters,
    $core.bool? hasActiveAdapters,
    $core.String? baseModelId,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (loadedAdapters != null) {
      $result.loadedAdapters.addAll(loadedAdapters);
    }
    if (hasActiveAdapters != null) {
      $result.hasActiveAdapters = hasActiveAdapters;
    }
    if (baseModelId != null) {
      $result.baseModelId = baseModelId;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  LoRAState._() : super();
  factory LoRAState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LoRAState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LoRAState', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pc<LoRAAdapterInfo>(1, _omitFieldNames ? '' : 'loadedAdapters', $pb.PbFieldType.PM, subBuilder: LoRAAdapterInfo.create)
    ..aOB(2, _omitFieldNames ? '' : 'hasActiveAdapters')
    ..aOS(3, _omitFieldNames ? '' : 'baseModelId')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LoRAState clone() => LoRAState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LoRAState copyWith(void Function(LoRAState) updates) => super.copyWith((message) => updates(message as LoRAState)) as LoRAState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoRAState create() => LoRAState._();
  LoRAState createEmptyInstance() => create();
  static $pb.PbList<LoRAState> createRepeated() => $pb.PbList<LoRAState>();
  @$core.pragma('dart2js:noInline')
  static LoRAState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoRAState>(create);
  static LoRAState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<LoRAAdapterInfo> get loadedAdapters => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get hasActiveAdapters => $_getBF(1);
  @$pb.TagNumber(2)
  set hasActiveAdapters($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasHasActiveAdapters() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasActiveAdapters() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get baseModelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set baseModelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBaseModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearBaseModelId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get errorCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set errorCode($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorCode() => clearField(5);
}

class LoRAApi {
  $pb.RpcClient _client;
  LoRAApi(this._client);

  $async.Future<LoraAdapterCatalogEntry> registerCatalogEntry($pb.ClientContext? ctx, LoraAdapterCatalogEntry request) =>
    _client.invoke<LoraAdapterCatalogEntry>(ctx, 'LoRA', 'RegisterCatalogEntry', request, LoraAdapterCatalogEntry())
  ;
  $async.Future<LoraAdapterCatalogListResult> listCatalog($pb.ClientContext? ctx, LoraAdapterCatalogListRequest request) =>
    _client.invoke<LoraAdapterCatalogListResult>(ctx, 'LoRA', 'ListCatalog', request, LoraAdapterCatalogListResult())
  ;
  $async.Future<LoraAdapterCatalogListResult> queryCatalog($pb.ClientContext? ctx, LoraAdapterCatalogQuery request) =>
    _client.invoke<LoraAdapterCatalogListResult>(ctx, 'LoRA', 'QueryCatalog', request, LoraAdapterCatalogListResult())
  ;
  $async.Future<LoraAdapterCatalogGetResult> getCatalogEntry($pb.ClientContext? ctx, LoraAdapterCatalogGetRequest request) =>
    _client.invoke<LoraAdapterCatalogGetResult>(ctx, 'LoRA', 'GetCatalogEntry', request, LoraAdapterCatalogGetResult())
  ;
  $async.Future<LoraAdapterDownloadCompletedResult> markDownloadCompleted($pb.ClientContext? ctx, LoraAdapterDownloadCompletedRequest request) =>
    _client.invoke<LoraAdapterDownloadCompletedResult>(ctx, 'LoRA', 'MarkDownloadCompleted', request, LoraAdapterDownloadCompletedResult())
  ;
  $async.Future<LoRAApplyResult> apply($pb.ClientContext? ctx, LoRAApplyRequest request) =>
    _client.invoke<LoRAApplyResult>(ctx, 'LoRA', 'Apply', request, LoRAApplyResult())
  ;
  $async.Future<LoRAState> remove($pb.ClientContext? ctx, LoRARemoveRequest request) =>
    _client.invoke<LoRAState>(ctx, 'LoRA', 'Remove', request, LoRAState())
  ;
  $async.Future<LoraCompatibilityResult> checkCompatibility($pb.ClientContext? ctx, LoRAAdapterConfig request) =>
    _client.invoke<LoraCompatibilityResult>(ctx, 'LoRA', 'CheckCompatibility', request, LoraCompatibilityResult())
  ;
  $async.Future<LoRAState> list($pb.ClientContext? ctx, LoRAState request) =>
    _client.invoke<LoRAState>(ctx, 'LoRA', 'List', request, LoRAState())
  ;
  $async.Future<LoRAState> state($pb.ClientContext? ctx, LoRAState request) =>
    _client.invoke<LoRAState>(ctx, 'LoRA', 'State', request, LoRAState())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
