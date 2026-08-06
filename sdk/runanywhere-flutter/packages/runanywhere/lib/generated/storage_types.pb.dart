// This is a generated file - do not edit.
//
// Generated from storage_types.proto.

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

export 'storage_types.pbenum.dart';

class DeviceStorageInfo extends $pb.GeneratedMessage {
  factory DeviceStorageInfo({
    $fixnum.Int64? totalBytes,
    $fixnum.Int64? freeBytes,
    $fixnum.Int64? usedBytes,
  }) {
    final result = create();
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (freeBytes != null) result.freeBytes = freeBytes;
    if (usedBytes != null) result.usedBytes = usedBytes;
    return result;
  }

  DeviceStorageInfo._();

  factory DeviceStorageInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceStorageInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceStorageInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'totalBytes')
    ..aInt64(2, _omitFieldNames ? '' : 'freeBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'usedBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceStorageInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceStorageInfo copyWith(void Function(DeviceStorageInfo) updates) =>
      super.copyWith((message) => updates(message as DeviceStorageInfo))
          as DeviceStorageInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceStorageInfo create() => DeviceStorageInfo._();
  @$core.override
  DeviceStorageInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceStorageInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceStorageInfo>(create);
  static DeviceStorageInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get totalBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set totalBytes($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTotalBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearTotalBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get freeBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set freeBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFreeBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearFreeBytes() => $_clearField(2);

  /// Distinct from total-minus-free: this is the adapter's own reading of
  /// occupied space, not a derivation. Kept live.
  @$pb.TagNumber(3)
  $fixnum.Int64 get usedBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set usedBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUsedBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearUsedBytes() => $_clearField(3);
}

class AppStorageInfo extends $pb.GeneratedMessage {
  factory AppStorageInfo({
    $fixnum.Int64? documentsBytes,
    $fixnum.Int64? cacheBytes,
    $fixnum.Int64? appSupportBytes,
    $fixnum.Int64? totalBytes,
  }) {
    final result = create();
    if (documentsBytes != null) result.documentsBytes = documentsBytes;
    if (cacheBytes != null) result.cacheBytes = cacheBytes;
    if (appSupportBytes != null) result.appSupportBytes = appSupportBytes;
    if (totalBytes != null) result.totalBytes = totalBytes;
    return result;
  }

  AppStorageInfo._();

  factory AppStorageInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AppStorageInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AppStorageInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'documentsBytes')
    ..aInt64(2, _omitFieldNames ? '' : 'cacheBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'appSupportBytes')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppStorageInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AppStorageInfo copyWith(void Function(AppStorageInfo) updates) =>
      super.copyWith((message) => updates(message as AppStorageInfo))
          as AppStorageInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AppStorageInfo create() => AppStorageInfo._();
  @$core.override
  AppStorageInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AppStorageInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AppStorageInfo>(create);
  static AppStorageInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get documentsBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set documentsBytes($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDocumentsBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearDocumentsBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get cacheBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set cacheBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCacheBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearCacheBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get appSupportBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set appSupportBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAppSupportBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearAppSupportBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => $_clearField(4);
}

class ModelStorageMetrics extends $pb.GeneratedMessage {
  factory ModelStorageMetrics({
    $core.String? modelId,
    $fixnum.Int64? sizeOnDiskBytes,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (sizeOnDiskBytes != null) result.sizeOnDiskBytes = sizeOnDiskBytes;
    return result;
  }

  ModelStorageMetrics._();

  factory ModelStorageMetrics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelStorageMetrics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelStorageMetrics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'sizeOnDiskBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelStorageMetrics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelStorageMetrics copyWith(void Function(ModelStorageMetrics) updates) =>
      super.copyWith((message) => updates(message as ModelStorageMetrics))
          as ModelStorageMetrics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelStorageMetrics create() => ModelStorageMetrics._();
  @$core.override
  ModelStorageMetrics createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelStorageMetrics getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelStorageMetrics>(create);
  static ModelStorageMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sizeOnDiskBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set sizeOnDiskBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSizeOnDiskBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearSizeOnDiskBytes() => $_clearField(2);
}

class StorageInfo extends $pb.GeneratedMessage {
  factory StorageInfo({
    AppStorageInfo? app,
    DeviceStorageInfo? device,
    $core.Iterable<ModelStorageMetrics>? models,
    $fixnum.Int64? totalModelsBytes,
  }) {
    final result = create();
    if (app != null) result.app = app;
    if (device != null) result.device = device;
    if (models != null) result.models.addAll(models);
    if (totalModelsBytes != null) result.totalModelsBytes = totalModelsBytes;
    return result;
  }

  StorageInfo._();

  factory StorageInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<AppStorageInfo>(1, _omitFieldNames ? '' : 'app',
        subBuilder: AppStorageInfo.create)
    ..aOM<DeviceStorageInfo>(2, _omitFieldNames ? '' : 'device',
        subBuilder: DeviceStorageInfo.create)
    ..pPM<ModelStorageMetrics>(3, _omitFieldNames ? '' : 'models',
        subBuilder: ModelStorageMetrics.create)
    ..aInt64(5, _omitFieldNames ? '' : 'totalModelsBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageInfo copyWith(void Function(StorageInfo) updates) =>
      super.copyWith((message) => updates(message as StorageInfo))
          as StorageInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageInfo create() => StorageInfo._();
  @$core.override
  StorageInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageInfo>(create);
  static StorageInfo? _defaultInstance;

  @$pb.TagNumber(1)
  AppStorageInfo get app => $_getN(0);
  @$pb.TagNumber(1)
  set app(AppStorageInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasApp() => $_has(0);
  @$pb.TagNumber(1)
  void clearApp() => $_clearField(1);
  @$pb.TagNumber(1)
  AppStorageInfo ensureApp() => $_ensure(0);

  @$pb.TagNumber(2)
  DeviceStorageInfo get device => $_getN(1);
  @$pb.TagNumber(2)
  set device(DeviceStorageInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevice() => $_clearField(2);
  @$pb.TagNumber(2)
  DeviceStorageInfo ensureDevice() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<ModelStorageMetrics> get models => $_getList(2);

  /// total_models_bytes (5) is NOT a pure derivation -- kept live; see
  /// storage_event_publisher.cpp and two facade readers.
  @$pb.TagNumber(5)
  $fixnum.Int64 get totalModelsBytes => $_getI64(3);
  @$pb.TagNumber(5)
  set totalModelsBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalModelsBytes() => $_has(3);
  @$pb.TagNumber(5)
  void clearTotalModelsBytes() => $_clearField(5);
}

class StorageAvailability extends $pb.GeneratedMessage {
  factory StorageAvailability({
    $core.bool? isAvailable,
    $fixnum.Int64? requiredBytes,
    $fixnum.Int64? availableBytes,
    $core.String? warningMessage,
    $core.String? recommendation,
  }) {
    final result = create();
    if (isAvailable != null) result.isAvailable = isAvailable;
    if (requiredBytes != null) result.requiredBytes = requiredBytes;
    if (availableBytes != null) result.availableBytes = availableBytes;
    if (warningMessage != null) result.warningMessage = warningMessage;
    if (recommendation != null) result.recommendation = recommendation;
    return result;
  }

  StorageAvailability._();

  factory StorageAvailability.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageAvailability.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageAvailability',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'isAvailable')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'availableBytes')
    ..aOS(4, _omitFieldNames ? '' : 'warningMessage')
    ..aOS(5, _omitFieldNames ? '' : 'recommendation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageAvailability clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageAvailability copyWith(void Function(StorageAvailability) updates) =>
      super.copyWith((message) => updates(message as StorageAvailability))
          as StorageAvailability;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageAvailability create() => StorageAvailability._();
  @$core.override
  StorageAvailability createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageAvailability getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageAvailability>(create);
  static StorageAvailability? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get isAvailable => $_getBF(0);
  @$pb.TagNumber(1)
  set isAvailable($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIsAvailable() => $_has(0);
  @$pb.TagNumber(1)
  void clearIsAvailable() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get availableBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set availableBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAvailableBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvailableBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get warningMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set warningMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWarningMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearWarningMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get recommendation => $_getSZ(4);
  @$pb.TagNumber(5)
  set recommendation($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRecommendation() => $_has(4);
  @$pb.TagNumber(5)
  void clearRecommendation() => $_clearField(5);
}

class StorageInfoRequest extends $pb.GeneratedMessage {
  factory StorageInfoRequest({
    $core.bool? includeDevice,
    $core.bool? includeApp,
    $core.bool? includeModels,
    $core.bool? includeCache,
  }) {
    final result = create();
    if (includeDevice != null) result.includeDevice = includeDevice;
    if (includeApp != null) result.includeApp = includeApp;
    if (includeModels != null) result.includeModels = includeModels;
    if (includeCache != null) result.includeCache = includeCache;
    return result;
  }

  StorageInfoRequest._();

  factory StorageInfoRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageInfoRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageInfoRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'includeDevice')
    ..aOB(2, _omitFieldNames ? '' : 'includeApp')
    ..aOB(3, _omitFieldNames ? '' : 'includeModels')
    ..aOB(4, _omitFieldNames ? '' : 'includeCache')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageInfoRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageInfoRequest copyWith(void Function(StorageInfoRequest) updates) =>
      super.copyWith((message) => updates(message as StorageInfoRequest))
          as StorageInfoRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageInfoRequest create() => StorageInfoRequest._();
  @$core.override
  StorageInfoRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageInfoRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageInfoRequest>(create);
  static StorageInfoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get includeDevice => $_getBF(0);
  @$pb.TagNumber(1)
  set includeDevice($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIncludeDevice() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncludeDevice() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get includeApp => $_getBF(1);
  @$pb.TagNumber(2)
  set includeApp($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncludeApp() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeApp() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeModels => $_getBF(2);
  @$pb.TagNumber(3)
  set includeModels($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIncludeModels() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeModels() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get includeCache => $_getBF(3);
  @$pb.TagNumber(4)
  set includeCache($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIncludeCache() => $_has(3);
  @$pb.TagNumber(4)
  void clearIncludeCache() => $_clearField(4);
}

class StorageInfoResult extends $pb.GeneratedMessage {
  factory StorageInfoResult({
    StorageInfo? info,
    $core.Iterable<$core.String>? warnings,
    $0.SDKError? error,
  }) {
    final result = create();
    if (info != null) result.info = info;
    if (warnings != null) result.warnings.addAll(warnings);
    if (error != null) result.error = error;
    return result;
  }

  StorageInfoResult._();

  factory StorageInfoResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageInfoResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageInfoResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<StorageInfo>(2, _omitFieldNames ? '' : 'info',
        subBuilder: StorageInfo.create)
    ..pPS(4, _omitFieldNames ? '' : 'warnings')
    ..aOM<$0.SDKError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageInfoResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageInfoResult copyWith(void Function(StorageInfoResult) updates) =>
      super.copyWith((message) => updates(message as StorageInfoResult))
          as StorageInfoResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageInfoResult create() => StorageInfoResult._();
  @$core.override
  StorageInfoResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageInfoResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageInfoResult>(create);
  static StorageInfoResult? _defaultInstance;

  @$pb.TagNumber(2)
  StorageInfo get info => $_getN(0);
  @$pb.TagNumber(2)
  set info(StorageInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasInfo() => $_has(0);
  @$pb.TagNumber(2)
  void clearInfo() => $_clearField(2);
  @$pb.TagNumber(2)
  StorageInfo ensureInfo() => $_ensure(0);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get warnings => $_getList(1);

  @$pb.TagNumber(5)
  $0.SDKError get error => $_getN(2);
  @$pb.TagNumber(5)
  set error($0.SDKError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.SDKError ensureError() => $_ensure(2);
}

class StorageAvailabilityRequest extends $pb.GeneratedMessage {
  factory StorageAvailabilityRequest({
    $core.String? modelId,
    $fixnum.Int64? requiredBytes,
    $core.bool? includeExistingModelBytes,
    $core.bool? includeDeletePlan,
    $core.bool? allowCacheReclamation,
    $fixnum.Int64? requiredFreeBytesAfterDownload,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (requiredBytes != null) result.requiredBytes = requiredBytes;
    if (includeExistingModelBytes != null)
      result.includeExistingModelBytes = includeExistingModelBytes;
    if (includeDeletePlan != null) result.includeDeletePlan = includeDeletePlan;
    if (allowCacheReclamation != null)
      result.allowCacheReclamation = allowCacheReclamation;
    if (requiredFreeBytesAfterDownload != null)
      result.requiredFreeBytesAfterDownload = requiredFreeBytesAfterDownload;
    return result;
  }

  StorageAvailabilityRequest._();

  factory StorageAvailabilityRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageAvailabilityRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageAvailabilityRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aOB(4, _omitFieldNames ? '' : 'includeExistingModelBytes')
    ..aOB(5, _omitFieldNames ? '' : 'includeDeletePlan')
    ..aOB(6, _omitFieldNames ? '' : 'allowCacheReclamation')
    ..aInt64(7, _omitFieldNames ? '' : 'requiredFreeBytesAfterDownload')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageAvailabilityRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageAvailabilityRequest copyWith(
          void Function(StorageAvailabilityRequest) updates) =>
      super.copyWith(
              (message) => updates(message as StorageAvailabilityRequest))
          as StorageAvailabilityRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityRequest create() => StorageAvailabilityRequest._();
  @$core.override
  StorageAvailabilityRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageAvailabilityRequest>(create);
  static StorageAvailabilityRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => $_clearField(2);

  /// Count bytes already occupied by this model as reclaimable.
  @$pb.TagNumber(4)
  $core.bool get includeExistingModelBytes => $_getBF(2);
  @$pb.TagNumber(4)
  set includeExistingModelBytes($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasIncludeExistingModelBytes() => $_has(2);
  @$pb.TagNumber(4)
  void clearIncludeExistingModelBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get includeDeletePlan => $_getBF(3);
  @$pb.TagNumber(5)
  set includeDeletePlan($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(5)
  $core.bool hasIncludeDeletePlan() => $_has(3);
  @$pb.TagNumber(5)
  void clearIncludeDeletePlan() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get allowCacheReclamation => $_getBF(4);
  @$pb.TagNumber(6)
  set allowCacheReclamation($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(6)
  $core.bool hasAllowCacheReclamation() => $_has(4);
  @$pb.TagNumber(6)
  void clearAllowCacheReclamation() => $_clearField(6);

  /// Absolute headroom the device must still have after the write. Same
  /// unit and same name as DownloadPlanRequest.required_free_bytes_after_download.
  @$pb.TagNumber(7)
  $fixnum.Int64 get requiredFreeBytesAfterDownload => $_getI64(5);
  @$pb.TagNumber(7)
  set requiredFreeBytesAfterDownload($fixnum.Int64 value) =>
      $_setInt64(5, value);
  @$pb.TagNumber(7)
  $core.bool hasRequiredFreeBytesAfterDownload() => $_has(5);
  @$pb.TagNumber(7)
  void clearRequiredFreeBytesAfterDownload() => $_clearField(7);
}

class StorageAvailabilityResult extends $pb.GeneratedMessage {
  factory StorageAvailabilityResult({
    StorageAvailability? availability,
    $core.Iterable<$core.String>? warnings,
    StorageDeletePlan? deletePlan,
    $0.SDKError? error,
  }) {
    final result = create();
    if (availability != null) result.availability = availability;
    if (warnings != null) result.warnings.addAll(warnings);
    if (deletePlan != null) result.deletePlan = deletePlan;
    if (error != null) result.error = error;
    return result;
  }

  StorageAvailabilityResult._();

  factory StorageAvailabilityResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageAvailabilityResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageAvailabilityResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<StorageAvailability>(2, _omitFieldNames ? '' : 'availability',
        subBuilder: StorageAvailability.create)
    ..pPS(3, _omitFieldNames ? '' : 'warnings')
    ..aOM<StorageDeletePlan>(5, _omitFieldNames ? '' : 'deletePlan',
        subBuilder: StorageDeletePlan.create)
    ..aOM<$0.SDKError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageAvailabilityResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageAvailabilityResult copyWith(
          void Function(StorageAvailabilityResult) updates) =>
      super.copyWith((message) => updates(message as StorageAvailabilityResult))
          as StorageAvailabilityResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityResult create() => StorageAvailabilityResult._();
  @$core.override
  StorageAvailabilityResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageAvailabilityResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageAvailabilityResult>(create);
  static StorageAvailabilityResult? _defaultInstance;

  @$pb.TagNumber(2)
  StorageAvailability get availability => $_getN(0);
  @$pb.TagNumber(2)
  set availability(StorageAvailability value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAvailability() => $_has(0);
  @$pb.TagNumber(2)
  void clearAvailability() => $_clearField(2);
  @$pb.TagNumber(2)
  StorageAvailability ensureAvailability() => $_ensure(0);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get warnings => $_getList(1);

  @$pb.TagNumber(5)
  StorageDeletePlan get deletePlan => $_getN(2);
  @$pb.TagNumber(5)
  set deletePlan(StorageDeletePlan value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasDeletePlan() => $_has(2);
  @$pb.TagNumber(5)
  void clearDeletePlan() => $_clearField(5);
  @$pb.TagNumber(5)
  StorageDeletePlan ensureDeletePlan() => $_ensure(2);

  @$pb.TagNumber(6)
  $0.SDKError get error => $_getN(3);
  @$pb.TagNumber(6)
  set error($0.SDKError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.SDKError ensureError() => $_ensure(3);
}

class StorageDeletePlanRequest extends $pb.GeneratedMessage {
  factory StorageDeletePlanRequest({
    $core.Iterable<$core.String>? modelIds,
    $fixnum.Int64? requiredBytes,
    $core.bool? includeCache,
    $core.bool? oldestFirst,
    $core.bool? allowLoadedModels,
    $core.bool? includeDownloadPartials,
  }) {
    final result = create();
    if (modelIds != null) result.modelIds.addAll(modelIds);
    if (requiredBytes != null) result.requiredBytes = requiredBytes;
    if (includeCache != null) result.includeCache = includeCache;
    if (oldestFirst != null) result.oldestFirst = oldestFirst;
    if (allowLoadedModels != null) result.allowLoadedModels = allowLoadedModels;
    if (includeDownloadPartials != null)
      result.includeDownloadPartials = includeDownloadPartials;
    return result;
  }

  StorageDeletePlanRequest._();

  factory StorageDeletePlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageDeletePlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageDeletePlanRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'modelIds')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aOB(3, _omitFieldNames ? '' : 'includeCache')
    ..aOB(4, _omitFieldNames ? '' : 'oldestFirst')
    ..aOB(5, _omitFieldNames ? '' : 'allowLoadedModels')
    ..aOB(6, _omitFieldNames ? '' : 'includeDownloadPartials')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeletePlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeletePlanRequest copyWith(
          void Function(StorageDeletePlanRequest) updates) =>
      super.copyWith((message) => updates(message as StorageDeletePlanRequest))
          as StorageDeletePlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeletePlanRequest create() => StorageDeletePlanRequest._();
  @$core.override
  StorageDeletePlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageDeletePlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageDeletePlanRequest>(create);
  static StorageDeletePlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get modelIds => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get includeCache => $_getBF(2);
  @$pb.TagNumber(3)
  set includeCache($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIncludeCache() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeCache() => $_clearField(3);

  /// Evict by least-recently-used rather than by size.
  @$pb.TagNumber(4)
  $core.bool get oldestFirst => $_getBF(3);
  @$pb.TagNumber(4)
  set oldestFirst($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOldestFirst() => $_has(3);
  @$pb.TagNumber(4)
  void clearOldestFirst() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get allowLoadedModels => $_getBF(4);
  @$pb.TagNumber(5)
  set allowLoadedModels($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAllowLoadedModels() => $_has(4);
  @$pb.TagNumber(5)
  void clearAllowLoadedModels() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeDownloadPartials => $_getBF(5);
  @$pb.TagNumber(6)
  set includeDownloadPartials($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeDownloadPartials() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeDownloadPartials() => $_clearField(6);
}

class StorageDeleteCandidate extends $pb.GeneratedMessage {
  factory StorageDeleteCandidate({
    $core.String? modelId,
    $fixnum.Int64? reclaimableBytes,
    $core.bool? isLoaded,
    $core.String? localPath,
    $core.bool? requiresUnload,
    $core.bool? requiresPlatformDelete,
    $core.String? storageKey,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (reclaimableBytes != null) result.reclaimableBytes = reclaimableBytes;
    if (isLoaded != null) result.isLoaded = isLoaded;
    if (localPath != null) result.localPath = localPath;
    if (requiresUnload != null) result.requiresUnload = requiresUnload;
    if (requiresPlatformDelete != null)
      result.requiresPlatformDelete = requiresPlatformDelete;
    if (storageKey != null) result.storageKey = storageKey;
    return result;
  }

  StorageDeleteCandidate._();

  factory StorageDeleteCandidate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageDeleteCandidate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageDeleteCandidate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(2, _omitFieldNames ? '' : 'reclaimableBytes')
    ..aOB(4, _omitFieldNames ? '' : 'isLoaded')
    ..aOS(5, _omitFieldNames ? '' : 'localPath')
    ..aOB(6, _omitFieldNames ? '' : 'requiresUnload')
    ..aOB(7, _omitFieldNames ? '' : 'requiresPlatformDelete')
    ..aOS(8, _omitFieldNames ? '' : 'storageKey')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeleteCandidate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeleteCandidate copyWith(
          void Function(StorageDeleteCandidate) updates) =>
      super.copyWith((message) => updates(message as StorageDeleteCandidate))
          as StorageDeleteCandidate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeleteCandidate create() => StorageDeleteCandidate._();
  @$core.override
  StorageDeleteCandidate createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageDeleteCandidate getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageDeleteCandidate>(create);
  static StorageDeleteCandidate? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get reclaimableBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set reclaimableBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReclaimableBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearReclaimableBytes() => $_clearField(2);

  @$pb.TagNumber(4)
  $core.bool get isLoaded => $_getBF(2);
  @$pb.TagNumber(4)
  set isLoaded($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasIsLoaded() => $_has(2);
  @$pb.TagNumber(4)
  void clearIsLoaded() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get localPath => $_getSZ(3);
  @$pb.TagNumber(5)
  set localPath($core.String value) => $_setString(3, value);
  @$pb.TagNumber(5)
  $core.bool hasLocalPath() => $_has(3);
  @$pb.TagNumber(5)
  void clearLocalPath() => $_clearField(5);

  /// Deleting this needs an unload first, or a platform-side delete.
  @$pb.TagNumber(6)
  $core.bool get requiresUnload => $_getBF(4);
  @$pb.TagNumber(6)
  set requiresUnload($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(6)
  $core.bool hasRequiresUnload() => $_has(4);
  @$pb.TagNumber(6)
  void clearRequiresUnload() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get requiresPlatformDelete => $_getBF(5);
  @$pb.TagNumber(7)
  set requiresPlatformDelete($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(7)
  $core.bool hasRequiresPlatformDelete() => $_has(5);
  @$pb.TagNumber(7)
  void clearRequiresPlatformDelete() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get storageKey => $_getSZ(6);
  @$pb.TagNumber(8)
  set storageKey($core.String value) => $_setString(6, value);
  @$pb.TagNumber(8)
  $core.bool hasStorageKey() => $_has(6);
  @$pb.TagNumber(8)
  void clearStorageKey() => $_clearField(8);
}

/// Non-destructive: describes what could be reclaimed without doing it.
class StorageDeletePlan extends $pb.GeneratedMessage {
  factory StorageDeletePlan({
    $core.bool? canReclaimRequiredBytes,
    $fixnum.Int64? requiredBytes,
    $fixnum.Int64? reclaimableBytes,
    $core.Iterable<StorageDeleteCandidate>? candidates,
    $core.Iterable<$core.String>? warnings,
    $core.bool? requiresUnload,
    $core.bool? requiresPlatformDelete,
    $0.SDKError? error,
  }) {
    final result = create();
    if (canReclaimRequiredBytes != null)
      result.canReclaimRequiredBytes = canReclaimRequiredBytes;
    if (requiredBytes != null) result.requiredBytes = requiredBytes;
    if (reclaimableBytes != null) result.reclaimableBytes = reclaimableBytes;
    if (candidates != null) result.candidates.addAll(candidates);
    if (warnings != null) result.warnings.addAll(warnings);
    if (requiresUnload != null) result.requiresUnload = requiresUnload;
    if (requiresPlatformDelete != null)
      result.requiresPlatformDelete = requiresPlatformDelete;
    if (error != null) result.error = error;
    return result;
  }

  StorageDeletePlan._();

  factory StorageDeletePlan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageDeletePlan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageDeletePlan',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'canReclaimRequiredBytes')
    ..aInt64(2, _omitFieldNames ? '' : 'requiredBytes')
    ..aInt64(3, _omitFieldNames ? '' : 'reclaimableBytes')
    ..pPM<StorageDeleteCandidate>(4, _omitFieldNames ? '' : 'candidates',
        subBuilder: StorageDeleteCandidate.create)
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..aOB(7, _omitFieldNames ? '' : 'requiresUnload')
    ..aOB(8, _omitFieldNames ? '' : 'requiresPlatformDelete')
    ..aOM<$0.SDKError>(10, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeletePlan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeletePlan copyWith(void Function(StorageDeletePlan) updates) =>
      super.copyWith((message) => updates(message as StorageDeletePlan))
          as StorageDeletePlan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeletePlan create() => StorageDeletePlan._();
  @$core.override
  StorageDeletePlan createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageDeletePlan getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageDeletePlan>(create);
  static StorageDeletePlan? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get canReclaimRequiredBytes => $_getBF(0);
  @$pb.TagNumber(1)
  set canReclaimRequiredBytes($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCanReclaimRequiredBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearCanReclaimRequiredBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get requiredBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set requiredBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequiredBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequiredBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get reclaimableBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set reclaimableBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReclaimableBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearReclaimableBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<StorageDeleteCandidate> get candidates => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get warnings => $_getList(4);

  @$pb.TagNumber(7)
  $core.bool get requiresUnload => $_getBF(5);
  @$pb.TagNumber(7)
  set requiresUnload($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(7)
  $core.bool hasRequiresUnload() => $_has(5);
  @$pb.TagNumber(7)
  void clearRequiresUnload() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get requiresPlatformDelete => $_getBF(6);
  @$pb.TagNumber(8)
  set requiresPlatformDelete($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(8)
  $core.bool hasRequiresPlatformDelete() => $_has(6);
  @$pb.TagNumber(8)
  void clearRequiresPlatformDelete() => $_clearField(8);

  @$pb.TagNumber(10)
  $0.SDKError get error => $_getN(7);
  @$pb.TagNumber(10)
  set error($0.SDKError value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasError() => $_has(7);
  @$pb.TagNumber(10)
  void clearError() => $_clearField(10);
  @$pb.TagNumber(10)
  $0.SDKError ensureError() => $_ensure(7);
}

class StorageDeleteRequest extends $pb.GeneratedMessage {
  factory StorageDeleteRequest({
    $core.Iterable<$core.String>? modelIds,
    $core.bool? keepFilesOnDisk,
    $core.bool? clearRegistryPaths,
    $core.bool? unloadIfLoaded,
    $core.bool? dryRun,
    StorageDeletePlan? plan,
    $core.bool? requirePlanMatch,
    $core.bool? allowPlatformDelete,
  }) {
    final result = create();
    if (modelIds != null) result.modelIds.addAll(modelIds);
    if (keepFilesOnDisk != null) result.keepFilesOnDisk = keepFilesOnDisk;
    if (clearRegistryPaths != null)
      result.clearRegistryPaths = clearRegistryPaths;
    if (unloadIfLoaded != null) result.unloadIfLoaded = unloadIfLoaded;
    if (dryRun != null) result.dryRun = dryRun;
    if (plan != null) result.plan = plan;
    if (requirePlanMatch != null) result.requirePlanMatch = requirePlanMatch;
    if (allowPlatformDelete != null)
      result.allowPlatformDelete = allowPlatformDelete;
    return result;
  }

  StorageDeleteRequest._();

  factory StorageDeleteRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageDeleteRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageDeleteRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'modelIds')
    ..aOB(2, _omitFieldNames ? '' : 'keepFilesOnDisk')
    ..aOB(3, _omitFieldNames ? '' : 'clearRegistryPaths')
    ..aOB(4, _omitFieldNames ? '' : 'unloadIfLoaded')
    ..aOB(5, _omitFieldNames ? '' : 'dryRun')
    ..aOM<StorageDeletePlan>(6, _omitFieldNames ? '' : 'plan',
        subBuilder: StorageDeletePlan.create)
    ..aOB(7, _omitFieldNames ? '' : 'requirePlanMatch')
    ..aOB(8, _omitFieldNames ? '' : 'allowPlatformDelete')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeleteRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeleteRequest copyWith(void Function(StorageDeleteRequest) updates) =>
      super.copyWith((message) => updates(message as StorageDeleteRequest))
          as StorageDeleteRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeleteRequest create() => StorageDeleteRequest._();
  @$core.override
  StorageDeleteRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageDeleteRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageDeleteRequest>(create);
  static StorageDeleteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get modelIds => $_getList(0);

  /// Files are deleted; set this only to opt OUT (catalog-only bookkeeping).
  @$pb.TagNumber(2)
  $core.bool get keepFilesOnDisk => $_getBF(1);
  @$pb.TagNumber(2)
  set keepFilesOnDisk($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasKeepFilesOnDisk() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeepFilesOnDisk() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get clearRegistryPaths => $_getBF(2);
  @$pb.TagNumber(3)
  set clearRegistryPaths($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClearRegistryPaths() => $_has(2);
  @$pb.TagNumber(3)
  void clearClearRegistryPaths() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get unloadIfLoaded => $_getBF(3);
  @$pb.TagNumber(4)
  set unloadIfLoaded($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUnloadIfLoaded() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnloadIfLoaded() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get dryRun => $_getBF(4);
  @$pb.TagNumber(5)
  set dryRun($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDryRun() => $_has(4);
  @$pb.TagNumber(5)
  void clearDryRun() => $_clearField(5);

  /// Refuse to execute if the plan no longer matches current state.
  @$pb.TagNumber(6)
  StorageDeletePlan get plan => $_getN(5);
  @$pb.TagNumber(6)
  set plan(StorageDeletePlan value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPlan() => $_has(5);
  @$pb.TagNumber(6)
  void clearPlan() => $_clearField(6);
  @$pb.TagNumber(6)
  StorageDeletePlan ensurePlan() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.bool get requirePlanMatch => $_getBF(6);
  @$pb.TagNumber(7)
  set requirePlanMatch($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRequirePlanMatch() => $_has(6);
  @$pb.TagNumber(7)
  void clearRequirePlanMatch() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get allowPlatformDelete => $_getBF(7);
  @$pb.TagNumber(8)
  set allowPlatformDelete($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAllowPlatformDelete() => $_has(7);
  @$pb.TagNumber(8)
  void clearAllowPlatformDelete() => $_clearField(8);
}

class StorageDeleteResult extends $pb.GeneratedMessage {
  factory StorageDeleteResult({
    $fixnum.Int64? deletedBytes,
    $core.Iterable<$core.String>? deletedModelIds,
    $core.Iterable<$core.String>? failedModelIds,
    $core.Iterable<$core.String>? warnings,
    $core.Iterable<$core.String>? skippedModelIds,
    $core.bool? dryRun,
    $core.bool? registryUpdated,
    $core.bool? filesDeleted,
    $0.SDKError? error,
  }) {
    final result = create();
    if (deletedBytes != null) result.deletedBytes = deletedBytes;
    if (deletedModelIds != null) result.deletedModelIds.addAll(deletedModelIds);
    if (failedModelIds != null) result.failedModelIds.addAll(failedModelIds);
    if (warnings != null) result.warnings.addAll(warnings);
    if (skippedModelIds != null) result.skippedModelIds.addAll(skippedModelIds);
    if (dryRun != null) result.dryRun = dryRun;
    if (registryUpdated != null) result.registryUpdated = registryUpdated;
    if (filesDeleted != null) result.filesDeleted = filesDeleted;
    if (error != null) result.error = error;
    return result;
  }

  StorageDeleteResult._();

  factory StorageDeleteResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageDeleteResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageDeleteResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(2, _omitFieldNames ? '' : 'deletedBytes')
    ..pPS(3, _omitFieldNames ? '' : 'deletedModelIds')
    ..pPS(4, _omitFieldNames ? '' : 'failedModelIds')
    ..pPS(5, _omitFieldNames ? '' : 'warnings')
    ..pPS(7, _omitFieldNames ? '' : 'skippedModelIds')
    ..aOB(8, _omitFieldNames ? '' : 'dryRun')
    ..aOB(9, _omitFieldNames ? '' : 'registryUpdated')
    ..aOB(10, _omitFieldNames ? '' : 'filesDeleted')
    ..aOM<$0.SDKError>(11, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeleteResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageDeleteResult copyWith(void Function(StorageDeleteResult) updates) =>
      super.copyWith((message) => updates(message as StorageDeleteResult))
          as StorageDeleteResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageDeleteResult create() => StorageDeleteResult._();
  @$core.override
  StorageDeleteResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageDeleteResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageDeleteResult>(create);
  static StorageDeleteResult? _defaultInstance;

  @$pb.TagNumber(2)
  $fixnum.Int64 get deletedBytes => $_getI64(0);
  @$pb.TagNumber(2)
  set deletedBytes($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(2)
  $core.bool hasDeletedBytes() => $_has(0);
  @$pb.TagNumber(2)
  void clearDeletedBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get deletedModelIds => $_getList(1);

  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get failedModelIds => $_getList(2);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get warnings => $_getList(3);

  @$pb.TagNumber(7)
  $pb.PbList<$core.String> get skippedModelIds => $_getList(4);

  @$pb.TagNumber(8)
  $core.bool get dryRun => $_getBF(5);
  @$pb.TagNumber(8)
  set dryRun($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(8)
  $core.bool hasDryRun() => $_has(5);
  @$pb.TagNumber(8)
  void clearDryRun() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get registryUpdated => $_getBF(6);
  @$pb.TagNumber(9)
  set registryUpdated($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(9)
  $core.bool hasRegistryUpdated() => $_has(6);
  @$pb.TagNumber(9)
  void clearRegistryUpdated() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get filesDeleted => $_getBF(7);
  @$pb.TagNumber(10)
  set filesDeleted($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(10)
  $core.bool hasFilesDeleted() => $_has(7);
  @$pb.TagNumber(10)
  void clearFilesDeleted() => $_clearField(10);

  @$pb.TagNumber(11)
  $0.SDKError get error => $_getN(8);
  @$pb.TagNumber(11)
  set error($0.SDKError value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(11)
  void clearError() => $_clearField(11);
  @$pb.TagNumber(11)
  $0.SDKError ensureError() => $_ensure(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
