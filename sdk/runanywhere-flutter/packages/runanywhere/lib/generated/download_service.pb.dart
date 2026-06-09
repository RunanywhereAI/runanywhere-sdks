// This is a generated file - do not edit.
//
// Generated from download_service.proto.

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

import 'download_service.pbenum.dart';
import 'model_types.pb.dart' as $0;

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
    DownloadStage? stage,
    $fixnum.Int64? bytesDownloaded,
    $fixnum.Int64? totalBytes,
    $core.double? stageProgress,
    $core.double? overallSpeedBps,
    $fixnum.Int64? etaSeconds,
    DownloadState? state,
    $core.int? retryAttempt,
    $core.String? errorMessage,
    $core.String? taskId,
    $core.int? currentFileIndex,
    $core.int? totalFiles,
    $core.String? storageKey,
    $core.String? localPath,
    $core.double? overallProgress,
    $fixnum.Int64? startedAtUnixMs,
    $fixnum.Int64? updatedAtUnixMs,
    $core.String? currentFileName,
    $core.String? resumeToken,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (stage != null) result.stage = stage;
    if (bytesDownloaded != null) result.bytesDownloaded = bytesDownloaded;
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (stageProgress != null) result.stageProgress = stageProgress;
    if (overallSpeedBps != null) result.overallSpeedBps = overallSpeedBps;
    if (etaSeconds != null) result.etaSeconds = etaSeconds;
    if (state != null) result.state = state;
    if (retryAttempt != null) result.retryAttempt = retryAttempt;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (taskId != null) result.taskId = taskId;
    if (currentFileIndex != null) result.currentFileIndex = currentFileIndex;
    if (totalFiles != null) result.totalFiles = totalFiles;
    if (storageKey != null) result.storageKey = storageKey;
    if (localPath != null) result.localPath = localPath;
    if (overallProgress != null) result.overallProgress = overallProgress;
    if (startedAtUnixMs != null) result.startedAtUnixMs = startedAtUnixMs;
    if (updatedAtUnixMs != null) result.updatedAtUnixMs = updatedAtUnixMs;
    if (currentFileName != null) result.currentFileName = currentFileName;
    if (resumeToken != null) result.resumeToken = resumeToken;
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
    ..aE<DownloadStage>(2, _omitFieldNames ? '' : 'stage',
        enumValues: DownloadStage.values)
    ..aInt64(3, _omitFieldNames ? '' : 'bytesDownloaded')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..aD(5, _omitFieldNames ? '' : 'stageProgress',
        fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'overallSpeedBps',
        fieldType: $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'etaSeconds')
    ..aE<DownloadState>(8, _omitFieldNames ? '' : 'state',
        enumValues: DownloadState.values)
    ..aI(9, _omitFieldNames ? '' : 'retryAttempt')
    ..aOS(10, _omitFieldNames ? '' : 'errorMessage')
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
    ..aOS(20, _omitFieldNames ? '' : 'resumeToken')
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

  @$pb.TagNumber(2)
  DownloadStage get stage => $_getN(1);
  @$pb.TagNumber(2)
  set stage(DownloadStage value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStage() => $_has(1);
  @$pb.TagNumber(2)
  void clearStage() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytesDownloaded => $_getI64(2);
  @$pb.TagNumber(3)
  set bytesDownloaded($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBytesDownloaded() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytesDownloaded() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get stageProgress => $_getN(4);
  @$pb.TagNumber(5)
  set stageProgress($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStageProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearStageProgress() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get overallSpeedBps => $_getN(5);
  @$pb.TagNumber(6)
  set overallSpeedBps($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOverallSpeedBps() => $_has(5);
  @$pb.TagNumber(6)
  void clearOverallSpeedBps() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get etaSeconds => $_getI64(6);
  @$pb.TagNumber(7)
  set etaSeconds($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEtaSeconds() => $_has(6);
  @$pb.TagNumber(7)
  void clearEtaSeconds() => $_clearField(7);

  @$pb.TagNumber(8)
  DownloadState get state => $_getN(7);
  @$pb.TagNumber(8)
  set state(DownloadState value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasState() => $_has(7);
  @$pb.TagNumber(8)
  void clearState() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get retryAttempt => $_getIZ(8);
  @$pb.TagNumber(9)
  set retryAttempt($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRetryAttempt() => $_has(8);
  @$pb.TagNumber(9)
  void clearRetryAttempt() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get errorMessage => $_getSZ(9);
  @$pb.TagNumber(10)
  set errorMessage($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorMessage() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorMessage() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get taskId => $_getSZ(10);
  @$pb.TagNumber(11)
  set taskId($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTaskId() => $_has(10);
  @$pb.TagNumber(11)
  void clearTaskId() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get currentFileIndex => $_getIZ(11);
  @$pb.TagNumber(12)
  set currentFileIndex($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasCurrentFileIndex() => $_has(11);
  @$pb.TagNumber(12)
  void clearCurrentFileIndex() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get totalFiles => $_getIZ(12);
  @$pb.TagNumber(13)
  set totalFiles($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasTotalFiles() => $_has(12);
  @$pb.TagNumber(13)
  void clearTotalFiles() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get storageKey => $_getSZ(13);
  @$pb.TagNumber(14)
  set storageKey($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasStorageKey() => $_has(13);
  @$pb.TagNumber(14)
  void clearStorageKey() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get localPath => $_getSZ(14);
  @$pb.TagNumber(15)
  set localPath($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasLocalPath() => $_has(14);
  @$pb.TagNumber(15)
  void clearLocalPath() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.double get overallProgress => $_getN(15);
  @$pb.TagNumber(16)
  set overallProgress($core.double value) => $_setFloat(15, value);
  @$pb.TagNumber(16)
  $core.bool hasOverallProgress() => $_has(15);
  @$pb.TagNumber(16)
  void clearOverallProgress() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get startedAtUnixMs => $_getI64(16);
  @$pb.TagNumber(17)
  set startedAtUnixMs($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasStartedAtUnixMs() => $_has(16);
  @$pb.TagNumber(17)
  void clearStartedAtUnixMs() => $_clearField(17);

  @$pb.TagNumber(18)
  $fixnum.Int64 get updatedAtUnixMs => $_getI64(17);
  @$pb.TagNumber(18)
  set updatedAtUnixMs($fixnum.Int64 value) => $_setInt64(17, value);
  @$pb.TagNumber(18)
  $core.bool hasUpdatedAtUnixMs() => $_has(17);
  @$pb.TagNumber(18)
  void clearUpdatedAtUnixMs() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get currentFileName => $_getSZ(18);
  @$pb.TagNumber(19)
  set currentFileName($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasCurrentFileName() => $_has(18);
  @$pb.TagNumber(19)
  void clearCurrentFileName() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.String get resumeToken => $_getSZ(19);
  @$pb.TagNumber(20)
  set resumeToken($core.String value) => $_setString(19, value);
  @$pb.TagNumber(20)
  $core.bool hasResumeToken() => $_has(19);
  @$pb.TagNumber(20)
  void clearResumeToken() => $_clearField(20);
}

class DownloadPlanRequest extends $pb.GeneratedMessage {
  factory DownloadPlanRequest({
    $core.String? modelId,
    $0.ModelInfo? model,
    $core.bool? resumeExisting,
    $fixnum.Int64? availableStorageBytes,
    $core.bool? allowMeteredNetwork,
    $core.String? storageNamespace,
    $core.bool? validateExistingBytes,
    $core.bool? verifyChecksums,
    $fixnum.Int64? requiredFreeBytesAfterDownload,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (model != null) result.model = model;
    if (resumeExisting != null) result.resumeExisting = resumeExisting;
    if (availableStorageBytes != null)
      result.availableStorageBytes = availableStorageBytes;
    if (allowMeteredNetwork != null)
      result.allowMeteredNetwork = allowMeteredNetwork;
    if (storageNamespace != null) result.storageNamespace = storageNamespace;
    if (validateExistingBytes != null)
      result.validateExistingBytes = validateExistingBytes;
    if (verifyChecksums != null) result.verifyChecksums = verifyChecksums;
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
    ..aOM<$0.ModelInfo>(2, _omitFieldNames ? '' : 'model',
        subBuilder: $0.ModelInfo.create)
    ..aOB(3, _omitFieldNames ? '' : 'resumeExisting')
    ..aInt64(4, _omitFieldNames ? '' : 'availableStorageBytes')
    ..aOB(5, _omitFieldNames ? '' : 'allowMeteredNetwork')
    ..aOS(6, _omitFieldNames ? '' : 'storageNamespace')
    ..aOB(7, _omitFieldNames ? '' : 'validateExistingBytes')
    ..aOB(8, _omitFieldNames ? '' : 'verifyChecksums')
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
  $0.ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model($0.ModelInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get resumeExisting => $_getBF(2);
  @$pb.TagNumber(3)
  set resumeExisting($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResumeExisting() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeExisting() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get availableStorageBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set availableStorageBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAvailableStorageBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvailableStorageBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get allowMeteredNetwork => $_getBF(4);
  @$pb.TagNumber(5)
  set allowMeteredNetwork($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAllowMeteredNetwork() => $_has(4);
  @$pb.TagNumber(5)
  void clearAllowMeteredNetwork() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get storageNamespace => $_getSZ(5);
  @$pb.TagNumber(6)
  set storageNamespace($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStorageNamespace() => $_has(5);
  @$pb.TagNumber(6)
  void clearStorageNamespace() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get validateExistingBytes => $_getBF(6);
  @$pb.TagNumber(7)
  set validateExistingBytes($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasValidateExistingBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearValidateExistingBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get verifyChecksums => $_getBF(7);
  @$pb.TagNumber(8)
  set verifyChecksums($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasVerifyChecksums() => $_has(7);
  @$pb.TagNumber(8)
  void clearVerifyChecksums() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get requiredFreeBytesAfterDownload => $_getI64(8);
  @$pb.TagNumber(9)
  set requiredFreeBytesAfterDownload($fixnum.Int64 value) =>
      $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRequiredFreeBytesAfterDownload() => $_has(8);
  @$pb.TagNumber(9)
  void clearRequiredFreeBytesAfterDownload() => $_clearField(9);
}

class DownloadFilePlan extends $pb.GeneratedMessage {
  factory DownloadFilePlan({
    $0.ModelFileDescriptor? file,
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
    ..aOM<$0.ModelFileDescriptor>(1, _omitFieldNames ? '' : 'file',
        subBuilder: $0.ModelFileDescriptor.create)
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
  $0.ModelFileDescriptor get file => $_getN(0);
  @$pb.TagNumber(1)
  set file($0.ModelFileDescriptor value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFile() => $_has(0);
  @$pb.TagNumber(1)
  void clearFile() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.ModelFileDescriptor ensureFile() => $_ensure(0);

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
    $core.String? errorMessage,
    $core.String? storageNamespace,
    $core.String? resumeToken,
    $fixnum.Int64? requiredFreeBytesAfterDownload,
    DownloadFailureReason? failureReason,
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
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (storageNamespace != null) result.storageNamespace = storageNamespace;
    if (resumeToken != null) result.resumeToken = resumeToken;
    if (requiredFreeBytesAfterDownload != null)
      result.requiredFreeBytesAfterDownload = requiredFreeBytesAfterDownload;
    if (failureReason != null) result.failureReason = failureReason;
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
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(10, _omitFieldNames ? '' : 'storageNamespace')
    ..aOS(11, _omitFieldNames ? '' : 'resumeToken')
    ..aInt64(12, _omitFieldNames ? '' : 'requiredFreeBytesAfterDownload')
    ..aE<DownloadFailureReason>(13, _omitFieldNames ? '' : 'failureReason',
        enumValues: DownloadFailureReason.values)
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

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get storageNamespace => $_getSZ(9);
  @$pb.TagNumber(10)
  set storageNamespace($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasStorageNamespace() => $_has(9);
  @$pb.TagNumber(10)
  void clearStorageNamespace() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get resumeToken => $_getSZ(10);
  @$pb.TagNumber(11)
  set resumeToken($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasResumeToken() => $_has(10);
  @$pb.TagNumber(11)
  void clearResumeToken() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get requiredFreeBytesAfterDownload => $_getI64(11);
  @$pb.TagNumber(12)
  set requiredFreeBytesAfterDownload($fixnum.Int64 value) =>
      $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasRequiredFreeBytesAfterDownload() => $_has(11);
  @$pb.TagNumber(12)
  void clearRequiredFreeBytesAfterDownload() => $_clearField(12);

  @$pb.TagNumber(13)
  DownloadFailureReason get failureReason => $_getN(12);
  @$pb.TagNumber(13)
  set failureReason(DownloadFailureReason value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasFailureReason() => $_has(12);
  @$pb.TagNumber(13)
  void clearFailureReason() => $_clearField(13);
}

class DownloadStartRequest extends $pb.GeneratedMessage {
  factory DownloadStartRequest({
    $core.String? modelId,
    DownloadPlanResult? plan,
    $core.bool? resume,
    $core.String? resumeToken,
    $core.bool? updateRegistryOnCompletion,
  }) {
    final result = create();
    if (modelId != null) result.modelId = modelId;
    if (plan != null) result.plan = plan;
    if (resume != null) result.resume = resume;
    if (resumeToken != null) result.resumeToken = resumeToken;
    if (updateRegistryOnCompletion != null)
      result.updateRegistryOnCompletion = updateRegistryOnCompletion;
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
    ..aOB(3, _omitFieldNames ? '' : 'resume')
    ..aOS(4, _omitFieldNames ? '' : 'resumeToken')
    ..aOB(5, _omitFieldNames ? '' : 'updateRegistryOnCompletion')
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

  @$pb.TagNumber(3)
  $core.bool get resume => $_getBF(2);
  @$pb.TagNumber(3)
  set resume($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResume() => $_has(2);
  @$pb.TagNumber(3)
  void clearResume() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get resumeToken => $_getSZ(3);
  @$pb.TagNumber(4)
  set resumeToken($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResumeToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearResumeToken() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get updateRegistryOnCompletion => $_getBF(4);
  @$pb.TagNumber(5)
  set updateRegistryOnCompletion($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUpdateRegistryOnCompletion() => $_has(4);
  @$pb.TagNumber(5)
  void clearUpdateRegistryOnCompletion() => $_clearField(5);
}

class DownloadStartResult extends $pb.GeneratedMessage {
  factory DownloadStartResult({
    $core.bool? accepted,
    $core.String? taskId,
    $core.String? modelId,
    DownloadProgress? initialProgress,
    $core.String? errorMessage,
    $core.String? resumeToken,
    DownloadFailureReason? failureReason,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (initialProgress != null) result.initialProgress = initialProgress;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (resumeToken != null) result.resumeToken = resumeToken;
    if (failureReason != null) result.failureReason = failureReason;
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
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(6, _omitFieldNames ? '' : 'resumeToken')
    ..aE<DownloadFailureReason>(7, _omitFieldNames ? '' : 'failureReason',
        enumValues: DownloadFailureReason.values)
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

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get resumeToken => $_getSZ(5);
  @$pb.TagNumber(6)
  set resumeToken($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasResumeToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearResumeToken() => $_clearField(6);

  @$pb.TagNumber(7)
  DownloadFailureReason get failureReason => $_getN(6);
  @$pb.TagNumber(7)
  set failureReason(DownloadFailureReason value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFailureReason() => $_has(6);
  @$pb.TagNumber(7)
  void clearFailureReason() => $_clearField(7);
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
    $core.bool? success,
    $core.String? taskId,
    $core.String? modelId,
    $fixnum.Int64? partialBytesDeleted,
    $core.String? errorMessage,
    $core.bool? wasRunning,
    $core.bool? partialBytesPreserved,
    $core.String? resumeToken,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (partialBytesDeleted != null)
      result.partialBytesDeleted = partialBytesDeleted;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (wasRunning != null) result.wasRunning = wasRunning;
    if (partialBytesPreserved != null)
      result.partialBytesPreserved = partialBytesPreserved;
    if (resumeToken != null) result.resumeToken = resumeToken;
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
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aInt64(4, _omitFieldNames ? '' : 'partialBytesDeleted')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aOB(6, _omitFieldNames ? '' : 'wasRunning')
    ..aOB(7, _omitFieldNames ? '' : 'partialBytesPreserved')
    ..aOS(8, _omitFieldNames ? '' : 'resumeToken')
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

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

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
  $fixnum.Int64 get partialBytesDeleted => $_getI64(3);
  @$pb.TagNumber(4)
  set partialBytesDeleted($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPartialBytesDeleted() => $_has(3);
  @$pb.TagNumber(4)
  void clearPartialBytesDeleted() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get wasRunning => $_getBF(5);
  @$pb.TagNumber(6)
  set wasRunning($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasWasRunning() => $_has(5);
  @$pb.TagNumber(6)
  void clearWasRunning() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get partialBytesPreserved => $_getBF(6);
  @$pb.TagNumber(7)
  set partialBytesPreserved($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPartialBytesPreserved() => $_has(6);
  @$pb.TagNumber(7)
  void clearPartialBytesPreserved() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get resumeToken => $_getSZ(7);
  @$pb.TagNumber(8)
  set resumeToken($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasResumeToken() => $_has(7);
  @$pb.TagNumber(8)
  void clearResumeToken() => $_clearField(8);
}

class DownloadResumeRequest extends $pb.GeneratedMessage {
  factory DownloadResumeRequest({
    $core.String? taskId,
    $core.String? modelId,
    $fixnum.Int64? resumeFromBytes,
    $core.String? resumeToken,
    $core.bool? validatePartialBytes,
  }) {
    final result = create();
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (resumeFromBytes != null) result.resumeFromBytes = resumeFromBytes;
    if (resumeToken != null) result.resumeToken = resumeToken;
    if (validatePartialBytes != null)
      result.validatePartialBytes = validatePartialBytes;
    return result;
  }

  DownloadResumeRequest._();

  factory DownloadResumeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadResumeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadResumeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'taskId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aInt64(3, _omitFieldNames ? '' : 'resumeFromBytes')
    ..aOS(4, _omitFieldNames ? '' : 'resumeToken')
    ..aOB(5, _omitFieldNames ? '' : 'validatePartialBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadResumeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadResumeRequest copyWith(
          void Function(DownloadResumeRequest) updates) =>
      super.copyWith((message) => updates(message as DownloadResumeRequest))
          as DownloadResumeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadResumeRequest create() => DownloadResumeRequest._();
  @$core.override
  DownloadResumeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadResumeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadResumeRequest>(create);
  static DownloadResumeRequest? _defaultInstance;

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
  $fixnum.Int64 get resumeFromBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set resumeFromBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasResumeFromBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeFromBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get resumeToken => $_getSZ(3);
  @$pb.TagNumber(4)
  set resumeToken($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResumeToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearResumeToken() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get validatePartialBytes => $_getBF(4);
  @$pb.TagNumber(5)
  set validatePartialBytes($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasValidatePartialBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearValidatePartialBytes() => $_clearField(5);
}

class DownloadResumeResult extends $pb.GeneratedMessage {
  factory DownloadResumeResult({
    $core.bool? accepted,
    $core.String? taskId,
    $core.String? modelId,
    DownloadProgress? initialProgress,
    $core.String? errorMessage,
    $core.String? resumeToken,
    DownloadFailureReason? failureReason,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (taskId != null) result.taskId = taskId;
    if (modelId != null) result.modelId = modelId;
    if (initialProgress != null) result.initialProgress = initialProgress;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (resumeToken != null) result.resumeToken = resumeToken;
    if (failureReason != null) result.failureReason = failureReason;
    return result;
  }

  DownloadResumeResult._();

  factory DownloadResumeResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadResumeResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadResumeResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aOM<DownloadProgress>(4, _omitFieldNames ? '' : 'initialProgress',
        subBuilder: DownloadProgress.create)
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(6, _omitFieldNames ? '' : 'resumeToken')
    ..aE<DownloadFailureReason>(7, _omitFieldNames ? '' : 'failureReason',
        enumValues: DownloadFailureReason.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadResumeResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadResumeResult copyWith(void Function(DownloadResumeResult) updates) =>
      super.copyWith((message) => updates(message as DownloadResumeResult))
          as DownloadResumeResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadResumeResult create() => DownloadResumeResult._();
  @$core.override
  DownloadResumeResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadResumeResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadResumeResult>(create);
  static DownloadResumeResult? _defaultInstance;

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

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get resumeToken => $_getSZ(5);
  @$pb.TagNumber(6)
  set resumeToken($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasResumeToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearResumeToken() => $_clearField(6);

  @$pb.TagNumber(7)
  DownloadFailureReason get failureReason => $_getN(6);
  @$pb.TagNumber(7)
  set failureReason(DownloadFailureReason value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFailureReason() => $_has(6);
  @$pb.TagNumber(7)
  void clearFailureReason() => $_clearField(7);
}

class DownloadApi {
  final $pb.RpcClient _client;

  DownloadApi(this._client);

  $async.Future<DownloadPlanResult> plan(
          $pb.ClientContext? ctx, DownloadPlanRequest request) =>
      _client.invoke<DownloadPlanResult>(
          ctx, 'Download', 'Plan', request, DownloadPlanResult());
  $async.Future<DownloadStartResult> start(
          $pb.ClientContext? ctx, DownloadStartRequest request) =>
      _client.invoke<DownloadStartResult>(
          ctx, 'Download', 'Start', request, DownloadStartResult());

  /// Server-streaming: emits a DownloadProgress message every time
  /// bytes_downloaded crosses a per-engine reporting threshold (currently
  /// every 64 KiB) until state ∈ {COMPLETED, FAILED, CANCELLED}.
  $async.Future<DownloadProgress> subscribe(
          $pb.ClientContext? ctx, DownloadSubscribeRequest request) =>
      _client.invoke<DownloadProgress>(
          ctx, 'Download', 'Subscribe', request, DownloadProgress());
  $async.Future<DownloadCancelResult> cancel(
          $pb.ClientContext? ctx, DownloadCancelRequest request) =>
      _client.invoke<DownloadCancelResult>(
          ctx, 'Download', 'Cancel', request, DownloadCancelResult());
  $async.Future<DownloadResumeResult> resume(
          $pb.ClientContext? ctx, DownloadResumeRequest request) =>
      _client.invoke<DownloadResumeResult>(
          ctx, 'Download', 'Resume', request, DownloadResumeResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
