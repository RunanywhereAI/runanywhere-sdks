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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'logging.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'logging.pbenum.dart';

/// ---------------------------------------------------------------------------
/// SDK logging configuration. Union of the fields the per-SDK
/// LoggingConfiguration structs carry today; per-environment presets
/// (development/staging/production) stay in each SDK as factory helpers.
/// ---------------------------------------------------------------------------
class LoggingConfiguration extends $pb.GeneratedMessage {
  factory LoggingConfiguration({
    $core.bool? enableLocalLogging,
    LogLevel? minLogLevel,
    $core.bool? includeSourceLocation,
    $core.bool? includeDeviceMetadata,
    $core.bool? enableRemoteLogging,
    $core.bool? enableSentryLogging,
  }) {
    final result = create();
    if (enableLocalLogging != null)
      result.enableLocalLogging = enableLocalLogging;
    if (minLogLevel != null) result.minLogLevel = minLogLevel;
    if (includeSourceLocation != null)
      result.includeSourceLocation = includeSourceLocation;
    if (includeDeviceMetadata != null)
      result.includeDeviceMetadata = includeDeviceMetadata;
    if (enableRemoteLogging != null)
      result.enableRemoteLogging = enableRemoteLogging;
    if (enableSentryLogging != null)
      result.enableSentryLogging = enableSentryLogging;
    return result;
  }

  LoggingConfiguration._();

  factory LoggingConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LoggingConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoggingConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enableLocalLogging')
    ..aE<LogLevel>(2, _omitFieldNames ? '' : 'minLogLevel',
        enumValues: LogLevel.values)
    ..aOB(3, _omitFieldNames ? '' : 'includeSourceLocation')
    ..aOB(4, _omitFieldNames ? '' : 'includeDeviceMetadata')
    ..aOB(5, _omitFieldNames ? '' : 'enableRemoteLogging')
    ..aOB(6, _omitFieldNames ? '' : 'enableSentryLogging')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoggingConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoggingConfiguration copyWith(void Function(LoggingConfiguration) updates) =>
      super.copyWith((message) => updates(message as LoggingConfiguration))
          as LoggingConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LoggingConfiguration create() => LoggingConfiguration._();
  @$core.override
  LoggingConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LoggingConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LoggingConfiguration>(create);
  static LoggingConfiguration? _defaultInstance;

  /// Write logs to the platform-local sink (os_log / Logcat / console).
  @$pb.TagNumber(1)
  $core.bool get enableLocalLogging => $_getBF(0);
  @$pb.TagNumber(1)
  set enableLocalLogging($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEnableLocalLogging() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnableLocalLogging() => $_clearField(1);

  /// Minimum severity emitted. Messages below this level are dropped.
  @$pb.TagNumber(2)
  LogLevel get minLogLevel => $_getN(1);
  @$pb.TagNumber(2)
  set minLogLevel(LogLevel value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasMinLogLevel() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinLogLevel() => $_clearField(2);

  /// Attach file:line:function source location to each record.
  @$pb.TagNumber(3)
  $core.bool get includeSourceLocation => $_getBF(2);
  @$pb.TagNumber(3)
  set includeSourceLocation($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIncludeSourceLocation() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncludeSourceLocation() => $_clearField(3);

  /// Attach device/build metadata (model, os version, app build) to records.
  @$pb.TagNumber(4)
  $core.bool get includeDeviceMetadata => $_getBF(3);
  @$pb.TagNumber(4)
  set includeDeviceMetadata($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIncludeDeviceMetadata() => $_has(3);
  @$pb.TagNumber(4)
  void clearIncludeDeviceMetadata() => $_clearField(4);

  /// Forward records to the remote logging pipeline.
  @$pb.TagNumber(5)
  $core.bool get enableRemoteLogging => $_getBF(4);
  @$pb.TagNumber(5)
  set enableRemoteLogging($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEnableRemoteLogging() => $_has(4);
  @$pb.TagNumber(5)
  void clearEnableRemoteLogging() => $_clearField(5);

  /// Forward error/fatal records to Sentry.
  @$pb.TagNumber(6)
  $core.bool get enableSentryLogging => $_getBF(5);
  @$pb.TagNumber(6)
  set enableSentryLogging($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEnableSentryLogging() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnableSentryLogging() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// A single structured log record. Mirrors the per-SDK LogEntry shape.
/// ---------------------------------------------------------------------------
class LogEntry extends $pb.GeneratedMessage {
  factory LogEntry({
    $fixnum.Int64? timestampUnixMs,
    LogLevel? level,
    $core.String? category,
    $core.String? message,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.String? file,
    $core.int? line,
    $core.String? function,
    $core.int? errorCode,
    $core.String? modelId,
    $core.String? framework,
  }) {
    final result = create();
    if (timestampUnixMs != null) result.timestampUnixMs = timestampUnixMs;
    if (level != null) result.level = level;
    if (category != null) result.category = category;
    if (message != null) result.message = message;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (file != null) result.file = file;
    if (line != null) result.line = line;
    if (function != null) result.function = function;
    if (errorCode != null) result.errorCode = errorCode;
    if (modelId != null) result.modelId = modelId;
    if (framework != null) result.framework = framework;
    return result;
  }

  LogEntry._();

  factory LogEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LogEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LogEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'timestampUnixMs')
    ..aE<LogLevel>(2, _omitFieldNames ? '' : 'level',
        enumValues: LogLevel.values)
    ..aOS(3, _omitFieldNames ? '' : 'category')
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'LogEntry.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(6, _omitFieldNames ? '' : 'file')
    ..aI(7, _omitFieldNames ? '' : 'line')
    ..aOS(8, _omitFieldNames ? '' : 'function')
    ..aI(9, _omitFieldNames ? '' : 'errorCode')
    ..aOS(10, _omitFieldNames ? '' : 'modelId')
    ..aOS(11, _omitFieldNames ? '' : 'framework')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LogEntry copyWith(void Function(LogEntry) updates) =>
      super.copyWith((message) => updates(message as LogEntry)) as LogEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LogEntry create() => LogEntry._();
  @$core.override
  LogEntry createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LogEntry getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LogEntry>(create);
  static LogEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get timestampUnixMs => $_getI64(0);
  @$pb.TagNumber(1)
  set timestampUnixMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestampUnixMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestampUnixMs() => $_clearField(1);

  @$pb.TagNumber(2)
  LogLevel get level => $_getN(1);
  @$pb.TagNumber(2)
  set level(LogLevel value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasLevel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLevel() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get category => $_getSZ(2);
  @$pb.TagNumber(3)
  set category($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCategory() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategory() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);

  /// Optional source location + context (Kotlin LogEntry carries these as
  /// first-class fields; other SDKs leave them empty). `line`/`error_code`
  /// use 0 as "unset".
  @$pb.TagNumber(6)
  $core.String get file => $_getSZ(5);
  @$pb.TagNumber(6)
  set file($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFile() => $_has(5);
  @$pb.TagNumber(6)
  void clearFile() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get line => $_getIZ(6);
  @$pb.TagNumber(7)
  set line($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLine() => $_has(6);
  @$pb.TagNumber(7)
  void clearLine() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get function => $_getSZ(7);
  @$pb.TagNumber(8)
  set function($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFunction() => $_has(7);
  @$pb.TagNumber(8)
  void clearFunction() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get errorCode => $_getIZ(8);
  @$pb.TagNumber(9)
  set errorCode($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorCode() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorCode() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get modelId => $_getSZ(9);
  @$pb.TagNumber(10)
  set modelId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasModelId() => $_has(9);
  @$pb.TagNumber(10)
  void clearModelId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get framework => $_getSZ(10);
  @$pb.TagNumber(11)
  set framework($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasFramework() => $_has(10);
  @$pb.TagNumber(11)
  void clearFramework() => $_clearField(11);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
