//
//  Generated code. Do not modify.
//  source: download_service.proto
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

import 'download_service.pbenum.dart';
import 'model_types.pb.dart' as $3;

export 'download_service.pbenum.dart';

class DownloadSubscribeRequest extends $pb.GeneratedMessage {
  factory DownloadSubscribeRequest({
    $core.String? modelId,
    $core.String? taskId,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (taskId != null) {
      $result.taskId = taskId;
    }
    return $result;
  }
  DownloadSubscribeRequest._() : super();
  factory DownloadSubscribeRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadSubscribeRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadSubscribeRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadSubscribeRequest clone() => DownloadSubscribeRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadSubscribeRequest copyWith(void Function(DownloadSubscribeRequest) updates) => super.copyWith((message) => updates(message as DownloadSubscribeRequest)) as DownloadSubscribeRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadSubscribeRequest create() => DownloadSubscribeRequest._();
  DownloadSubscribeRequest createEmptyInstance() => create();
  static $pb.PbList<DownloadSubscribeRequest> createRepeated() => $pb.PbList<DownloadSubscribeRequest>();
  @$core.pragma('dart2js:noInline')
  static DownloadSubscribeRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadSubscribeRequest>(create);
  static DownloadSubscribeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(1);
  @$pb.TagNumber(2)
  set taskId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTaskId() => clearField(2);
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
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (stage != null) {
      $result.stage = stage;
    }
    if (bytesDownloaded != null) {
      $result.bytesDownloaded = bytesDownloaded;
    }
    if (totalBytes != null) {
      $result.totalBytes = totalBytes;
    }
    if (stageProgress != null) {
      $result.stageProgress = stageProgress;
    }
    if (overallSpeedBps != null) {
      $result.overallSpeedBps = overallSpeedBps;
    }
    if (etaSeconds != null) {
      $result.etaSeconds = etaSeconds;
    }
    if (state != null) {
      $result.state = state;
    }
    if (retryAttempt != null) {
      $result.retryAttempt = retryAttempt;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (taskId != null) {
      $result.taskId = taskId;
    }
    if (currentFileIndex != null) {
      $result.currentFileIndex = currentFileIndex;
    }
    if (totalFiles != null) {
      $result.totalFiles = totalFiles;
    }
    if (storageKey != null) {
      $result.storageKey = storageKey;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    return $result;
  }
  DownloadProgress._() : super();
  factory DownloadProgress.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadProgress.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadProgress', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..e<DownloadStage>(2, _omitFieldNames ? '' : 'stage', $pb.PbFieldType.OE, defaultOrMaker: DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED, valueOf: DownloadStage.valueOf, enumValues: DownloadStage.values)
    ..aInt64(3, _omitFieldNames ? '' : 'bytesDownloaded')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..a<$core.double>(5, _omitFieldNames ? '' : 'stageProgress', $pb.PbFieldType.OF)
    ..a<$core.double>(6, _omitFieldNames ? '' : 'overallSpeedBps', $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'etaSeconds')
    ..e<DownloadState>(8, _omitFieldNames ? '' : 'state', $pb.PbFieldType.OE, defaultOrMaker: DownloadState.DOWNLOAD_STATE_UNSPECIFIED, valueOf: DownloadState.valueOf, enumValues: DownloadState.values)
    ..a<$core.int>(9, _omitFieldNames ? '' : 'retryAttempt', $pb.PbFieldType.O3)
    ..aOS(10, _omitFieldNames ? '' : 'errorMessage')
    ..aOS(11, _omitFieldNames ? '' : 'taskId')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'currentFileIndex', $pb.PbFieldType.O3)
    ..a<$core.int>(13, _omitFieldNames ? '' : 'totalFiles', $pb.PbFieldType.O3)
    ..aOS(14, _omitFieldNames ? '' : 'storageKey')
    ..aOS(15, _omitFieldNames ? '' : 'localPath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadProgress clone() => DownloadProgress()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadProgress copyWith(void Function(DownloadProgress) updates) => super.copyWith((message) => updates(message as DownloadProgress)) as DownloadProgress;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadProgress create() => DownloadProgress._();
  DownloadProgress createEmptyInstance() => create();
  static $pb.PbList<DownloadProgress> createRepeated() => $pb.PbList<DownloadProgress>();
  @$core.pragma('dart2js:noInline')
  static DownloadProgress getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadProgress>(create);
  static DownloadProgress? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  DownloadStage get stage => $_getN(1);
  @$pb.TagNumber(2)
  set stage(DownloadStage v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasStage() => $_has(1);
  @$pb.TagNumber(2)
  void clearStage() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get bytesDownloaded => $_getI64(2);
  @$pb.TagNumber(3)
  set bytesDownloaded($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBytesDownloaded() => $_has(2);
  @$pb.TagNumber(3)
  void clearBytesDownloaded() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get stageProgress => $_getN(4);
  @$pb.TagNumber(5)
  set stageProgress($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasStageProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearStageProgress() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get overallSpeedBps => $_getN(5);
  @$pb.TagNumber(6)
  set overallSpeedBps($core.double v) { $_setFloat(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasOverallSpeedBps() => $_has(5);
  @$pb.TagNumber(6)
  void clearOverallSpeedBps() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get etaSeconds => $_getI64(6);
  @$pb.TagNumber(7)
  set etaSeconds($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEtaSeconds() => $_has(6);
  @$pb.TagNumber(7)
  void clearEtaSeconds() => clearField(7);

  @$pb.TagNumber(8)
  DownloadState get state => $_getN(7);
  @$pb.TagNumber(8)
  set state(DownloadState v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasState() => $_has(7);
  @$pb.TagNumber(8)
  void clearState() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get retryAttempt => $_getIZ(8);
  @$pb.TagNumber(9)
  set retryAttempt($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasRetryAttempt() => $_has(8);
  @$pb.TagNumber(9)
  void clearRetryAttempt() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get errorMessage => $_getSZ(9);
  @$pb.TagNumber(10)
  set errorMessage($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasErrorMessage() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorMessage() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get taskId => $_getSZ(10);
  @$pb.TagNumber(11)
  set taskId($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasTaskId() => $_has(10);
  @$pb.TagNumber(11)
  void clearTaskId() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get currentFileIndex => $_getIZ(11);
  @$pb.TagNumber(12)
  set currentFileIndex($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasCurrentFileIndex() => $_has(11);
  @$pb.TagNumber(12)
  void clearCurrentFileIndex() => clearField(12);

  @$pb.TagNumber(13)
  $core.int get totalFiles => $_getIZ(12);
  @$pb.TagNumber(13)
  set totalFiles($core.int v) { $_setSignedInt32(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasTotalFiles() => $_has(12);
  @$pb.TagNumber(13)
  void clearTotalFiles() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get storageKey => $_getSZ(13);
  @$pb.TagNumber(14)
  set storageKey($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasStorageKey() => $_has(13);
  @$pb.TagNumber(14)
  void clearStorageKey() => clearField(14);

  @$pb.TagNumber(15)
  $core.String get localPath => $_getSZ(14);
  @$pb.TagNumber(15)
  set localPath($core.String v) { $_setString(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasLocalPath() => $_has(14);
  @$pb.TagNumber(15)
  void clearLocalPath() => clearField(15);
}

class DownloadPlanRequest extends $pb.GeneratedMessage {
  factory DownloadPlanRequest({
    $core.String? modelId,
    $3.ModelInfo? model,
    $core.bool? resumeExisting,
    $fixnum.Int64? availableStorageBytes,
    $core.bool? allowMeteredNetwork,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (model != null) {
      $result.model = model;
    }
    if (resumeExisting != null) {
      $result.resumeExisting = resumeExisting;
    }
    if (availableStorageBytes != null) {
      $result.availableStorageBytes = availableStorageBytes;
    }
    if (allowMeteredNetwork != null) {
      $result.allowMeteredNetwork = allowMeteredNetwork;
    }
    return $result;
  }
  DownloadPlanRequest._() : super();
  factory DownloadPlanRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadPlanRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadPlanRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOM<$3.ModelInfo>(2, _omitFieldNames ? '' : 'model', subBuilder: $3.ModelInfo.create)
    ..aOB(3, _omitFieldNames ? '' : 'resumeExisting')
    ..aInt64(4, _omitFieldNames ? '' : 'availableStorageBytes')
    ..aOB(5, _omitFieldNames ? '' : 'allowMeteredNetwork')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadPlanRequest clone() => DownloadPlanRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadPlanRequest copyWith(void Function(DownloadPlanRequest) updates) => super.copyWith((message) => updates(message as DownloadPlanRequest)) as DownloadPlanRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadPlanRequest create() => DownloadPlanRequest._();
  DownloadPlanRequest createEmptyInstance() => create();
  static $pb.PbList<DownloadPlanRequest> createRepeated() => $pb.PbList<DownloadPlanRequest>();
  @$core.pragma('dart2js:noInline')
  static DownloadPlanRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadPlanRequest>(create);
  static DownloadPlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $3.ModelInfo get model => $_getN(1);
  @$pb.TagNumber(2)
  set model($3.ModelInfo v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearModel() => clearField(2);
  @$pb.TagNumber(2)
  $3.ModelInfo ensureModel() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get resumeExisting => $_getBF(2);
  @$pb.TagNumber(3)
  set resumeExisting($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResumeExisting() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeExisting() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get availableStorageBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set availableStorageBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAvailableStorageBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvailableStorageBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get allowMeteredNetwork => $_getBF(4);
  @$pb.TagNumber(5)
  set allowMeteredNetwork($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAllowMeteredNetwork() => $_has(4);
  @$pb.TagNumber(5)
  void clearAllowMeteredNetwork() => clearField(5);
}

class DownloadFilePlan extends $pb.GeneratedMessage {
  factory DownloadFilePlan({
    $3.ModelFileDescriptor? file,
    $core.String? storageKey,
    $core.String? destinationPath,
    $fixnum.Int64? expectedBytes,
    $core.bool? requiresExtraction,
    $core.String? checksumSha256,
  }) {
    final $result = create();
    if (file != null) {
      $result.file = file;
    }
    if (storageKey != null) {
      $result.storageKey = storageKey;
    }
    if (destinationPath != null) {
      $result.destinationPath = destinationPath;
    }
    if (expectedBytes != null) {
      $result.expectedBytes = expectedBytes;
    }
    if (requiresExtraction != null) {
      $result.requiresExtraction = requiresExtraction;
    }
    if (checksumSha256 != null) {
      $result.checksumSha256 = checksumSha256;
    }
    return $result;
  }
  DownloadFilePlan._() : super();
  factory DownloadFilePlan.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadFilePlan.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadFilePlan', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOM<$3.ModelFileDescriptor>(1, _omitFieldNames ? '' : 'file', subBuilder: $3.ModelFileDescriptor.create)
    ..aOS(2, _omitFieldNames ? '' : 'storageKey')
    ..aOS(3, _omitFieldNames ? '' : 'destinationPath')
    ..aInt64(4, _omitFieldNames ? '' : 'expectedBytes')
    ..aOB(5, _omitFieldNames ? '' : 'requiresExtraction')
    ..aOS(6, _omitFieldNames ? '' : 'checksumSha256')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadFilePlan clone() => DownloadFilePlan()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadFilePlan copyWith(void Function(DownloadFilePlan) updates) => super.copyWith((message) => updates(message as DownloadFilePlan)) as DownloadFilePlan;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadFilePlan create() => DownloadFilePlan._();
  DownloadFilePlan createEmptyInstance() => create();
  static $pb.PbList<DownloadFilePlan> createRepeated() => $pb.PbList<DownloadFilePlan>();
  @$core.pragma('dart2js:noInline')
  static DownloadFilePlan getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadFilePlan>(create);
  static DownloadFilePlan? _defaultInstance;

  @$pb.TagNumber(1)
  $3.ModelFileDescriptor get file => $_getN(0);
  @$pb.TagNumber(1)
  set file($3.ModelFileDescriptor v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasFile() => $_has(0);
  @$pb.TagNumber(1)
  void clearFile() => clearField(1);
  @$pb.TagNumber(1)
  $3.ModelFileDescriptor ensureFile() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get storageKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set storageKey($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasStorageKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearStorageKey() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get destinationPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set destinationPath($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDestinationPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearDestinationPath() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expectedBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set expectedBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasExpectedBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get requiresExtraction => $_getBF(4);
  @$pb.TagNumber(5)
  set requiresExtraction($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRequiresExtraction() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequiresExtraction() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get checksumSha256 => $_getSZ(5);
  @$pb.TagNumber(6)
  set checksumSha256($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasChecksumSha256() => $_has(5);
  @$pb.TagNumber(6)
  void clearChecksumSha256() => clearField(6);
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
  }) {
    final $result = create();
    if (canStart != null) {
      $result.canStart = canStart;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (files != null) {
      $result.files.addAll(files);
    }
    if (totalBytes != null) {
      $result.totalBytes = totalBytes;
    }
    if (requiresExtraction != null) {
      $result.requiresExtraction = requiresExtraction;
    }
    if (canResume != null) {
      $result.canResume = canResume;
    }
    if (resumeFromBytes != null) {
      $result.resumeFromBytes = resumeFromBytes;
    }
    if (warnings != null) {
      $result.warnings.addAll(warnings);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  DownloadPlanResult._() : super();
  factory DownloadPlanResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadPlanResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadPlanResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'canStart')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..pc<DownloadFilePlan>(3, _omitFieldNames ? '' : 'files', $pb.PbFieldType.PM, subBuilder: DownloadFilePlan.create)
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..aOB(5, _omitFieldNames ? '' : 'requiresExtraction')
    ..aOB(6, _omitFieldNames ? '' : 'canResume')
    ..aInt64(7, _omitFieldNames ? '' : 'resumeFromBytes')
    ..pPS(8, _omitFieldNames ? '' : 'warnings')
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadPlanResult clone() => DownloadPlanResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadPlanResult copyWith(void Function(DownloadPlanResult) updates) => super.copyWith((message) => updates(message as DownloadPlanResult)) as DownloadPlanResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadPlanResult create() => DownloadPlanResult._();
  DownloadPlanResult createEmptyInstance() => create();
  static $pb.PbList<DownloadPlanResult> createRepeated() => $pb.PbList<DownloadPlanResult>();
  @$core.pragma('dart2js:noInline')
  static DownloadPlanResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadPlanResult>(create);
  static DownloadPlanResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get canStart => $_getBF(0);
  @$pb.TagNumber(1)
  set canStart($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCanStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearCanStart() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<DownloadFilePlan> get files => $_getList(2);

  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get requiresExtraction => $_getBF(4);
  @$pb.TagNumber(5)
  set requiresExtraction($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRequiresExtraction() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequiresExtraction() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get canResume => $_getBF(5);
  @$pb.TagNumber(6)
  set canResume($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasCanResume() => $_has(5);
  @$pb.TagNumber(6)
  void clearCanResume() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get resumeFromBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set resumeFromBytes($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasResumeFromBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearResumeFromBytes() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.String> get warnings => $_getList(7);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => clearField(9);
}

class DownloadStartRequest extends $pb.GeneratedMessage {
  factory DownloadStartRequest({
    $core.String? modelId,
    DownloadPlanResult? plan,
    $core.bool? resume,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (plan != null) {
      $result.plan = plan;
    }
    if (resume != null) {
      $result.resume = resume;
    }
    return $result;
  }
  DownloadStartRequest._() : super();
  factory DownloadStartRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadStartRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadStartRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOM<DownloadPlanResult>(2, _omitFieldNames ? '' : 'plan', subBuilder: DownloadPlanResult.create)
    ..aOB(3, _omitFieldNames ? '' : 'resume')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadStartRequest clone() => DownloadStartRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadStartRequest copyWith(void Function(DownloadStartRequest) updates) => super.copyWith((message) => updates(message as DownloadStartRequest)) as DownloadStartRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadStartRequest create() => DownloadStartRequest._();
  DownloadStartRequest createEmptyInstance() => create();
  static $pb.PbList<DownloadStartRequest> createRepeated() => $pb.PbList<DownloadStartRequest>();
  @$core.pragma('dart2js:noInline')
  static DownloadStartRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadStartRequest>(create);
  static DownloadStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  DownloadPlanResult get plan => $_getN(1);
  @$pb.TagNumber(2)
  set plan(DownloadPlanResult v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasPlan() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlan() => clearField(2);
  @$pb.TagNumber(2)
  DownloadPlanResult ensurePlan() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get resume => $_getBF(2);
  @$pb.TagNumber(3)
  set resume($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResume() => $_has(2);
  @$pb.TagNumber(3)
  void clearResume() => clearField(3);
}

class DownloadStartResult extends $pb.GeneratedMessage {
  factory DownloadStartResult({
    $core.bool? accepted,
    $core.String? taskId,
    $core.String? modelId,
    DownloadProgress? initialProgress,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (taskId != null) {
      $result.taskId = taskId;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (initialProgress != null) {
      $result.initialProgress = initialProgress;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  DownloadStartResult._() : super();
  factory DownloadStartResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadStartResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadStartResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aOM<DownloadProgress>(4, _omitFieldNames ? '' : 'initialProgress', subBuilder: DownloadProgress.create)
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadStartResult clone() => DownloadStartResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadStartResult copyWith(void Function(DownloadStartResult) updates) => super.copyWith((message) => updates(message as DownloadStartResult)) as DownloadStartResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadStartResult create() => DownloadStartResult._();
  DownloadStartResult createEmptyInstance() => create();
  static $pb.PbList<DownloadStartResult> createRepeated() => $pb.PbList<DownloadStartResult>();
  @$core.pragma('dart2js:noInline')
  static DownloadStartResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadStartResult>(create);
  static DownloadStartResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(1);
  @$pb.TagNumber(2)
  set taskId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTaskId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => clearField(3);

  @$pb.TagNumber(4)
  DownloadProgress get initialProgress => $_getN(3);
  @$pb.TagNumber(4)
  set initialProgress(DownloadProgress v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasInitialProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearInitialProgress() => clearField(4);
  @$pb.TagNumber(4)
  DownloadProgress ensureInitialProgress() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);
}

class DownloadCancelRequest extends $pb.GeneratedMessage {
  factory DownloadCancelRequest({
    $core.String? taskId,
    $core.String? modelId,
    $core.bool? deletePartialBytes,
  }) {
    final $result = create();
    if (taskId != null) {
      $result.taskId = taskId;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (deletePartialBytes != null) {
      $result.deletePartialBytes = deletePartialBytes;
    }
    return $result;
  }
  DownloadCancelRequest._() : super();
  factory DownloadCancelRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadCancelRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadCancelRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'taskId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOB(3, _omitFieldNames ? '' : 'deletePartialBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadCancelRequest clone() => DownloadCancelRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadCancelRequest copyWith(void Function(DownloadCancelRequest) updates) => super.copyWith((message) => updates(message as DownloadCancelRequest)) as DownloadCancelRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadCancelRequest create() => DownloadCancelRequest._();
  DownloadCancelRequest createEmptyInstance() => create();
  static $pb.PbList<DownloadCancelRequest> createRepeated() => $pb.PbList<DownloadCancelRequest>();
  @$core.pragma('dart2js:noInline')
  static DownloadCancelRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadCancelRequest>(create);
  static DownloadCancelRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get taskId => $_getSZ(0);
  @$pb.TagNumber(1)
  set taskId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTaskId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTaskId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get deletePartialBytes => $_getBF(2);
  @$pb.TagNumber(3)
  set deletePartialBytes($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDeletePartialBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearDeletePartialBytes() => clearField(3);
}

class DownloadCancelResult extends $pb.GeneratedMessage {
  factory DownloadCancelResult({
    $core.bool? success,
    $core.String? taskId,
    $core.String? modelId,
    $fixnum.Int64? partialBytesDeleted,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (success != null) {
      $result.success = success;
    }
    if (taskId != null) {
      $result.taskId = taskId;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (partialBytesDeleted != null) {
      $result.partialBytesDeleted = partialBytesDeleted;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  DownloadCancelResult._() : super();
  factory DownloadCancelResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadCancelResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadCancelResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aInt64(4, _omitFieldNames ? '' : 'partialBytesDeleted')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadCancelResult clone() => DownloadCancelResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadCancelResult copyWith(void Function(DownloadCancelResult) updates) => super.copyWith((message) => updates(message as DownloadCancelResult)) as DownloadCancelResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadCancelResult create() => DownloadCancelResult._();
  DownloadCancelResult createEmptyInstance() => create();
  static $pb.PbList<DownloadCancelResult> createRepeated() => $pb.PbList<DownloadCancelResult>();
  @$core.pragma('dart2js:noInline')
  static DownloadCancelResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadCancelResult>(create);
  static DownloadCancelResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(1);
  @$pb.TagNumber(2)
  set taskId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTaskId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get partialBytesDeleted => $_getI64(3);
  @$pb.TagNumber(4)
  set partialBytesDeleted($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPartialBytesDeleted() => $_has(3);
  @$pb.TagNumber(4)
  void clearPartialBytesDeleted() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);
}

class DownloadResumeRequest extends $pb.GeneratedMessage {
  factory DownloadResumeRequest({
    $core.String? taskId,
    $core.String? modelId,
    $fixnum.Int64? resumeFromBytes,
  }) {
    final $result = create();
    if (taskId != null) {
      $result.taskId = taskId;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (resumeFromBytes != null) {
      $result.resumeFromBytes = resumeFromBytes;
    }
    return $result;
  }
  DownloadResumeRequest._() : super();
  factory DownloadResumeRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadResumeRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadResumeRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'taskId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aInt64(3, _omitFieldNames ? '' : 'resumeFromBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadResumeRequest clone() => DownloadResumeRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadResumeRequest copyWith(void Function(DownloadResumeRequest) updates) => super.copyWith((message) => updates(message as DownloadResumeRequest)) as DownloadResumeRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadResumeRequest create() => DownloadResumeRequest._();
  DownloadResumeRequest createEmptyInstance() => create();
  static $pb.PbList<DownloadResumeRequest> createRepeated() => $pb.PbList<DownloadResumeRequest>();
  @$core.pragma('dart2js:noInline')
  static DownloadResumeRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadResumeRequest>(create);
  static DownloadResumeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get taskId => $_getSZ(0);
  @$pb.TagNumber(1)
  set taskId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTaskId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTaskId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get resumeFromBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set resumeFromBytes($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasResumeFromBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearResumeFromBytes() => clearField(3);
}

class DownloadResumeResult extends $pb.GeneratedMessage {
  factory DownloadResumeResult({
    $core.bool? accepted,
    $core.String? taskId,
    $core.String? modelId,
    DownloadProgress? initialProgress,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (accepted != null) {
      $result.accepted = accepted;
    }
    if (taskId != null) {
      $result.taskId = taskId;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (initialProgress != null) {
      $result.initialProgress = initialProgress;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  DownloadResumeResult._() : super();
  factory DownloadResumeResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadResumeResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DownloadResumeResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'taskId')
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aOM<DownloadProgress>(4, _omitFieldNames ? '' : 'initialProgress', subBuilder: DownloadProgress.create)
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadResumeResult clone() => DownloadResumeResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadResumeResult copyWith(void Function(DownloadResumeResult) updates) => super.copyWith((message) => updates(message as DownloadResumeResult)) as DownloadResumeResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadResumeResult create() => DownloadResumeResult._();
  DownloadResumeResult createEmptyInstance() => create();
  static $pb.PbList<DownloadResumeResult> createRepeated() => $pb.PbList<DownloadResumeResult>();
  @$core.pragma('dart2js:noInline')
  static DownloadResumeResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DownloadResumeResult>(create);
  static DownloadResumeResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get taskId => $_getSZ(1);
  @$pb.TagNumber(2)
  set taskId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTaskId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTaskId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => clearField(3);

  @$pb.TagNumber(4)
  DownloadProgress get initialProgress => $_getN(3);
  @$pb.TagNumber(4)
  set initialProgress(DownloadProgress v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasInitialProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearInitialProgress() => clearField(4);
  @$pb.TagNumber(4)
  DownloadProgress ensureInitialProgress() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => clearField(5);
}

class DownloadApi {
  $pb.RpcClient _client;
  DownloadApi(this._client);

  $async.Future<DownloadPlanResult> plan($pb.ClientContext? ctx, DownloadPlanRequest request) =>
    _client.invoke<DownloadPlanResult>(ctx, 'Download', 'Plan', request, DownloadPlanResult())
  ;
  $async.Future<DownloadStartResult> start($pb.ClientContext? ctx, DownloadStartRequest request) =>
    _client.invoke<DownloadStartResult>(ctx, 'Download', 'Start', request, DownloadStartResult())
  ;
  $async.Future<DownloadProgress> subscribe($pb.ClientContext? ctx, DownloadSubscribeRequest request) =>
    _client.invoke<DownloadProgress>(ctx, 'Download', 'Subscribe', request, DownloadProgress())
  ;
  $async.Future<DownloadCancelResult> cancel($pb.ClientContext? ctx, DownloadCancelRequest request) =>
    _client.invoke<DownloadCancelResult>(ctx, 'Download', 'Cancel', request, DownloadCancelResult())
  ;
  $async.Future<DownloadResumeResult> resume($pb.ClientContext? ctx, DownloadResumeRequest request) =>
    _client.invoke<DownloadResumeResult>(ctx, 'Download', 'Resume', request, DownloadResumeResult())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
