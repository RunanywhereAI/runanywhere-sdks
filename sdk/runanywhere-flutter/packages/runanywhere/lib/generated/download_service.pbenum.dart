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

import 'package:protobuf/protobuf.dart' as $pb;

class DownloadStage extends $pb.ProtobufEnum {
  static const DownloadStage DOWNLOAD_STAGE_UNSPECIFIED =
      DownloadStage._(0, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_UNSPECIFIED');
  static const DownloadStage DOWNLOAD_STAGE_DOWNLOADING =
      DownloadStage._(1, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_DOWNLOADING');
  static const DownloadStage DOWNLOAD_STAGE_EXTRACTING =
      DownloadStage._(2, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_EXTRACTING');
  static const DownloadStage DOWNLOAD_STAGE_VALIDATING =
      DownloadStage._(3, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_VALIDATING');
  static const DownloadStage DOWNLOAD_STAGE_COMPLETED =
      DownloadStage._(4, _omitEnumNames ? '' : 'DOWNLOAD_STAGE_COMPLETED');

  static const $core.List<DownloadStage> values = <DownloadStage>[
    DOWNLOAD_STAGE_UNSPECIFIED,
    DOWNLOAD_STAGE_DOWNLOADING,
    DOWNLOAD_STAGE_EXTRACTING,
    DOWNLOAD_STAGE_VALIDATING,
    DOWNLOAD_STAGE_COMPLETED,
  ];

  static final $core.List<DownloadStage?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static DownloadStage? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DownloadStage._(super.value, super.name);
}

class DownloadState extends $pb.ProtobufEnum {
  static const DownloadState DOWNLOAD_STATE_UNSPECIFIED =
      DownloadState._(0, _omitEnumNames ? '' : 'DOWNLOAD_STATE_UNSPECIFIED');
  static const DownloadState DOWNLOAD_STATE_PENDING =
      DownloadState._(1, _omitEnumNames ? '' : 'DOWNLOAD_STATE_PENDING');
  static const DownloadState DOWNLOAD_STATE_DOWNLOADING =
      DownloadState._(2, _omitEnumNames ? '' : 'DOWNLOAD_STATE_DOWNLOADING');
  static const DownloadState DOWNLOAD_STATE_EXTRACTING =
      DownloadState._(3, _omitEnumNames ? '' : 'DOWNLOAD_STATE_EXTRACTING');
  static const DownloadState DOWNLOAD_STATE_RETRYING =
      DownloadState._(4, _omitEnumNames ? '' : 'DOWNLOAD_STATE_RETRYING');
  static const DownloadState DOWNLOAD_STATE_COMPLETED =
      DownloadState._(5, _omitEnumNames ? '' : 'DOWNLOAD_STATE_COMPLETED');
  static const DownloadState DOWNLOAD_STATE_FAILED =
      DownloadState._(6, _omitEnumNames ? '' : 'DOWNLOAD_STATE_FAILED');
  static const DownloadState DOWNLOAD_STATE_CANCELLED =
      DownloadState._(7, _omitEnumNames ? '' : 'DOWNLOAD_STATE_CANCELLED');
  static const DownloadState DOWNLOAD_STATE_PAUSED =
      DownloadState._(8, _omitEnumNames ? '' : 'DOWNLOAD_STATE_PAUSED');
  static const DownloadState DOWNLOAD_STATE_RESUMING =
      DownloadState._(9, _omitEnumNames ? '' : 'DOWNLOAD_STATE_RESUMING');

  static const $core.List<DownloadState> values = <DownloadState>[
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

  static final $core.List<DownloadState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 9);
  static DownloadState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DownloadState._(super.value, super.name);
}

/// Structured reason for a download plan/start/resume rejection. Lets every SDK
/// branch on a stable enum instead of substring-matching the human-readable
/// error_message (the prior approach, which silently broke on any reword).
class DownloadFailureReason extends $pb.ProtobufEnum {
  static const DownloadFailureReason DOWNLOAD_FAILURE_REASON_UNSPECIFIED =
      DownloadFailureReason._(
          0, _omitEnumNames ? '' : 'DOWNLOAD_FAILURE_REASON_UNSPECIFIED');

  /// On-disk partial download is larger than the expected total byte count.
  static const DownloadFailureReason
      DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES = DownloadFailureReason._(
          1,
          _omitEnumNames
              ? ''
              : 'DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES');

  /// Requested resume offset is past the expected total size.
  static const DownloadFailureReason
      DOWNLOAD_FAILURE_REASON_RESUME_OFFSET_EXCEEDS_EXPECTED =
      DownloadFailureReason._(
          2,
          _omitEnumNames
              ? ''
              : 'DOWNLOAD_FAILURE_REASON_RESUME_OFFSET_EXCEEDS_EXPECTED');

  /// On-disk partial is smaller than the requested resume offset.
  static const DownloadFailureReason
      DOWNLOAD_FAILURE_REASON_PARTIAL_SMALLER_THAN_OFFSET =
      DownloadFailureReason._(
          3,
          _omitEnumNames
              ? ''
              : 'DOWNLOAD_FAILURE_REASON_PARTIAL_SMALLER_THAN_OFFSET');

  /// The partial file changed (size/mtime) since the resume token was issued.
  static const DownloadFailureReason
      DOWNLOAD_FAILURE_REASON_PARTIAL_CHANGED_BEFORE_RESUME =
      DownloadFailureReason._(
          4,
          _omitEnumNames
              ? ''
              : 'DOWNLOAD_FAILURE_REASON_PARTIAL_CHANGED_BEFORE_RESUME');

  /// Not enough free space to complete the download.
  static const DownloadFailureReason
      DOWNLOAD_FAILURE_REASON_INSUFFICIENT_STORAGE = DownloadFailureReason._(5,
          _omitEnumNames ? '' : 'DOWNLOAD_FAILURE_REASON_INSUFFICIENT_STORAGE');

  static const $core.List<DownloadFailureReason> values =
      <DownloadFailureReason>[
    DOWNLOAD_FAILURE_REASON_UNSPECIFIED,
    DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES,
    DOWNLOAD_FAILURE_REASON_RESUME_OFFSET_EXCEEDS_EXPECTED,
    DOWNLOAD_FAILURE_REASON_PARTIAL_SMALLER_THAN_OFFSET,
    DOWNLOAD_FAILURE_REASON_PARTIAL_CHANGED_BEFORE_RESUME,
    DOWNLOAD_FAILURE_REASON_INSUFFICIENT_STORAGE,
  ];

  static final $core.List<DownloadFailureReason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static DownloadFailureReason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DownloadFailureReason._(super.value, super.name);
}

/// HTTP transport download status — numeric values MUST match
/// rac_http_download_status_t (RAC_HTTP_DL_*) in
/// sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_download.h.
/// rac_http_download_execute returns this int directly through the C ABI;
/// every SDK consumes the proto-generated enum so a new RAC_HTTP_DL_* value
/// added in commons fails compilation across all bindings until the enum is
/// extended here. OK = 0 mirrors the C ABI's success sentinel (no separate
/// UNSPECIFIED needed — success is the proto3 zero default).
class HttpDownloadStatus extends $pb.ProtobufEnum {
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_OK =
      HttpDownloadStatus._(0, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_OK');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_NETWORK_ERROR =
      HttpDownloadStatus._(
          1, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_NETWORK_ERROR');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_FILE_ERROR =
      HttpDownloadStatus._(
          2, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_FILE_ERROR');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_INSUFFICIENT_STORAGE =
      HttpDownloadStatus._(
          3, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_INSUFFICIENT_STORAGE');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_INVALID_URL =
      HttpDownloadStatus._(
          4, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_INVALID_URL');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_CHECKSUM_FAILED =
      HttpDownloadStatus._(
          5, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_CHECKSUM_FAILED');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_CANCELLED =
      HttpDownloadStatus._(
          6, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_CANCELLED');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_SERVER_ERROR =
      HttpDownloadStatus._(
          7, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_SERVER_ERROR');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_TIMEOUT =
      HttpDownloadStatus._(
          8, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_TIMEOUT');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_NETWORK_UNAVAILABLE =
      HttpDownloadStatus._(
          9, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_NETWORK_UNAVAILABLE');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_DNS_ERROR =
      HttpDownloadStatus._(
          10, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_DNS_ERROR');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_SSL_ERROR =
      HttpDownloadStatus._(
          11, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_SSL_ERROR');
  static const HttpDownloadStatus HTTP_DOWNLOAD_STATUS_UNKNOWN =
      HttpDownloadStatus._(
          99, _omitEnumNames ? '' : 'HTTP_DOWNLOAD_STATUS_UNKNOWN');

  static const $core.List<HttpDownloadStatus> values = <HttpDownloadStatus>[
    HTTP_DOWNLOAD_STATUS_OK,
    HTTP_DOWNLOAD_STATUS_NETWORK_ERROR,
    HTTP_DOWNLOAD_STATUS_FILE_ERROR,
    HTTP_DOWNLOAD_STATUS_INSUFFICIENT_STORAGE,
    HTTP_DOWNLOAD_STATUS_INVALID_URL,
    HTTP_DOWNLOAD_STATUS_CHECKSUM_FAILED,
    HTTP_DOWNLOAD_STATUS_CANCELLED,
    HTTP_DOWNLOAD_STATUS_SERVER_ERROR,
    HTTP_DOWNLOAD_STATUS_TIMEOUT,
    HTTP_DOWNLOAD_STATUS_NETWORK_UNAVAILABLE,
    HTTP_DOWNLOAD_STATUS_DNS_ERROR,
    HTTP_DOWNLOAD_STATUS_SSL_ERROR,
    HTTP_DOWNLOAD_STATUS_UNKNOWN,
  ];

  static final $core.Map<$core.int, HttpDownloadStatus> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static HttpDownloadStatus? valueOf($core.int value) => _byValue[value];

  const HttpDownloadStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
