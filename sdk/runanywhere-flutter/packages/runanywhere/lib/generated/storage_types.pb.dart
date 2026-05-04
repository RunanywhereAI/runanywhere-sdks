//
//  Generated code. Do not modify.
//  source: storage_types.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'storage_types.pbenum.dart';

///  ---------------------------------------------------------------------------
///  Whole-device storage capacity. Reported by the platform OS (e.g. iOS
///  `URLResourceKey.volumeAvailableCapacity*`, Android `StatFs`, browser
///  `navigator.storage.estimate()`).
///
///  `used_percent` is materialized rather than computed at the receiver so
///  every binding (Swift, Kotlin, Dart, RN, Web) reports the same number even
///  when total_bytes == 0 (in which case used_percent MUST be 0.0).
///
///  Sources pre-IDL: see header drift table.
///  ---------------------------------------------------------------------------
class DeviceStorageInfo extends $pb.GeneratedMessage {
  factory DeviceStorageInfo({
    $fixnum.Int64? totalBytes,
    $fixnum.Int64? freeBytes,
    $fixnum.Int64? usedBytes,
    $core.double? usedPercent,
  }) {
    final $result = create();
    if (totalBytes != null) {
      $result.totalBytes = totalBytes;
    }
    if (freeBytes != null) {
      $result.freeBytes = freeBytes;
    }
    if (usedBytes != null) {
      $result.usedBytes = usedBytes;
    }
    if (usedPercent != null) {
      $result.usedPercent = usedPercent;
    }
    return $result;
  }
  DeviceStorageInfo._() : super();
  factory DeviceStorageInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceStorageInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DeviceStorageInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'totalBytes')
    ..aInt64(2, _omitFieldNames ? '' : 'freeBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'usedBytes')
    ..a<$core.double>(4, _omitFieldNames ? '' : 'usedPercent', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceStorageInfo clone() => DeviceStorageInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceStorageInfo copyWith(void Function(DeviceStorageInfo) updates) => super.copyWith((message) => updates(message as DeviceStorageInfo)) as DeviceStorageInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceStorageInfo create() => DeviceStorageInfo._();
  DeviceStorageInfo createEmptyInstance() => create();
  static $pb.PbList<DeviceStorageInfo> createRepeated() => $pb.PbList<DeviceStorageInfo>();
  @$core.pragma('dart2js:noInline')
  static DeviceStorageInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceStorageInfo>(create);
  static DeviceStorageInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get totalBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set totalBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTotalBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearTotalBytes() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get freeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set freeBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFreeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearFreeBytes() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get usedBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set usedBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUsedBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearUsedBytes() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get usedPercent => $_getN(3);
  @$pb.TagNumber(4)
  set usedPercent($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUsedPercent() => $_has(3);
  @$pb.TagNumber(4)
  void clearUsedPercent() => clearField(4);
}

///  ---------------------------------------------------------------------------
///  Per-app storage breakdown by directory type. Mirrors the iOS notion of
///  Documents / Caches / Application Support; on Android these map to
///  filesDir / cacheDir / a stable app-support sub-directory; on Web they map
///  to OPFS / FSAccess buckets (collapsed to documents_bytes by default).
///
///  Sources pre-IDL: see header drift table.
///  ---------------------------------------------------------------------------
class AppStorageInfo extends $pb.GeneratedMessage {
  factory AppStorageInfo({
    $fixnum.Int64? documentsBytes,
    $fixnum.Int64? cacheBytes,
    $fixnum.Int64? appSupportBytes,
    $fixnum.Int64? totalBytes,
  }) {
    final $result = create();
    if (documentsBytes != null) {
      $result.documentsBytes = documentsBytes;
    }
    if (cacheBytes != null) {
      $result.cacheBytes = cacheBytes;
    }
    if (appSupportBytes != null) {
      $result.appSupportBytes = appSupportBytes;
    }
    if (totalBytes != null) {
      $result.totalBytes = totalBytes;
    }
    return $result;
  }
  AppStorageInfo._() : super();
  factory AppStorageInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AppStorageInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AppStorageInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'documentsBytes')
    ..aInt64(2, _omitFieldNames ? '' : 'cacheBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'appSupportBytes')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AppStorageInfo clone() => AppStorageInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AppStorageInfo copyWith(void Function(AppStorageInfo) updates) => super.copyWith((message) => updates(message as AppStorageInfo)) as AppStorageInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppStorageInfo create() => AppStorageInfo._();
  AppStorageInfo createEmptyInstance() => create();
  static $pb.PbList<AppStorageInfo> createRepeated() => $pb.PbList<AppStorageInfo>();
  @$core.pragma('dart2js:noInline')
  static AppStorageInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AppStorageInfo>(create);
  static AppStorageInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get documentsBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set documentsBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDocumentsBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearDocumentsBytes() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get cacheBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set cacheBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCacheBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearCacheBytes() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get appSupportBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set appSupportBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAppSupportBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearAppSupportBytes() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => clearField(4);
}

///  ---------------------------------------------------------------------------
///  On-disk metrics for a single downloaded model. The full ModelInfo is *not*
///  embedded here — callers cross-reference `model_id` against ModelInfo from
///  model_types.proto. This avoids circular embeds and keeps the wire payload
///  for storage queries small.
///
///  `last_used_ms` (epoch ms, optional) preserves the field that lived on the
///  older Kotlin `StoredModel` (`models/storage/StorageInfo.kt:131`). All
///  other SDKs lacked it pre-IDL; canonicalizing it here lets the SDK surface
///  LRU eviction without another type round-trip.
///
///  Sources pre-IDL: see header drift table.
///  ---------------------------------------------------------------------------
class ModelStorageMetrics extends $pb.GeneratedMessage {
  factory ModelStorageMetrics({
    $core.String? modelId,
    $fixnum.Int64? sizeOnDiskBytes,
    $fixnum.Int64? lastUsedMs,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (sizeOnDiskBytes != null) {
      $result.sizeOnDiskBytes = sizeOnDiskBytes;
    }
    if (lastUsedMs != null) {
      $result.lastUsedMs = lastUsedMs;
    }
    return $result;
  }
  ModelStorageMetrics._() : super();
  factory ModelStorageMetrics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelStorageMetrics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ModelStorageMetrics', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'sizeOnDiskBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'lastUsedMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelStorageMetrics clone() => ModelStorageMetrics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelStorageMetrics copyWith(void Function(ModelStorageMetrics) updates) => super.copyWith((message) => updates(message as ModelStorageMetrics)) as ModelStorageMetrics;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelStorageMetrics create() => ModelStorageMetrics._();
  ModelStorageMetrics createEmptyInstance() => create();
  static $pb.PbList<ModelStorageMetrics> createRepeated() => $pb.PbList<ModelStorageMetrics>();
  @$core.pragma('dart2js:noInline')
  static ModelStorageMetrics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ModelStorageMetrics>(create);
  static ModelStorageMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sizeOnDiskBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set sizeOnDiskBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSizeOnDiskBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearSizeOnDiskBytes() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get lastUsedMs => $_getI64(2);
  @$pb.TagNumber(3)
  set lastUsedMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLastUsedMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastUsedMs() => clearField(3);
}

///  ---------------------------------------------------------------------------
///  Aggregate storage view: device capacity + app footprint + per-model rows.
///  `total_models` and `total_models_bytes` are denormalized for receivers that
///  would otherwise re-iterate `models` to compute them (Web binding, RN host).
///
///  Sources pre-IDL: see header drift table.
///  ---------------------------------------------------------------------------
class StorageInfo extends $pb.GeneratedMessage {
  factory StorageInfo({
    AppStorageInfo? app,
    DeviceStorageInfo? device,
    $core.Iterable<ModelStorageMetrics>? models,
    $core.int? totalModels,
    $fixnum.Int64? totalModelsBytes,
  }) {
    final $result = create();
    if (app != null) {
      $result.app = app;
    }
    if (device != null) {
      $result.device = device;
    }
    if (models != null) {
      $result.models.addAll(models);
    }
    if (totalModels != null) {
      $result.totalModels = totalModels;
    }
    if (totalModelsBytes != null) {
      $result.totalModelsBytes = totalModelsBytes;
    }
    return $result;
  }
  StorageInfo._() : super();
  factory StorageInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<AppStorageInfo>(1, _omitFieldNames ? '' : 'app', subBuilder: AppStorageInfo.create)
    ..aOM<DeviceStorageInfo>(2, _omitFieldNames ? '' : 'device', subBuilder: DeviceStorageInfo.create)
    ..pc<ModelStorageMetrics>(3, _omitFieldNames ? '' : 'models', $pb.PbFieldType.PM, subBuilder: ModelStorageMetrics.create)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'totalModels', $pb.PbFieldType.O3)
    ..aInt64(5, _omitFieldNames ? '' : 'totalModelsBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageInfo clone() => StorageInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageInfo copyWith(void Function(StorageInfo) updates) => super.copyWith((message) => updates(message as StorageInfo)) as StorageInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageInfo create() => StorageInfo._();
  StorageInfo createEmptyInstance() => create();
  static $pb.PbList<StorageInfo> createRepeated() => $pb.PbList<StorageInfo>();
  @$core.pragma('dart2js:noInline')
  static StorageInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageInfo>(create);
  static StorageInfo? _defaultInstance;

  @$pb.TagNumber(1)
  AppStorageInfo get app => $_getN(0);
  @$pb.TagNumber(1)
  set app(AppStorageInfo v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasApp() => $_has(0);
  @$pb.TagNumber(1)
  void clearApp() => clearField(1);
  @$pb.TagNumber(1)
  AppStorageInfo ensureApp() => $_ensure(0);

  @$pb.TagNumber(2)
  DeviceStorageInfo get device => $_getN(1);
  @$pb.TagNumber(2)
  set device(DeviceStorageInfo v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevice() => clearField(2);
  @$pb.TagNumber(2)
  DeviceStorageInfo ensureDevice() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<ModelStorageMetrics> get models => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get totalModels => $_getIZ(3);
  @$pb.TagNumber(4)
  set totalModels($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalModels() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalModels() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get totalModelsBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set totalModelsBytes($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTotalModelsBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalModelsBytes() => clearField(5);
}

///  ---------------------------------------------------------------------------
///  Result of a "do I have room to download X bytes?" probe. SDKs use this to
///  pre-flight `downloadModel(...)` and surface user-facing warnings (e.g.
///  "you only have 1.2 GB free; this model needs 4 GB").
///
///  `warning_message` and `recommendation` are independently optional —
///  `warning_message` describes the current shortfall, `recommendation`
///  suggests an action (delete cache, free models, etc.).
///
///  Sources pre-IDL: see header drift table.
///  ---------------------------------------------------------------------------
class StorageAvailability extends $pb.GeneratedMessage {
  factory StorageAvailability({
    $core.bool? isAvailable,
    $fixnum.Int64? requiredBytes,
    $fixnum.Int64? availableBytes,
    $core.String? warningMessage,
    $core.String? recommendation,
  }) {
    final $result = create();
    if (isAvailable != null) {
      $result.isAvailable = isAvailable;
    }
    if (requiredBytes != null) {
      $result.requiredBytes = requiredBytes;
    }
    if (availableBytes != null) {
      $result.availableBytes = availableBytes;
    }
    if (warningMessage != null) {
      $result.warningMessage = warningMessage;
    }
    if (recommendation != null) {
      $result.recommendation = recommendation;
    }
    return $result;
  }
  StorageAvailability._() : super();
  factory StorageAvailability.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageAvailability.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageAvailability', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isAvailable')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'availableBytes')
    ..aOS(4, _omitFieldNames ? '' : 'warningMessage')
    ..aOS(5, _omitFieldNames ? '' : 'recommendation')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageAvailability clone() => StorageAvailability()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageAvailability copyWith(void Function(StorageAvailability) updates) => super.copyWith((message) => updates(message as StorageAvailability)) as StorageAvailability;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageAvailability create() => StorageAvailability._();
  StorageAvailability createEmptyInstance() => create();
  static $pb.PbList<StorageAvailability> createRepeated() => $pb.PbList<StorageAvailability>();
  @$core.pragma('dart2js:noInline')
  static StorageAvailability getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageAvailability>(create);
  static StorageAvailability? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isAvailable => $_getBF(0);
  @$pb.TagNumber(1)
  set isAvailable($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIsAvailable() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsAvailable() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get availableBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set availableBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAvailableBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvailableBytes() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get warningMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set warningMessage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasWarningMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearWarningMessage() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get recommendation => $_getSZ(4);
  @$pb.TagNumber(5)
  set recommendation($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRecommendation() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecommendation() => clearField(5);
}

///  ---------------------------------------------------------------------------
///  Backward-compatible "stored model" projection. Older Swift / Kotlin / Dart
///  surfaces (`StoredModel`) wrapped a full `ModelInfo`; this canonical form
///  flattens to the columns those SDKs actually exposed via computed
///  properties (id, name, size, local path, downloaded-at), so RN / Web can
///  emit the same shape without round-tripping through `ModelInfo`.
///
///  Sources pre-IDL: see header drift table.
///  ---------------------------------------------------------------------------
class StoredModel extends $pb.GeneratedMessage {
  factory StoredModel({
    $core.String? modelId,
    $core.String? name,
    $fixnum.Int64? sizeBytes,
    $core.String? localPath,
    $fixnum.Int64? downloadedAtMs,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (downloadedAtMs != null) {
      $result.downloadedAtMs = downloadedAtMs;
    }
    return $result;
  }
  StoredModel._() : super();
  factory StoredModel.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StoredModel.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StoredModel', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aInt64(3, _omitFieldNames ? '' : 'sizeBytes')
    ..aOS(4, _omitFieldNames ? '' : 'localPath')
    ..aInt64(5, _omitFieldNames ? '' : 'downloadedAtMs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StoredModel clone() => StoredModel()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StoredModel copyWith(void Function(StoredModel) updates) => super.copyWith((message) => updates(message as StoredModel)) as StoredModel;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StoredModel create() => StoredModel._();
  StoredModel createEmptyInstance() => create();
  static $pb.PbList<StoredModel> createRepeated() => $pb.PbList<StoredModel>();
  @$core.pragma('dart2js:noInline')
  static StoredModel getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StoredModel>(create);
  static StoredModel? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearSizeBytes() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get localPath => $_getSZ(3);
  @$pb.TagNumber(4)
  set localPath($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLocalPath() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocalPath() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get downloadedAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set downloadedAtMs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDownloadedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearDownloadedAtMs() => clearField(5);
}

class StorageInfoRequest extends $pb.GeneratedMessage {
  factory StorageInfoRequest({
    $core.bool? includeDevice,
    $core.bool? includeApp,
    $core.bool? includeModels,
  }) {
    final $result = create();
    if (includeDevice != null) {
      $result.includeDevice = includeDevice;
    }
    if (includeApp != null) {
      $result.includeApp = includeApp;
    }
    if (includeModels != null) {
      $result.includeModels = includeModels;
    }
    return $result;
  }
  StorageInfoRequest._() : super();
  factory StorageInfoRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageInfoRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageInfoRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'includeDevice')
    ..aOB(2, _omitFieldNames ? '' : 'includeApp')
    ..aOB(3, _omitFieldNames ? '' : 'includeModels')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageInfoRequest clone() => StorageInfoRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageInfoRequest copyWith(void Function(StorageInfoRequest) updates) => super.copyWith((message) => updates(message as StorageInfoRequest)) as StorageInfoRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageInfoRequest create() => StorageInfoRequest._();
  StorageInfoRequest createEmptyInstance() => create();
  static $pb.PbList<StorageInfoRequest> createRepeated() => $pb.PbList<StorageInfoRequest>();
  @$core.pragma('dart2js:noInline')
  static StorageInfoRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageInfoRequest>(create);
  static StorageInfoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get includeDevice => $_getBF(0);
  @$pb.TagNumber(1)
  set includeDevice($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasIncludeDevice() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncludeDevice() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get includeApp => $_getBF(1);
  @$pb.TagNumber(2)
  set includeApp($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIncludeApp() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeApp() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeModels => $_getBF(2);
  @$pb.TagNumber(3)
  set includeModels($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIncludeModels() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeModels() => clearField(3);
}

class StorageInfoResult extends $pb.GeneratedMessage {
  factory StorageInfoResult({
    $core.bool? success,
    StorageInfo? info,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (info != null) {
      $result.info = info;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  StorageInfoResult._() : super();
  factory StorageInfoResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageInfoResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageInfoResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<StorageInfo>(2, _omitFieldNames ? '' : 'info', subBuilder: StorageInfo.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageInfoResult clone() => StorageInfoResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageInfoResult copyWith(void Function(StorageInfoResult) updates) => super.copyWith((message) => updates(message as StorageInfoResult)) as StorageInfoResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageInfoResult create() => StorageInfoResult._();
  StorageInfoResult createEmptyInstance() => create();
  static $pb.PbList<StorageInfoResult> createRepeated() => $pb.PbList<StorageInfoResult>();
  @$core.pragma('dart2js:noInline')
  static StorageInfoResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageInfoResult>(create);
  static StorageInfoResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  StorageInfo get info => $_getN(1);
  @$pb.TagNumber(2)
  set info(StorageInfo v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasInfo() => $_has(1);
  @$pb.TagNumber(2)
  void clearInfo() => clearField(2);
  @$pb.TagNumber(2)
  StorageInfo ensureInfo() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => clearField(3);
}

class StorageAvailabilityRequest extends $pb.GeneratedMessage {
  factory StorageAvailabilityRequest({
    $core.String? modelId,
    $fixnum.Int64? requiredBytes,
    $core.double? safetyMargin,
    $core.bool? includeExistingModelBytes,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (requiredBytes != null) {
      $result.requiredBytes = requiredBytes;
    }
    if (safetyMargin != null) {
      $result.safetyMargin = safetyMargin;
    }
    if (includeExistingModelBytes != null) {
      $result.includeExistingModelBytes = includeExistingModelBytes;
    }
    return $result;
  }
  StorageAvailabilityRequest._() : super();
  factory StorageAvailabilityRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageAvailabilityRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageAvailabilityRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'safetyMargin', $pb.PbFieldType.OD)
    ..aOB(4, _omitFieldNames ? '' : 'includeExistingModelBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageAvailabilityRequest clone() => StorageAvailabilityRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageAvailabilityRequest copyWith(void Function(StorageAvailabilityRequest) updates) => super.copyWith((message) => updates(message as StorageAvailabilityRequest)) as StorageAvailabilityRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityRequest create() => StorageAvailabilityRequest._();
  StorageAvailabilityRequest createEmptyInstance() => create();
  static $pb.PbList<StorageAvailabilityRequest> createRepeated() => $pb.PbList<StorageAvailabilityRequest>();
  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageAvailabilityRequest>(create);
  static StorageAvailabilityRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get safetyMargin => $_getN(2);
  @$pb.TagNumber(3)
  set safetyMargin($core.double v) { $_setDouble(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSafetyMargin() => $_has(2);
  @$pb.TagNumber(3)
  void clearSafetyMargin() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get includeExistingModelBytes => $_getBF(3);
  @$pb.TagNumber(4)
  set includeExistingModelBytes($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIncludeExistingModelBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearIncludeExistingModelBytes() => clearField(4);
}

class StorageAvailabilityResult extends $pb.GeneratedMessage {
  factory StorageAvailabilityResult({
    $core.bool? success,
    StorageAvailability? availability,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (availability != null) {
      $result.availability = availability;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  StorageAvailabilityResult._() : super();
  factory StorageAvailabilityResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageAvailabilityResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageAvailabilityResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOM<StorageAvailability>(2, _omitFieldNames ? '' : 'availability', subBuilder: StorageAvailability.create)
    ..pPS(3, _omitFieldNames ? '' : 'warnings')
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageAvailabilityResult clone() => StorageAvailabilityResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageAvailabilityResult copyWith(void Function(StorageAvailabilityResult) updates) => super.copyWith((message) => updates(message as StorageAvailabilityResult)) as StorageAvailabilityResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityResult create() => StorageAvailabilityResult._();
  StorageAvailabilityResult createEmptyInstance() => create();
  static $pb.PbList<StorageAvailabilityResult> createRepeated() => $pb.PbList<StorageAvailabilityResult>();
  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageAvailabilityResult>(create);
  static StorageAvailabilityResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  StorageAvailability get availability => $_getN(1);
  @$pb.TagNumber(2)
  set availability(StorageAvailability v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasAvailability() => $_has(1);
  @$pb.TagNumber(2)
  void clearAvailability() => clearField(2);
  @$pb.TagNumber(2)
  StorageAvailability ensureAvailability() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.String> get warnings => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => clearField(4);
}

class StorageDeletePlanRequest extends $pb.GeneratedMessage {
  factory StorageDeletePlanRequest({
    $core.Iterable<$core.String>? modelIds,
    $fixnum.Int64? requiredBytes,
    $core.bool? includeCache,
    $core.bool? oldestFirst,
  }) {
    final $result = create();
    if (modelIds != null) {
      $result.modelIds.addAll(modelIds);
    }
    if (requiredBytes != null) {
      $result.requiredBytes = requiredBytes;
    }
    if (includeCache != null) {
      $result.includeCache = includeCache;
    }
    if (oldestFirst != null) {
      $result.oldestFirst = oldestFirst;
    }
    return $result;
  }
  StorageDeletePlanRequest._() : super();
  factory StorageDeletePlanRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageDeletePlanRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageDeletePlanRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'modelIds')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aOB(3, _omitFieldNames ? '' : 'includeCache')
    ..aOB(4, _omitFieldNames ? '' : 'oldestFirst')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageDeletePlanRequest clone() => StorageDeletePlanRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageDeletePlanRequest copyWith(void Function(StorageDeletePlanRequest) updates) => super.copyWith((message) => updates(message as StorageDeletePlanRequest)) as StorageDeletePlanRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeletePlanRequest create() => StorageDeletePlanRequest._();
  StorageDeletePlanRequest createEmptyInstance() => create();
  static $pb.PbList<StorageDeletePlanRequest> createRepeated() => $pb.PbList<StorageDeletePlanRequest>();
  @$core.pragma('dart2js:noInline')
  static StorageDeletePlanRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageDeletePlanRequest>(create);
  static StorageDeletePlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get modelIds => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeCache => $_getBF(2);
  @$pb.TagNumber(3)
  set includeCache($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIncludeCache() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeCache() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get oldestFirst => $_getBF(3);
  @$pb.TagNumber(4)
  set oldestFirst($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOldestFirst() => $_has(3);
  @$pb.TagNumber(4)
  void clearOldestFirst() => clearField(4);
}

class StorageDeleteCandidate extends $pb.GeneratedMessage {
  factory StorageDeleteCandidate({
    $core.String? modelId,
    $fixnum.Int64? reclaimableBytes,
    $fixnum.Int64? lastUsedMs,
    $core.bool? isLoaded,
    $core.String? localPath,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (reclaimableBytes != null) {
      $result.reclaimableBytes = reclaimableBytes;
    }
    if (lastUsedMs != null) {
      $result.lastUsedMs = lastUsedMs;
    }
    if (isLoaded != null) {
      $result.isLoaded = isLoaded;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    return $result;
  }
  StorageDeleteCandidate._() : super();
  factory StorageDeleteCandidate.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageDeleteCandidate.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageDeleteCandidate', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'reclaimableBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'lastUsedMs')
    ..aOB(4, _omitFieldNames ? '' : 'isLoaded')
    ..aOS(5, _omitFieldNames ? '' : 'localPath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageDeleteCandidate clone() => StorageDeleteCandidate()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageDeleteCandidate copyWith(void Function(StorageDeleteCandidate) updates) => super.copyWith((message) => updates(message as StorageDeleteCandidate)) as StorageDeleteCandidate;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeleteCandidate create() => StorageDeleteCandidate._();
  StorageDeleteCandidate createEmptyInstance() => create();
  static $pb.PbList<StorageDeleteCandidate> createRepeated() => $pb.PbList<StorageDeleteCandidate>();
  @$core.pragma('dart2js:noInline')
  static StorageDeleteCandidate getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageDeleteCandidate>(create);
  static StorageDeleteCandidate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get reclaimableBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set reclaimableBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReclaimableBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearReclaimableBytes() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get lastUsedMs => $_getI64(2);
  @$pb.TagNumber(3)
  set lastUsedMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLastUsedMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastUsedMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isLoaded => $_getBF(3);
  @$pb.TagNumber(4)
  set isLoaded($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsLoaded() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsLoaded() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get localPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set localPath($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasLocalPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearLocalPath() => clearField(5);
}

class StorageDeletePlan extends $pb.GeneratedMessage {
  factory StorageDeletePlan({
    $core.bool? canReclaimRequiredBytes,
    $fixnum.Int64? requiredBytes,
    $fixnum.Int64? reclaimableBytes,
    $core.Iterable<StorageDeleteCandidate>? candidates,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (canReclaimRequiredBytes != null) {
      $result.canReclaimRequiredBytes = canReclaimRequiredBytes;
    }
    if (requiredBytes != null) {
      $result.requiredBytes = requiredBytes;
    }
    if (reclaimableBytes != null) {
      $result.reclaimableBytes = reclaimableBytes;
    }
    if (candidates != null) {
      $result.candidates.addAll(candidates);
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  StorageDeletePlan._() : super();
  factory StorageDeletePlan.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageDeletePlan.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageDeletePlan', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'canReclaimRequiredBytes')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'reclaimableBytes')
    ..pc<StorageDeleteCandidate>(4, _omitFieldNames ? '' : 'candidates', $pb.PbFieldType.PM, subBuilder: StorageDeleteCandidate.create)
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageDeletePlan clone() => StorageDeletePlan()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageDeletePlan copyWith(void Function(StorageDeletePlan) updates) => super.copyWith((message) => updates(message as StorageDeletePlan)) as StorageDeletePlan;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeletePlan create() => StorageDeletePlan._();
  StorageDeletePlan createEmptyInstance() => create();
  static $pb.PbList<StorageDeletePlan> createRepeated() => $pb.PbList<StorageDeletePlan>();
  @$core.pragma('dart2js:noInline')
  static StorageDeletePlan getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageDeletePlan>(create);
  static StorageDeletePlan? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get canReclaimRequiredBytes => $_getBF(0);
  @$pb.TagNumber(1)
  set canReclaimRequiredBytes($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCanReclaimRequiredBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearCanReclaimRequiredBytes() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get reclaimableBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set reclaimableBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasReclaimableBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearReclaimableBytes() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<StorageDeleteCandidate> get candidates => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => clearField(6);
}

class StorageDeleteRequest extends $pb.GeneratedMessage {
  factory StorageDeleteRequest({
    $core.Iterable<$core.String>? modelIds,
    $core.bool? deleteFiles,
    $core.bool? clearRegistryPaths,
    $core.bool? unloadIfLoaded,
    $core.bool? dryRun,
  }) {
    final $result = create();
    if (modelIds != null) {
      $result.modelIds.addAll(modelIds);
    }
    if (deleteFiles != null) {
      $result.deleteFiles = deleteFiles;
    }
    if (clearRegistryPaths != null) {
      $result.clearRegistryPaths = clearRegistryPaths;
    }
    if (unloadIfLoaded != null) {
      $result.unloadIfLoaded = unloadIfLoaded;
    }
    if (dryRun != null) {
      $result.dryRun = dryRun;
    }
    return $result;
  }
  StorageDeleteRequest._() : super();
  factory StorageDeleteRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageDeleteRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageDeleteRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'modelIds')
    ..aOB(2, _omitFieldNames ? '' : 'deleteFiles')
    ..aOB(3, _omitFieldNames ? '' : 'clearRegistryPaths')
    ..aOB(4, _omitFieldNames ? '' : 'unloadIfLoaded')
    ..aOB(5, _omitFieldNames ? '' : 'dryRun')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageDeleteRequest clone() => StorageDeleteRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageDeleteRequest copyWith(void Function(StorageDeleteRequest) updates) => super.copyWith((message) => updates(message as StorageDeleteRequest)) as StorageDeleteRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeleteRequest create() => StorageDeleteRequest._();
  StorageDeleteRequest createEmptyInstance() => create();
  static $pb.PbList<StorageDeleteRequest> createRepeated() => $pb.PbList<StorageDeleteRequest>();
  @$core.pragma('dart2js:noInline')
  static StorageDeleteRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageDeleteRequest>(create);
  static StorageDeleteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get modelIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get deleteFiles => $_getBF(1);
  @$pb.TagNumber(2)
  set deleteFiles($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeleteFiles() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeleteFiles() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get clearRegistryPaths => $_getBF(2);
  @$pb.TagNumber(3)
  set clearRegistryPaths($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasClearRegistryPaths() => $_has(2);
  @$pb.TagNumber(3)
  void clearClearRegistryPaths() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get unloadIfLoaded => $_getBF(3);
  @$pb.TagNumber(4)
  set unloadIfLoaded($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUnloadIfLoaded() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnloadIfLoaded() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get dryRun => $_getBF(4);
  @$pb.TagNumber(5)
  set dryRun($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDryRun() => $_has(4);
  @$pb.TagNumber(5)
  void clearDryRun() => clearField(5);
}

class StorageDeleteResult extends $pb.GeneratedMessage {
  factory StorageDeleteResult({
    $core.bool? success,
    $fixnum.Int64? deletedBytes,
    $core.Iterable<$core.String>? deletedModelIds,
    $core.Iterable<$core.String>? failedModelIds,
    $core.Iterable<$core.String>? warnings,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (deletedBytes != null) {
      $result.deletedBytes = deletedBytes;
    }
    if (deletedModelIds != null) {
      $result.deletedModelIds.addAll(deletedModelIds);
    }
    if (failedModelIds != null) {
      $result.failedModelIds.addAll(failedModelIds);
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  StorageDeleteResult._() : super();
  factory StorageDeleteResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageDeleteResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StorageDeleteResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aInt64(2, _omitFieldNames ? '' : 'deletedBytes')
    ..pPS(3, _omitFieldNames ? '' : 'deletedModelIds')
    ..pPS(4, _omitFieldNames ? '' : 'failedModelIds')
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageDeleteResult clone() => StorageDeleteResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageDeleteResult copyWith(void Function(StorageDeleteResult) updates) => super.copyWith((message) => updates(message as StorageDeleteResult)) as StorageDeleteResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeleteResult create() => StorageDeleteResult._();
  StorageDeleteResult createEmptyInstance() => create();
  static $pb.PbList<StorageDeleteResult> createRepeated() => $pb.PbList<StorageDeleteResult>();
  @$core.pragma('dart2js:noInline')
  static StorageDeleteResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StorageDeleteResult>(create);
  static StorageDeleteResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get deletedBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set deletedBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDeletedBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeletedBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.String> get deletedModelIds => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.String> get failedModelIds => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => clearField(6);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
