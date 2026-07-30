// This is a generated file - do not edit.
//
// Generated from errors.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'errors.pbenum.dart';

/// Debugging metadata captured at the throw site. Stack traces are deliberately
/// absent: they are platform-shaped and belong in platform-local logging.
class ErrorContext extends $pb.GeneratedMessage {
  factory ErrorContext({
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.String? sourceFile,
    $core.int? sourceLine,
    $core.String? operation,
    $core.String? fieldPath,
  }) {
    final result = create();
    if (metadata != null) result.metadata.addEntries(metadata);
    if (sourceFile != null) result.sourceFile = sourceFile;
    if (sourceLine != null) result.sourceLine = sourceLine;
    if (operation != null) result.operation = operation;
    if (fieldPath != null) result.fieldPath = fieldPath;
    return result;
  }

  ErrorContext._();

  factory ErrorContext.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ErrorContext.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorContext',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..m<$core.String, $core.String>(1, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ErrorContext.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(2, _omitFieldNames ? '' : 'sourceFile')
    ..aI(3, _omitFieldNames ? '' : 'sourceLine')
    ..aOS(4, _omitFieldNames ? '' : 'operation')
    ..aOS(5, _omitFieldNames ? '' : 'fieldPath')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorContext clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorContext copyWith(void Function(ErrorContext) updates) =>
      super.copyWith((message) => updates(message as ErrorContext))
          as ErrorContext;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ErrorContext create() => ErrorContext._();
  @$core.override
  ErrorContext createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ErrorContext getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ErrorContext>(create);
  static ErrorContext? _defaultInstance;

  /// Telemetry tagging.
  @$pb.TagNumber(1)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(0);

  @$pb.TagNumber(2)
  $core.String get sourceFile => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceFile($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceFile() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceFile() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get sourceLine => $_getIZ(2);
  @$pb.TagNumber(3)
  set sourceLine($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceLine() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceLine() => $_clearField(3);

  /// Logical operation ("loadModel", "generate", "transcribeStream"), so
  /// clients can route without parsing free text.
  @$pb.TagNumber(4)
  $core.String get operation => $_getSZ(3);
  @$pb.TagNumber(4)
  set operation($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOperation() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperation() => $_clearField(4);

  /// "<Message>.<field>" for validation errors. The generated validate()
  /// emits this.
  @$pb.TagNumber(5)
  $core.String get fieldPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set fieldPath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFieldPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearFieldPath() => $_clearField(5);
}

/// The unified error payload every SDK throws or returns.
///
/// `code` is always non-zero: an SDKError implies failure, and success is
/// signalled by its absence. `message` is non-localized; localization is a
/// consumer concern.
class SDKError extends $pb.GeneratedMessage {
  factory SDKError({
    ErrorCode? code,
    ErrorCategory? category,
    $core.String? message,
    ErrorContext? context,
    $core.int? cAbiCode,
    $core.String? nestedMessage,
    $fixnum.Int64? timestampMs,
    ErrorSeverity? severity,
    $core.String? component,
    $core.bool? retryable,
    $core.String? remediationHint,
    $core.String? correlationId,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (category != null) result.category = category;
    if (message != null) result.message = message;
    if (context != null) result.context = context;
    if (cAbiCode != null) result.cAbiCode = cAbiCode;
    if (nestedMessage != null) result.nestedMessage = nestedMessage;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (severity != null) result.severity = severity;
    if (component != null) result.component = component;
    if (retryable != null) result.retryable = retryable;
    if (remediationHint != null) result.remediationHint = remediationHint;
    if (correlationId != null) result.correlationId = correlationId;
    return result;
  }

  SDKError._();

  factory SDKError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ErrorCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: ErrorCode.values)
    ..aE<ErrorCategory>(2, _omitFieldNames ? '' : 'category',
        enumValues: ErrorCategory.values)
    ..aOS(3, _omitFieldNames ? '' : 'message')
    ..aOM<ErrorContext>(4, _omitFieldNames ? '' : 'context',
        subBuilder: ErrorContext.create)
    ..aI(5, _omitFieldNames ? '' : 'cAbiCode')
    ..aOS(6, _omitFieldNames ? '' : 'nestedMessage')
    ..aInt64(7, _omitFieldNames ? '' : 'timestampMs')
    ..aE<ErrorSeverity>(8, _omitFieldNames ? '' : 'severity',
        enumValues: ErrorSeverity.values)
    ..aOS(9, _omitFieldNames ? '' : 'component')
    ..aOB(10, _omitFieldNames ? '' : 'retryable')
    ..aOS(11, _omitFieldNames ? '' : 'remediationHint')
    ..aOS(12, _omitFieldNames ? '' : 'correlationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKError copyWith(void Function(SDKError) updates) =>
      super.copyWith((message) => updates(message as SDKError)) as SDKError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKError create() => SDKError._();
  @$core.override
  SDKError createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKError getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SDKError>(create);
  static SDKError? _defaultInstance;

  @$pb.TagNumber(1)
  ErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(ErrorCode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  ErrorCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ErrorCategory value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  ErrorContext get context => $_getN(3);
  @$pb.TagNumber(4)
  set context(ErrorContext value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasContext() => $_has(3);
  @$pb.TagNumber(4)
  void clearContext() => $_clearField(4);
  @$pb.TagNumber(4)
  ErrorContext ensureContext() => $_ensure(3);

  /// Signed rac_result_t. Equals -code for codes <= 899. Unset for the
  /// Web-only WASM codes (>= 900), which have no C ABI counterpart, and for
  /// failures originating outside the C ABI.
  @$pb.TagNumber(5)
  $core.int get cAbiCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set cAbiCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCAbiCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearCAbiCode() => $_clearField(5);

  /// The "caused by" chain.
  @$pb.TagNumber(6)
  $core.String get nestedMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set nestedMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNestedMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearNestedMessage() => $_clearField(6);

  /// `component` is a stable lowercase key ("llm", "stt", "rag", "download").
  /// SDKEvent carries the enum-typed component instead.
  @$pb.TagNumber(7)
  $fixnum.Int64 get timestampMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timestampMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTimestampMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimestampMs() => $_clearField(7);

  @$pb.TagNumber(8)
  ErrorSeverity get severity => $_getN(7);
  @$pb.TagNumber(8)
  set severity(ErrorSeverity value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasSeverity() => $_has(7);
  @$pb.TagNumber(8)
  void clearSeverity() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get component => $_getSZ(8);
  @$pb.TagNumber(9)
  set component($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasComponent() => $_has(8);
  @$pb.TagNumber(9)
  void clearComponent() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get retryable => $_getBF(9);
  @$pb.TagNumber(10)
  set retryable($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRetryable() => $_has(9);
  @$pb.TagNumber(10)
  void clearRetryable() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get remediationHint => $_getSZ(10);
  @$pb.TagNumber(11)
  set remediationHint($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasRemediationHint() => $_has(10);
  @$pb.TagNumber(11)
  void clearRemediationHint() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get correlationId => $_getSZ(11);
  @$pb.TagNumber(12)
  set correlationId($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasCorrelationId() => $_has(11);
  @$pb.TagNumber(12)
  void clearCorrelationId() => $_clearField(12);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
