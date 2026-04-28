///
//  Generated code. Do not modify.
//  source: download_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'download_service.pbenum.dart';

export 'download_service.pbenum.dart';

class DownloadSubscribeRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DownloadSubscribeRequest', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..hasRequiredFields = false
  ;

  DownloadSubscribeRequest._() : super();
  factory DownloadSubscribeRequest({
    $core.String? modelId,
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    return _result;
  }
  factory DownloadSubscribeRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadSubscribeRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadSubscribeRequest clone() => DownloadSubscribeRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadSubscribeRequest copyWith(void Function(DownloadSubscribeRequest) updates) => super.copyWith((message) => updates(message as DownloadSubscribeRequest)) as DownloadSubscribeRequest; // ignore: deprecated_member_use
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
}

class DownloadProgress extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'DownloadProgress', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelId')
    ..e<DownloadStage>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stage', $pb.PbFieldType.OE, defaultOrMaker: DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED, valueOf: DownloadStage.valueOf, enumValues: DownloadStage.values)
    ..aInt64(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'bytesDownloaded')
    ..aInt64(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'totalBytes')
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stageProgress', $pb.PbFieldType.OF)
    ..a<$core.double>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'overallSpeedBps', $pb.PbFieldType.OF)
    ..aInt64(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'etaSeconds')
    ..e<DownloadState>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'state', $pb.PbFieldType.OE, defaultOrMaker: DownloadState.DOWNLOAD_STATE_UNSPECIFIED, valueOf: DownloadState.valueOf, enumValues: DownloadState.values)
    ..a<$core.int>(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'retryAttempt', $pb.PbFieldType.O3)
    ..aOS(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  DownloadProgress._() : super();
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
  }) {
    final _result = create();
    if (modelId != null) {
      _result.modelId = modelId;
    }
    if (stage != null) {
      _result.stage = stage;
    }
    if (bytesDownloaded != null) {
      _result.bytesDownloaded = bytesDownloaded;
    }
    if (totalBytes != null) {
      _result.totalBytes = totalBytes;
    }
    if (stageProgress != null) {
      _result.stageProgress = stageProgress;
    }
    if (overallSpeedBps != null) {
      _result.overallSpeedBps = overallSpeedBps;
    }
    if (etaSeconds != null) {
      _result.etaSeconds = etaSeconds;
    }
    if (state != null) {
      _result.state = state;
    }
    if (retryAttempt != null) {
      _result.retryAttempt = retryAttempt;
    }
    if (errorMessage != null) {
      _result.errorMessage = errorMessage;
    }
    return _result;
  }
  factory DownloadProgress.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DownloadProgress.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DownloadProgress clone() => DownloadProgress()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DownloadProgress copyWith(void Function(DownloadProgress) updates) => super.copyWith((message) => updates(message as DownloadProgress)) as DownloadProgress; // ignore: deprecated_member_use
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
}

class DownloadApi {
  $pb.RpcClient _client;
  DownloadApi(this._client);

  $async.Future<DownloadProgress> subscribe($pb.ClientContext? ctx, DownloadSubscribeRequest request) {
    var emptyResponse = DownloadProgress();
    return _client.invoke<DownloadProgress>(ctx, 'Download', 'Subscribe', request, emptyResponse);
  }
}

