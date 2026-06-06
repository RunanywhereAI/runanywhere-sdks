// This is a generated file - do not edit.
//
// Generated from logging.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Severity, mirroring the C ABI `rac_log_level_t`. Larger value = more severe.
/// 0 is TRACE (not UNSPECIFIED) to keep numeric parity with the C enum — the
/// same C-ABI-aligned convention used by HttpDownloadStatus (0=OK) and
/// SdkInitEnvironment (0=DEVELOPMENT).
/// ---------------------------------------------------------------------------
class LogLevel extends $pb.ProtobufEnum {
  static const LogLevel LOG_LEVEL_TRACE =
      LogLevel._(0, _omitEnumNames ? '' : 'LOG_LEVEL_TRACE');
  static const LogLevel LOG_LEVEL_DEBUG =
      LogLevel._(1, _omitEnumNames ? '' : 'LOG_LEVEL_DEBUG');
  static const LogLevel LOG_LEVEL_INFO =
      LogLevel._(2, _omitEnumNames ? '' : 'LOG_LEVEL_INFO');
  static const LogLevel LOG_LEVEL_WARNING =
      LogLevel._(3, _omitEnumNames ? '' : 'LOG_LEVEL_WARNING');
  static const LogLevel LOG_LEVEL_ERROR =
      LogLevel._(4, _omitEnumNames ? '' : 'LOG_LEVEL_ERROR');
  static const LogLevel LOG_LEVEL_FATAL =
      LogLevel._(5, _omitEnumNames ? '' : 'LOG_LEVEL_FATAL');

  static const $core.List<LogLevel> values = <LogLevel>[
    LOG_LEVEL_TRACE,
    LOG_LEVEL_DEBUG,
    LOG_LEVEL_INFO,
    LOG_LEVEL_WARNING,
    LOG_LEVEL_ERROR,
    LOG_LEVEL_FATAL,
  ];

  static final $core.List<LogLevel?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static LogLevel? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LogLevel._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
