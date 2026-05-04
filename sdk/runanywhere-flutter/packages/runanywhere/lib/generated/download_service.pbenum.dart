//
//  Generated code. Do not modify.
//  source: download_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class DownloadStage extends $pb.ProtobufEnum {
  static const DownloadStage DOWNLOAD_STAGE_UNSPECIFIED = DownloadStage._(0, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_UNSPECIFIED');
  static const DownloadStage DOWNLOAD_STAGE_DOWNLOADING = DownloadStage._(1, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_DOWNLOADING');
  static const DownloadStage DOWNLOAD_STAGE_EXTRACTING = DownloadStage._(2, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_EXTRACTING');
  static const DownloadStage DOWNLOAD_STAGE_VALIDATING = DownloadStage._(3, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_VALIDATING');
  static const DownloadStage DOWNLOAD_STAGE_COMPLETED = DownloadStage._(4, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_COMPLETED');

  static const $core.List<DownloadStage> values = <DownloadStage> [
    DOWNLOAD_STAGE_UNSPECIFIED,
    DOWNLOAD_STAGE_DOWNLOADING,
    DOWNLOAD_STAGE_EXTRACTING,
    DOWNLOAD_STAGE_VALIDATING,
    DOWNLOAD_STAGE_COMPLETED,
  ];

  static final $core.Map<$core.int, DownloadStage> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DownloadStage? valueOf($core.int value) => _byValue[value];

  const DownloadStage._($core.int v, $core.String n) : super(v, n);
}

class DownloadState extends $pb.ProtobufEnum {
  static const DownloadState DOWNLOAD_STATE_UNSPECIFIED = DownloadState._(0, _omitEnumNames ? '' : 'DOWNLOAD_STATE_UNSPECIFIED');
  static const DownloadState DOWNLOAD_STATE_PENDING = DownloadState._(1, _omitEnumNames ? '' : 'DOWNLOAD_STATE_PENDING');
  static const DownloadState DOWNLOAD_STATE_DOWNLOADING = DownloadState._(2, _omitEnumNames ? '' : 'DOWNLOAD_STATE_DOWNLOADING');
  static const DownloadState DOWNLOAD_STATE_EXTRACTING = DownloadState._(3, _omitEnumNames ? '' : 'DOWNLOAD_STATE_EXTRACTING');
  static const DownloadState DOWNLOAD_STATE_RETRYING = DownloadState._(4, _omitEnumNames ? '' : 'DOWNLOAD_STATE_RETRYING');
  static const DownloadState DOWNLOAD_STATE_COMPLETED = DownloadState._(5, _omitEnumNames ? '' : 'DOWNLOAD_STATE_COMPLETED');
  static const DownloadState DOWNLOAD_STATE_FAILED = DownloadState._(6, _omitEnumNames ? '' : 'DOWNLOAD_STATE_FAILED');
  static const DownloadState DOWNLOAD_STATE_CANCELLED = DownloadState._(7, _omitEnumNames ? '' : 'DOWNLOAD_STATE_CANCELLED');
  static const DownloadState DOWNLOAD_STATE_PAUSED = DownloadState._(8, _omitEnumNames ? '' : 'DOWNLOAD_STATE_PAUSED');
  static const DownloadState DOWNLOAD_STATE_RESUMING = DownloadState._(9, _omitEnumNames ? '' : 'DOWNLOAD_STATE_RESUMING');

  static const $core.List<DownloadState> values = <DownloadState> [
    DOWNLOAD_STATE_UNSPECIFIED,
    DOWNLOAD_STATE_PENDING,
    DOWNLOAD_STATE_DOWNLOADING,
    DOWNLOAD_STATE_EXTRACTING,
    DOWNLOAD_STATE_RETRYING,
    DOWNLOAD_STATE_COMPLETED,
    DOWNLOAD_STATE_FAILED,
    DOWNLOAD_STATE_CANCELLED,
    DOWNLOAD_STATE_PAUSED,
    DOWNLOAD_STATE_RESUMING,
  ];

  static final $core.Map<$core.int, DownloadState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DownloadState? valueOf($core.int value) => _byValue[value];

  const DownloadState._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
