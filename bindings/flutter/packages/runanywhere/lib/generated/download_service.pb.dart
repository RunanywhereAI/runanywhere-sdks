// This is a generated file - do not edit.
//
// Generated from download_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'download_service.pbenum.dart';
import 'errors.pb.dart' as $0;
import 'model_types.pb.dart' as $1;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'download_service.pbenum.dart';

class DownloadSubscribeRequest extends $pb.GeneratedMessage {
  factory DownloadSubscribeRequest({
    $core.String? modelId,
    $core.String? taskId,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (taskId != null) result.taskId = taskId;
    return result;
  }

  DownloadSubscribeRequest._();

  factory DownloadSubscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadSubscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadSubscribeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadSubscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadSubscribeRequest copyWith(
          void Function(DownloadSubscribeRequest) updates) =>
      super.copyWith((message) => updates(message as DownloadSubscribeRequest))
          as DownloadSubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadSubscribeRequest create() => DownloadSubscribeRequest._();
  @$core.override
  DownloadSubscribeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadSubscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadSubscribeRequest>(create);
  static DownloadSubscribeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(1);
  @$pb.TagNumber(2)
  set taskId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTaskId() => $_clearField(2);
}

class DownloadProgress extends $pb.GeneratedMessage {
  factory DownloadProgress({
    $core.String? modelId,
    $fixnum.Int64? bytesDownloaded,
    $fixnum.Int64? totalBytes,
    $core.double? stageProgress,
    $core.double? bytesPerSecond,
    $fixnum.Int64? etaSeconds,
    DownloadState? state,
    $core.int? retryAttempt,
    $core.String? taskId,
    $core.int? currentFileIndex,
    $core.int? totalFiles,
    $core.String? storageKey,
    $core.String? localPath,
    $core.double? overallProgress,
    $fixnum.Int64? startedAtUnixMs,
    $fixnum.Int64? updatedAtUnixMs,
    $core.String? currentFileName,
    $0.SDKError? error,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (bytesDownloaded != null) result.bytesDownloaded = bytesDownloaded;
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (stageProgress != null) result.stageProgress = stageProgress;
    if (bytesPerSecond != null) result.bytesPerSecond = bytesPerSecond;
    if (etaSeconds != null) result.etaSeconds = etaSeconds;
    if (state != null) result.state = state;
    if (retryAttempt != null) result.retryAttempt = retryAttempt;
    if (taskId != null) result.taskId = taskId;
    if (currentFileIndex != null) result.currentFileIndex = currentFileIndex;
    if (totalFiles != null) result.totalFiles = totalFiles;
    if (storageKey != null) result.storageKey = storageKey;
    if (localPath != null) result.localPath = localPath;
    if (overallProgress != null) result.overallProgress = overallProgress;
    if (startedAtUnixMs != null) result.startedAtUnixMs = startedAtUnixMs;
    if (updatedAtUnixMs != null) result.updatedAtUnixMs = updatedAtUnixMs;
    if (currentFileName != null) result.currentFileName = currentFileName;
    if (error != null) result.error = error;
    return result;
  }

  DownloadProgress._();

  factory DownloadProgress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadProgress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadProgress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aInt64(3, _omitFieldNames ? '' : 'bytesDownloaded')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..aD(5, _omitFieldNames ? '' : 'stageProgress',
        fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'bytesPerSecond',
        fieldType: $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'etaSeconds')
    ..aE<DownloadState>(8, _omitFieldNames ? '' : 'state',
        enumValues: DownloadState.values)
    ..aI(9, _omitFieldNames ? '' : 'retryAttempt')
    ..aOS(11, _omitFieldNames ? '' : 'taskId')
    ..aI(12, _omitFieldNames ? '' : 'currentFileIndex')
    ..aI(13, _omitFieldNames ? '' : 'totalFiles')
    ..aOS(14, _omitFieldNames ? '' : 'storageKey')
    ..aOS(15, _omitFieldNames ? '' : 'localPath')
    ..aD(16, _omitFieldNames ? '' : 'overallProgress',
        fieldType: $pb.PbFieldType.OF)
    ..aInt64(17, _omitFieldNames ? '' : 'startedAtUnixMs')
    ..aInt64(18, _omitFieldNames ? '' : 'updatedAtUnixMs')
    ..aOS(19, _omitFieldNames ? '' : 'currentFileName')
    ..aOM<$0.SDKError>(21, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadProgress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadProgress copyWith(void Function(DownloadProgress) updates) =>
      super.copyWith((message) => updates(message as DownloadProgress))
          as DownloadProgress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadProgress create() => DownloadProgress._();
  @$core.override
  DownloadProgress createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadProgress getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadProgress>(create);
  static DownloadProgress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytesDownloaded => $_getI64(1);
  @$pb.TagNumber(3)
  set bytesDownloaded($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(3)
  $core.bool hasBytesDownloaded() => $_has(1);
  @$pb.TagNumber(3)
  void clearBytesDownloaded() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(2);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(2);
  @$pb.TagNumber(4)
  void clearTotalBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get stageProgress => $_getN(3);
  @$pb.TagNumber(5)
  set stageProgress($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(5)
  $core.bool hasStageProgress() => $_has(3);
  @$pb.TagNumber(5)
  void clearStageProgress() => $_clearField(5);

  /// Bytes per second. Absent means unknown -- no sentinel that collides
  /// with a real value.
  @$pb.TagNumber(6)
  $core.double get bytesPerSecond => $_getN(4);
  @$pb.TagNumber(6)
  set bytesPerSecond($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(6)
  $core.bool hasBytesPerSecond() => $_has(4);
  @$pb.TagNumber(6)
  void clearBytesPerSecond() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get etaSeconds => $_getI64(5);
  @$pb.TagNumber(7)
  set etaSeconds($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(7)
  $core.bool hasEtaSeconds() => $_has(5);
  @$pb.TagNumber(7)
  void clearEtaSeconds() => $_clearField(7);

  /// The single phase of this transfer. `error` (21) is populated exactly
  /// when state == DOWNLOAD_STATE_FAILED and is meaningless otherwise.
  @$pb.TagNumber(8)
  DownloadState get state => $_getN(6);
  @$pb.TagNumber(8)
  set state(DownloadState value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasState() => $_has(6);
  @$pb.TagNumber(8)
  void clearState() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get retryAttempt => $_getIZ(7);
  @$pb.TagNumber(9)
  set retryAttempt($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(9)
  $core.bool hasRetryAttempt() => $_has(7);
  @$pb.TagNumber(9)
  void clearRetryAttempt() => $_clearField(9);

  @$pb.TagNumber(11)
  $core.String get taskId => $_getSZ(8);
  @$pb.TagNumber(11)
  set taskId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(11)
  $core.bool hasTaskId() => $_has(8);
  @$pb.TagNumber(11)
  void clearTaskId() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get currentFileIndex => $_getIZ(9);
  @$pb.TagNumber(12)
  set currentFileIndex($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(12)
  $core.bool hasCurrentFileIndex() => $_has(9);
  @$pb.TagNumber(12)
  void clearCurrentFileIndex() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get totalFiles => $_getIZ(10);
  @$pb.TagNumber(13)
  set totalFiles($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(13)
  $core.bool hasTotalFiles() => $_has(10);
  @$pb.TagNumber(13)
  void clearTotalFiles() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get storageKey => $_getSZ(11);
  @$pb.TagNumber(14)
  set storageKey($core.String value) => $_setString(11, value);
  @$pb.TagNumber(14)
  $core.bool hasStorageKey() => $_has(11);
  @$pb.TagNumber(14)
  void clearStorageKey() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get localPath => $_getSZ(12);
  @$pb.TagNumber(15)
  set localPath($core.String value) => $_setString(12, value);
  @$pb.TagNumber(15)
  $core.bool hasLocalPath() => $_has(12);
  @$pb.TagNumber(15)
  void clearLocalPath() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.double get overallProgress => $_getN(13);
  @$pb.TagNumber(16)
  set overallProgress($core.double value) => $_setFloat(13, value);
  @$pb.TagNumber(16)
  $core.bool hasOverallProgress() => $_has(13);
  @$pb.TagNumber(16)
  void clearOverallProgress() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get startedAtUnixMs => $_getI64(14);
  @$pb.TagNumber(17)
  set startedAtUnixMs($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(17)
  $core.bool hasStartedAtUnixMs() => $_has(14);
  @$pb.TagNumber(17)
  void clearStartedAtUnixMs() => $_clearField(17);

  @$pb.TagNumber(18)
  $fixnum.Int64 get updatedAtUnixMs => $_getI64(15);
  @$pb.TagNumber(18)
  set updatedAtUnixMs($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(18)
  $core.bool hasUpdatedAtUnixMs() => $_has(15);
  @$pb.TagNumber(18)
  void clearUpdatedAtUnixMs() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get currentFileName => $_getSZ(16);
  @$pb.TagNumber(19)
  set currentFileName($core.String value) => $_setString(16, value);
  @$pb.TagNumber(19)
  $core.bool hasCurrentFileName() => $_has(16);
  @$pb.TagNumber(19)
  void clearCurrentFileName() => $_clearField(19);

  @$pb.TagNumber(21)
  $0.SDKError get error => $_getN(17);
  @$pb.TagNumber(21)
  set error($0.SDKError value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasError() => $_has(17);
  @$pb.TagNumber(21)
  void clearError() => $_clearField(21);
  @$pb.TagNumber(21)
  $0.SDKError ensureError() => $_ensure(17);
}

class DownloadPlanRequest extends $pb.GeneratedMessage {
  factory DownloadPlanRequest({
    $core.String? modelId,
    $1.ModelInfo? model,
    $fixnum.Int64? availableStorageBytes,
    $core.bool? allowMeteredNetwork,
    $core.String? storageNamespace,
    $core.bool? validateExistingBytes,
    $core.bool? skipChecksumVerification,
    $fixnum.Int64? requiredFreeBytesAfterDownload,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (model != null) result.model = model;
    if (availableStorageBytes != null)
      result.availableStorageBytes = availableStorageBytes;
    if (allowMeteredNetwork != null)
      result.allowMeteredNetwork = allowMeteredNetwork;
    if (storageNamespace != null) result.storageNamespace = storageNamespace;
    if (validateExistingBytes != null)
      result.validateExistingBytes = validateExistingBytes;
    if (skipChecksumVerification != null)
      result.skipChecksumVerification = skipChecksumVerification;
    if (requiredFreeBytesAfterDownload != null)
      result.requiredFreeBytesAfterDownload = requiredFreeBytesAfterDownload;
    return result;
  }

  DownloadPlanRequest._();

  factory DownloadPlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadPlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadPlanRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOM<$1.ModelInfo>(2, _omitFieldNames ? '' : 'model',
        subBuilder: $1.ModelInfo.create)
    ..aInt64(4, _omitFieldNames ? '' : 'availableStorageBytes')
    ..aOB(5, _omitFieldNames ? '' : 'allowMeteredNetwork')
    ..aOS(6, _omitFieldNames ? '' : 'storageNamespace')
    ..aOB(7, _omitFieldNames ? '' : 'validateExistingBytes')
    ..aOB(8, _omitFieldNames ? '' : 'skipChecksumVerification')
    ..aInt64(9, _omitFieldNames ? '' : 'requiredFreeBytesAfterDownload')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadPlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadPlanRequest copyWith(void Function(DownloadPlanRequest) updates) =>
      super.copyWith((message) => updates(message as DownloadPlanRequest))
          as DownloadPlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadPlanRequest create() => DownloadPlanRequest._();
  @$core.override
  DownloadPlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadPlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadPlanRequest>(create);
  static DownloadPlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $1.ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model($1.ModelInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => $_clearField(2);
  @$pb.TagNumber(2)
  $1.ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(4)
  $fixnum.Int64 get availableStorageBytes => $_getI64(2);
  @$pb.TagNumber(4)
  set availableStorageBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasAvailableStorageBytes() => $_has(2);
  @$pb.TagNumber(4)
  void clearAvailableStorageBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get allowMeteredNetwork => $_getBF(3);
  @$pb.TagNumber(5)
  set allowMeteredNetwork($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(5)
  $core.bool hasAllowMeteredNetwork() => $_has(3);
  @$pb.TagNumber(5)
  void clearAllowMeteredNetwork() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get storageNamespace => $_getSZ(4);
  @$pb.TagNumber(6)
  set storageNamespace($core.String value) => $_setString(4, value);
  @$pb.TagNumber(6)
  $core.bool hasStorageNamespace() => $_has(4);
  @$pb.TagNumber(6)
  void clearStorageNamespace() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get validateExistingBytes => $_getBF(5);
  @$pb.TagNumber(7)
  set validateExistingBytes($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(7)
  $core.bool hasValidateExistingBytes() => $_has(5);
  @$pb.TagNumber(7)
  void clearValidateExistingBytes() => $_clearField(7);

  /// Checksums are verified whenever the catalog has one; set this only to
  /// opt OUT.
  @$pb.TagNumber(8)
  $core.bool get skipChecksumVerification => $_getBF(6);
  @$pb.TagNumber(8)
  set skipChecksumVerification($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(8)
  $core.bool hasSkipChecksumVerification() => $_has(6);
  @$pb.TagNumber(8)
  void clearSkipChecksumVerification() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get requiredFreeBytesAfterDownload => $_getI64(7);
  @$pb.TagNumber(9)
  set requiredFreeBytesAfterDownload($fixnum.Int64 value) =>
      $_setInt64(7, value);
  @$pb.TagNumber(9)
  $core.bool hasRequiredFreeBytesAfterDownload() => $_has(7);
  @$pb.TagNumber(9)
  void clearRequiredFreeBytesAfterDownload() => $_clearField(9);
}

class DownloadFilePlan extends $pb.GeneratedMessage {
  factory DownloadFilePlan({
    $1.ModelFileDescriptor? file,
    $core.String? storageKey,
    $core.String? destinationPath,
    $fixnum.Int64? expectedBytes,
    $core.bool? requiresExtraction,
    $core.String? checksumSha256,
    $core.bool? isResumeCandidate,
  }) {
    final result = create();
    if (file != null) result.file = file;
    if (storageKey != null) result.storageKey = storageKey;
    if (destinationPath != null) result.destinationPath = destinationPath;
    if (expectedBytes != null) result.expectedBytes = expectedBytes;
    if (requiresExtraction != null)
      result.requiresExtraction = requiresExtraction;
    if (checksumSha256 != null) result.checksumSha256 = checksumSha256;
    if (isResumeCandidate != null) result.isResumeCandidate = isResumeCandidate;
    return result;
  }

  DownloadFilePlan._();

  factory DownloadFilePlan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadFilePlan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadFilePlan',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<$1.ModelFileDescriptor>(1, _omitFieldNames ? '' : 'file',
        subBuilder: $1.ModelFileDescriptor.create)
    ..aOS(2, _omitFieldNames ? '' : 'storageKey')
    ..aOS(3, _omitFieldNames ? '' : 'destinationPath')
    ..aInt64(4, _omitFieldNames ? '' : 'expectedBytes')
    ..aOB(5, _omitFieldNames ? '' : 'requiresExtraction')
    ..aOS(6, _omitFieldNames ? '' : 'checksumSha256')
    ..aOB(7, _omitFieldNames ? '' : 'isResumeCandidate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadFilePlan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadFilePlan copyWith(void Function(DownloadFilePlan) updates) =>
      super.copyWith((message) => updates(message as DownloadFilePlan))
          as DownloadFilePlan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadFilePlan create() => DownloadFilePlan._();
  @$core.override
  DownloadFilePlan createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadFilePlan getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadFilePlan>(create);
  static DownloadFilePlan? _defaultInstance;

  @$pb.TagNumber(1)
  $1.ModelFileDescriptor get file => $_getN(0);
  @$pb.TagNumber(1)
  set file($1.ModelFileDescriptor value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFile() => $_has(0);
  @$pb.TagNumber(1)
  void clearFile() => $_clearField(1);
  @$pb.TagNumber(1)
  $1.ModelFileDescriptor ensureFile() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get storageKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set storageKey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStorageKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearStorageKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get destinationPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set destinationPath($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDestinationPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearDestinationPath() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expectedBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set expectedBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpectedBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get requiresExtraction => $_getBF(4);
  @$pb.TagNumber(5)
  set requiresExtraction($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRequiresExtraction() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequiresExtraction() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get checksumSha256 => $_getSZ(5);
  @$pb.TagNumber(6)
  set checksumSha256($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasChecksumSha256() => $_has(5);
  @$pb.TagNumber(6)
  void clearChecksumSha256() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isResumeCandidate => $_getBF(6);
  @$pb.TagNumber(7)
  set isResumeCandidate($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsResumeCandidate() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsResumeCandidate() => $_clearField(7);
}

class DownloadPlanResult extends $pb.GeneratedMessage {
  factory DownloadPlanResult({
    $core.bool? canStart,
    $core.String? modelId,
    $core.Iterable<DownloadFilePlan>? files,
    $fixnum.Int64? totalBytes,
    $core.bool? requiresExtraction,
    $core.bool? canResume,
    $fixnum.Int64? resumeFromBytes,
    $core.Iterable<$core.String>? warnings,
    $core.String? storageNamespace,
    $fixnum.Int64? requiredFreeBytesAfterDownload,
    DownloadFailureReason? failureReason,
    $0.SDKError? error,
  }) {
    final result = create();
    if (canStart != null) result.canStart = canStart;
    if (modelId != null) result.modelId = modelId;
    if (files != null) result.files.addAll(files);
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (requiresExtraction != null)
      result.requiresExtraction = requiresExtraction;
    if (canResume != null) result.canResume = canResume;
    if (resumeFromBytes != null) result.resumeFromBytes = resumeFromBytes;
    if (warnings != null) result.warnings.addAll(warnings);
    if (storageNamespace != null) result.storageNamespace = storageNamespace;
    if (requiredFreeBytesAfterDownload != null)
      result.requiredFreeBytesAfterDownload = requiredFreeBytesAfterDownload;
    if (failureReason != null) result.failureReason = failureReason;
    if (error != null) result.error = error;
    return result;
  }

  DownloadPlanResult._();

  factory DownloadPlanResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadPlanResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadPlanResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'canStart')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..pPM<DownloadFilePlan>(3, _omitFieldNames ? '' : 'files',
        subBuilder: DownloadFilePlan.create)
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..aOB(5, _omitFieldNames ? '' : 'requiresExtraction')
    ..aOB(6, _omitFieldNames ? '' : 'canResume')
    ..aInt64(7, _omitFieldNames ? '' : 'resumeFromBytes')
    ..pPS(8, _omitFieldNames ? '' : 'warnings')
    ..aOS(10, _omitFieldNames ? '' : 'storageNamespace')
    ..aInt64(12, _omitFieldNames ? '' : 'requiredFreeBytesAfterDownload')
    ..aE<DownloadFailureReason>(13, _omitFieldNames ? '' : 'failureReason',
        enumValues: DownloadFailureReason.values)
    ..aOM<$0.SDKError>(14, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadPlanResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadPlanResult copyWith(void Function(DownloadPlanResult) updates) =>
      super.copyWith((message) => updates(message as DownloadPlanResult))
          as DownloadPlanResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadPlanResult create() => DownloadPlanResult._();
  @$core.override
  DownloadPlanResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadPlanResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadPlanResult>(create);
  static DownloadPlanResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get canStart => $_getBF(0);
  @$pb.TagNumber(1)
  set canStart($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCanStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearCanStart() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<DownloadFilePlan> get files => $_getList(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get requiresExtraction => $_getBF(4);
  @$pb.TagNumber(5)
  set requiresExtraction($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRequiresExtraction() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequiresExtraction() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get canResume => $_getBF(5);
  @$pb.TagNumber(6)
  set canResume($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCanResume() => $_has(5);
  @$pb.TagNumber(6)
  void clearCanResume() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get resumeFromBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set resumeFromBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasResumeFromBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearResumeFromBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<$core.String> get warnings => $_getList(7);

  @$pb.TagNumber(10)
  $core.String get storageNamespace => $_getSZ(8);
  @$pb.TagNumber(10)
  set storageNamespace($core.String value) => $_setString(8, value);
  @$pb.TagNumber(10)
  $core.bool hasStorageNamespace() => $_has(8);
  @$pb.TagNumber(10)
  void clearStorageNamespace() => $_clearField(10);

  @$pb.TagNumber(12)
  $fixnum.Int64 get requiredFreeBytesAfterDownload => $_getI64(9);
  @$pb.TagNumber(12)
  set requiredFreeBytesAfterDownload($fixnum.Int64 value) =>
      $_setInt64(9, value);
  @$pb.TagNumber(12)
  $core.bool hasRequiredFreeBytesAfterDownload() => $_has(9);
  @$pb.TagNumber(12)
  void clearRequiredFreeBytesAfterDownload() => $_clearField(12);

  @$pb.TagNumber(13)
  DownloadFailureReason get failureReason => $_getN(10);
  @$pb.TagNumber(13)
  set failureReason(DownloadFailureReason value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasFailureReason() => $_has(10);
  @$pb.TagNumber(13)
  void clearFailureReason() => $_clearField(13);

  @$pb.TagNumber(14)
  $0.SDKError get error => $_getN(11);
  @$pb.TagNumber(14)
  set error($0.SDKError value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasError() => $_has(11);
  @$pb.TagNumber(14)
  void clearError() => $_clearField(14);
  @$pb.TagNumber(14)
  $0.SDKError ensureError() => $_ensure(11);
}

class DownloadStartRequest extends $pb.GeneratedMessage {
  factory DownloadStartRequest({
    $core.String? modelId,
    DownloadPlanResult? plan,
    $core.bool? skipRegistryUpdate,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (plan != null) result.plan = plan;
    if (skipRegistryUpdate != null)
      result.skipRegistryUpdate = skipRegistryUpdate;
    return result;
  }

  DownloadStartRequest._();

  factory DownloadStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOM<DownloadPlanResult>(2, _omitFieldNames ? '' : 'plan',
        subBuilder: DownloadPlanResult.create)
    ..aOB(5, _omitFieldNames ? '' : 'skipRegistryUpdate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadStartRequest copyWith(void Function(DownloadStartRequest) updates) =>
      super.copyWith((message) => updates(message as DownloadStartRequest))
          as DownloadStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadStartRequest create() => DownloadStartRequest._();
  @$core.override
  DownloadStartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadStartRequest>(create);
  static DownloadStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => $_clearField(1);

  /// Optional. ABSENT (the common path) = plan internally and start, one
  /// call. PRESENT = execute this exact previously-approved plan, for the
  /// flow that showed the user a size and a metered-network warning first.
  @$pb.TagNumber(2)
  DownloadPlanResult get plan => $_getN(1);
  @$pb.TagNumber(2)
  set plan(DownloadPlanResult value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPlan() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlan() => $_clearField(2);
  @$pb.TagNumber(2)
  DownloadPlanResult ensurePlan() => $_ensure(1);

  /// The registry is updated on completion; set this only to opt OUT
  /// (staging flows).
  @$pb.TagNumber(5)
  $core.bool get skipRegistryUpdate => $_getBF(2);
  @$pb.TagNumber(5)
  set skipRegistryUpdate($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(5)
  $core.bool hasSkipRegistryUpdate() => $_has(2);
  @$pb.TagNumber(5)
  void clearSkipRegistryUpdate() => $_clearField(5);
}

class DownloadStartResult extends $pb.GeneratedMessage {
  factory DownloadStartResult({
    $core.bool? accepted,
    $core.String? taskId,
    $core.String? modelId,
    DownloadProgress? initialProgress,
    DownloadFailureReason? failureReason,
    $0.SDKError? error,
    DownloadPlanResult? plan,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (initialProgress != null) result.initialProgress = initialProgress;
    if (failureReason != null) result.failureReason = failureReason;
    if (error != null) result.error = error;
    if (plan != null) result.plan = plan;
    return result;
  }

  DownloadStartResult._();

  factory DownloadStartResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadStartResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadStartResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aOM<DownloadProgress>(4, _omitFieldNames ? '' : 'initialProgress',
        subBuilder: DownloadProgress.create)
    ..aE<DownloadFailureReason>(7, _omitFieldNames ? '' : 'failureReason',
        enumValues: DownloadFailureReason.values)
    ..aOM<$0.SDKError>(8, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..aOM<DownloadPlanResult>(9, _omitFieldNames ? '' : 'plan',
        subBuilder: DownloadPlanResult.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadStartResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadStartResult copyWith(void Function(DownloadStartResult) updates) =>
      super.copyWith((message) => updates(message as DownloadStartResult))
          as DownloadStartResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadStartResult create() => DownloadStartResult._();
  @$core.override
  DownloadStartResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadStartResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadStartResult>(create);
  static DownloadStartResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(1);
  @$pb.TagNumber(2)
  set taskId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTaskId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  DownloadProgress get initialProgress => $_getN(3);
  @$pb.TagNumber(4)
  set initialProgress(DownloadProgress value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasInitialProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearInitialProgress() => $_clearField(4);
  @$pb.TagNumber(4)
  DownloadProgress ensureInitialProgress() => $_ensure(3);

  @$pb.TagNumber(7)
  DownloadFailureReason get failureReason => $_getN(4);
  @$pb.TagNumber(7)
  set failureReason(DownloadFailureReason value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFailureReason() => $_has(4);
  @$pb.TagNumber(7)
  void clearFailureReason() => $_clearField(7);

  @$pb.TagNumber(8)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(8)
  set error($0.SDKError value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(8)
  void clearError() => $_clearField(8);
  @$pb.TagNumber(8)
  $0.SDKError ensureError() => $_ensure(5);

  /// The plan that was executed, supplied or computed, so a one-call caller
  /// still gets the byte numbers.
  @$pb.TagNumber(9)
  DownloadPlanResult get plan => $_getN(6);
  @$pb.TagNumber(9)
  set plan(DownloadPlanResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasPlan() => $_has(6);
  @$pb.TagNumber(9)
  void clearPlan() => $_clearField(9);
  @$pb.TagNumber(9)
  DownloadPlanResult ensurePlan() => $_ensure(6);
}

class DownloadCancelRequest extends $pb.GeneratedMessage {
  factory DownloadCancelRequest({
    $core.String? taskId,
    $core.String? modelId,
    $core.bool? deletePartialBytes,
  }) {
    final result = create();
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (deletePartialBytes != null)
      result.deletePartialBytes = deletePartialBytes;
    return result;
  }

  DownloadCancelRequest._();

  factory DownloadCancelRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadCancelRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadCancelRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'taskId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOB(3, _omitFieldNames ? '' : 'deletePartialBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadCancelRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadCancelRequest copyWith(
          void Function(DownloadCancelRequest) updates) =>
      super.copyWith((message) => updates(message as DownloadCancelRequest))
          as DownloadCancelRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadCancelRequest create() => DownloadCancelRequest._();
  @$core.override
  DownloadCancelRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadCancelRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadCancelRequest>(create);
  static DownloadCancelRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get taskId => $_getSZ(0);
  @$pb.TagNumber(1)
  set taskId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTaskId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTaskId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get deletePartialBytes => $_getBF(2);
  @$pb.TagNumber(3)
  set deletePartialBytes($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDeletePartialBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeletePartialBytes() => $_clearField(3);
}

class DownloadCancelResult extends $pb.GeneratedMessage {
  factory DownloadCancelResult({
    $core.String? taskId,
    $core.String? modelId,
    $fixnum.Int64? partialBytesDeleted,
    $core.bool? wasRunning,
    $core.bool? partialBytesPreserved,
    $0.SDKError? error,
  }) {
    final result = create();
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (partialBytesDeleted != null)
      result.partialBytesDeleted = partialBytesDeleted;
    if (wasRunning != null) result.wasRunning = wasRunning;
    if (partialBytesPreserved != null)
      result.partialBytesPreserved = partialBytesPreserved;
    if (error != null) result.error = error;
    return result;
  }

  DownloadCancelResult._();

  factory DownloadCancelResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadCancelResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadCancelResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aInt64(4, _omitFieldNames ? '' : 'partialBytesDeleted')
    ..aOB(6, _omitFieldNames ? '' : 'wasRunning')
    ..aOB(7, _omitFieldNames ? '' : 'partialBytesPreserved')
    ..aOM<$0.SDKError>(9, _omitFieldNames ? '' : 'error',
        subBuilder: $0.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadCancelResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadCancelResult copyWith(void Function(DownloadCancelResult) updates) =>
      super.copyWith((message) => updates(message as DownloadCancelResult))
          as DownloadCancelResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadCancelResult create() => DownloadCancelResult._();
  @$core.override
  DownloadCancelResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadCancelResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadCancelResult>(create);
  static DownloadCancelResult? _defaultInstance;

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(0);
  @$pb.TagNumber(2)
  set taskId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(0);
  @$pb.TagNumber(2)
  void clearTaskId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get partialBytesDeleted => $_getI64(2);
  @$pb.TagNumber(4)
  set partialBytesDeleted($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(4)
  $core.bool hasPartialBytesDeleted() => $_has(2);
  @$pb.TagNumber(4)
  void clearPartialBytesDeleted() => $_clearField(4);

  @$pb.TagNumber(6)
  $core.bool get wasRunning => $_getBF(3);
  @$pb.TagNumber(6)
  set wasRunning($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(6)
  $core.bool hasWasRunning() => $_has(3);
  @$pb.TagNumber(6)
  void clearWasRunning() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get partialBytesPreserved => $_getBF(4);
  @$pb.TagNumber(7)
  set partialBytesPreserved($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(7)
  $core.bool hasPartialBytesPreserved() => $_has(4);
  @$pb.TagNumber(7)
  void clearPartialBytesPreserved() => $_clearField(7);

  @$pb.TagNumber(9)
  $0.SDKError get error => $_getN(5);
  @$pb.TagNumber(9)
  set error($0.SDKError value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.SDKError ensureError() => $_ensure(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
