///
//  Generated code. Do not modify.
//  source: storage_types.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'storage_types.pbenum.dart';

class DeviceStorageInfo extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DeviceStorageInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalBytes')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'freeBytes')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'usedBytes')
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'usedPercent', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  DeviceStorageInfo._() : super();
  factory DeviceStorageInfo({
    $fixnum.Int64? totalBytes,
    $fixnum.Int64? freeBytes,
    $fixnum.Int64? usedBytes,
    $core.double? usedPercent,
  }) {
    final _result = create();
    if (totalBytes != null) {
      _result.totalBytes = totalBytes;
    }
    if (freeBytes != null) {
      _result.freeBytes = freeBytes;
    }
    if (usedBytes != null) {
      _result.usedBytes = usedBytes;
    }
    if (usedPercent != null) {
      _result.usedPercent = usedPercent;
    }
    return _result;
  }
  factory DeviceStorageInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DeviceStorageInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DeviceStorageInfo clone() => DeviceStorageInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DeviceStorageInfo copyWith(void Function(DeviceStorageInfo) updates) => super.copyWith((message) => updates(message as DeviceStorageInfo)) as DeviceStorageInfo; // ignore: deprecated_member_use
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

class AppStorageInfo extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'AppStorageInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'documentsBytes')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'cacheBytes')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'appSupportBytes')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalBytes')
    ..hasRequiredFields = false
  ;

  AppStorageInfo._() : super();
  factory AppStorageInfo({
    $fixnum.Int64? documentsBytes,
    $fixnum.Int64? cacheBytes,
    $fixnum.Int64? appSupportBytes,
    $fixnum.Int64? totalBytes,
  }) {
    final _result = create();
    if (documentsBytes != null) {
      _result.documentsBytes = documentsBytes;
    }
    if (cacheBytes != null) {
      _result.cacheBytes = cacheBytes;
    }
    if (appSupportBytes != null) {
      _result.appSupportBytes = appSupportBytes;
    }
    if (totalBytes != null) {
      _result.totalBytes = totalBytes;
    }
    return _result;
  }
  factory AppStorageInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AppStorageInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AppStorageInfo clone() => AppStorageInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AppStorageInfo copyWith(void Function(AppStorageInfo) updates) => super.copyWith((message) => updates(message as AppStorageInfo)) as AppStorageInfo; // ignore: deprecated_member_use
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

class ModelStorageMetrics extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ModelStorageMetrics', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sizeOnDiskBytes')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'lastUsedMs')
    ..hasRequiredFields = false
  ;

  ModelStorageMetrics._() : super();
  factory ModelStorageMetrics({
    $core.String? modelId,
    $fixnum.Int64? sizeOnDiskBytes,
    $fixnum.Int64? lastUsedMs,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (sizeOnDiskBytes != null) {
      _result.sizeOnDiskBytes = sizeOnDiskBytes;
    }
    if (lastUsedMs != null) {
      _result.lastUsedMs = lastUsedMs;
    }
    return _result;
  }
  factory ModelStorageMetrics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ModelStorageMetrics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ModelStorageMetrics clone() => ModelStorageMetrics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ModelStorageMetrics copyWith(void Function(ModelStorageMetrics) updates) => super.copyWith((message) => updates(message as ModelStorageMetrics)) as ModelStorageMetrics; // ignore: deprecated_member_use
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

class StorageInfo extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StorageInfo', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<AppStorageInfo>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'app', subBuilder: AppStorageInfo.create)
    ..aOM<DeviceStorageInfo>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'device', subBuilder: DeviceStorageInfo.create)
    ..pc<ModelStorageMetrics>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'models', $pb.PbFieldType.PM, subBuilder: ModelStorageMetrics.create)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalModels', $pb.PbFieldType.O3)
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalModelsBytes')
    ..hasRequiredFields = false
  ;

  StorageInfo._() : super();
  factory StorageInfo({
    AppStorageInfo? app,
    DeviceStorageInfo? device,
    $core.Iterable<ModelStorageMetrics>? models,
    $core.int? totalModels,
    $fixnum.Int64? totalModelsBytes,
  }) {
    final _result = create();
    if (app != null) {
      _result.app = app;
    }
    if (device != null) {
      _result.device = device;
    }
    if (models != null) {
      _result.models.addAll(models);
    }
    if (totalModels != null) {
      _result.totalModels = totalModels;
    }
    if (totalModelsBytes != null) {
      _result.totalModelsBytes = totalModelsBytes;
    }
    return _result;
  }
  factory StorageInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageInfo clone() => StorageInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageInfo copyWith(void Function(StorageInfo) updates) => super.copyWith((message) => updates(message as StorageInfo)) as StorageInfo; // ignore: deprecated_member_use
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

class StorageAvailability extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StorageAvailability', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isAvailable')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'requiredBytes')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'availableBytes')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'warningMessage')
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'recommendation')
    ..hasRequiredFields = false
  ;

  StorageAvailability._() : super();
  factory StorageAvailability({
    $core.bool? isAvailable,
    $fixnum.Int64? requiredBytes,
    $fixnum.Int64? availableBytes,
    $core.String? warningMessage,
    $core.String? recommendation,
  }) {
    final _result = create();
    if (isAvailable != null) {
      _result.isAvailable = isAvailable;
    }
    if (requiredBytes != null) {
      _result.requiredBytes = requiredBytes;
    }
    if (availableBytes != null) {
      _result.availableBytes = availableBytes;
    }
    if (warningMessage != null) {
      _result.warningMessage = warningMessage;
    }
    if (recommendation != null) {
      _result.recommendation = recommendation;
    }
    return _result;
  }
  factory StorageAvailability.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StorageAvailability.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StorageAvailability clone() => StorageAvailability()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StorageAvailability copyWith(void Function(StorageAvailability) updates) => super.copyWith((message) => updates(message as StorageAvailability)) as StorageAvailability; // ignore: deprecated_member_use
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

class StoredModel extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StoredModel', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'name')
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sizeBytes')
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'localPath')
    ..aInt64(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'downloadedAtMs')
    ..hasRequiredFields = false
  ;

  StoredModel._() : super();
  factory StoredModel({
    $core.String? modelId,
    $core.String? name,
    $fixnum.Int64? sizeBytes,
    $core.String? localPath,
    $fixnum.Int64? downloadedAtMs,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (name != null) {
      _result.name = name;
    }
    if (sizeBytes != null) {
      _result.sizeBytes = sizeBytes;
    }
    if (localPath != null) {
      _result.localPath = localPath;
    }
    if (downloadedAtMs != null) {
      _result.downloadedAtMs = downloadedAtMs;
    }
    return _result;
  }
  factory StoredModel.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StoredModel.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StoredModel clone() => StoredModel()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StoredModel copyWith(void Function(StoredModel) updates) => super.copyWith((message) => updates(message as StoredModel)) as StoredModel; // ignore: deprecated_member_use
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

