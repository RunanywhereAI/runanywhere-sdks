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

/// ---------------------------------------------------------------------------
/// ErrorContext — debugging metadata captured at the throw site.
///
/// Sources pre-IDL:
///   C ABI   rac_structured_error.h:102  rac_error_t fields source_file,
///                                       source_line, source_function plus a
///                                       rac_stack_frame_t[32] fixed-size
///                                       stack capture and 3 custom k/v slots
///                                       (custom_key1..3 / custom_value1..3).
///                                       The fixed-shape custom slots flatten
///                                       to a `metadata` map<string,string> in
///                                       proto.
///   Swift   ErrorContext.swift          (matches Dart equivalent).
///   Kotlin  SDKError.kt                 No ErrorContext — uses Throwable.cause
///                                       only. Will pick up source location
///                                       from this proto on regeneration.
///   Dart    error_context.dart:4        StackTrace? stackTrace, String file,
///                                       int line, String function, DateTime
///                                       timestamp, String threadInfo.
///   RN      ErrorContext.ts:11          stackTrace[], file, line, function,
///                                       timestamp, threadInfo.
///   Web     ErrorTypes.ts               (no context type).
///
/// Stack traces are intentionally NOT modeled here — they are platform-shaped
/// (string lines on RN/Dart, rac_stack_frame_t[] on C, StackTrace on Dart) and
/// belong in a platform-local logging path, not in the wire IDL. If the C ABI
/// ever ships symbolicated frames, add a `repeated StackFrame frames` field
/// guarded by a feature flag.
/// ---------------------------------------------------------------------------
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

  /// Free-form key/value pairs for telemetry tagging. Maps onto the C ABI's
  /// three custom_key/custom_value slots and Dart's `Map<String, dynamic>`
  /// (after string-coercion).
  @$pb.TagNumber(1)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(0);

  /// __FILE__ at the throw site. C ABI cap is RAC_MAX_METADATA_STRING (256).
  @$pb.TagNumber(2)
  $core.String get sourceFile => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceFile($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceFile() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceFile() => $_clearField(2);

  /// __LINE__ at the throw site.
  @$pb.TagNumber(3)
  $core.int get sourceLine => $_getIZ(2);
  @$pb.TagNumber(3)
  set sourceLine($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceLine() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceLine() => $_clearField(3);

  /// Logical operation name ("loadModel", "generate", "transcribeStream",
  /// ...). Lets clients route on operation without parsing free-text.
  /// Maps roughly onto Dart's `function` field and C ABI's source_function;
  /// we use the more generic "operation" name because some platforms (C++,
  /// Swift) symbolicate the function name from the stack frame instead.
  @$pb.TagNumber(4)
  $core.String get operation => $_getSZ(3);
  @$pb.TagNumber(4)
  set operation($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOperation() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperation() => $_clearField(4);

  /// The structured field path a validation error refers to
  /// ("<Message>.<field>"). First-class replacement for the
  /// metadata["field_path"] magic key all five SDKs read/write today; the
  /// generated convenience validate() already emits this path.
  @$pb.TagNumber(5)
  $core.String get fieldPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set fieldPath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFieldPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearFieldPath() => $_clearField(5);
}

/// ---------------------------------------------------------------------------
/// SDKError — the unified error payload every SDK throws / returns.
///
/// Sources pre-IDL:
///   C ABI   rac_structured_error.h:102  rac_error_t (code, category, message,
///                                       source location, stack trace,
///                                       underlying_code, underlying_message,
///                                       model_id, framework, session_id,
///                                       timestamp_ms, 3 custom k/v slots).
///   Swift   (no concrete SDKError type was located; Swift code uses
///           ErrorCode + ErrorCategory + a SDKErrorProtocol shape that
///           matches this message; the migrated Swift SDK in sdk/swift/ will
///           be regenerated from this proto).
///   Kotlin  SDKError.kt:27              data class (code, category, message,
///                                       cause).
///   Dart    sdk_error.dart:13           class SDKError (message, type,
///                                       underlyingError, context).
///   RN      SDKError.ts:147             class SDKError (code, legacyCode?,
///                                       category, underlyingError, context,
///                                       details?).
///   Web     ErrorTypes.ts:68            class SDKError (code, details?).
///
/// Wire contract:
///   * `code` — required. Always non-zero (zero indicates success and there
///     should be no SDKError to begin with). Codegen MUST refuse to emit
///     ERROR_CODE_UNSPECIFIED at runtime.
///   * `category` — required. Coarse routing bucket. May be UNSPECIFIED only
///     when `code` itself doesn't fit any bucket cleanly (rare).
///   * `message` — required, human-readable, non-localized. Localization is a
///     consumer concern.
///   * `context` — optional. Source location + telemetry metadata.
///   * `c_abi_code` — optional. Negative `rac_result_t` integer from the C ABI
///     (e.g. -110 for MODEL_NOT_FOUND). Allows lossless round-trip with the
///     C ABI even when intermediate platforms (Kotlin, Dart, RN) use a
///     positive-numbered local enum. If `code` is set, `c_abi_code` MUST
///     equal `-int32(code)` for codes ≤ 899; for the Web-only WASM codes
///     (≥ 900) `c_abi_code` is unset because no canonical C ABI value exists.
///   * `nested_message` — optional. Underlying-error message as captured at
///     wrap time. Mirrors Swift's RunAnywhereError.underlyingError.localizedDesc
///     and Kotlin's Throwable.cause.message.
///   * `retryable` — canonical retry hint. This is business-policy metadata
///     owned by the portable layer; the platform adapter still decides how to
///     schedule the retry through native/background APIs when appropriate.
///   * `correlation_id` — stable cross-event/request correlation key. SDKEvent
///     also carries this field so callers can join success/progress/failure
///     events without parsing free-form properties.
/// ---------------------------------------------------------------------------
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

  /// Negative rac_result_t value from the C ABI. May be negative; preserved
  /// via int32 (proto3 int32 is signed). Unset when the failure originated
  /// outside the C ABI (e.g. a pure-Web WASM failure).
  @$pb.TagNumber(5)
  $core.int get cAbiCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set cAbiCode($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCAbiCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearCAbiCode() => $_clearField(5);

  /// Underlying error's message (the "caused by" chain), if any.
  @$pb.TagNumber(6)
  $core.String get nestedMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set nestedMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNestedMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearNestedMessage() => $_clearField(6);

  /// Envelope metadata for canonical error emission. `component` is a stable
  /// lowercase component key ("llm", "stt", "tts", "vad", "vlm", "rag",
  /// "download", "storage", ...); SDKEvent carries the enum-typed component.
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
