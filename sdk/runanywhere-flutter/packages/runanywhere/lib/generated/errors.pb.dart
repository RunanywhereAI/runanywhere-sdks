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

/// The unified error payload every SDK throws or returns.
///
/// `code` is always non-zero: an SDKError implies failure, and success is
/// signalled by its absence. `message` is non-localized; localization is a
/// consumer concern. Stack traces are deliberately absent: they are
/// platform-shaped and belong in platform-local logging.
class SDKError extends $pb.GeneratedMessage {
  factory SDKError({
    ErrorCode? code,
    ErrorCategory? category,
    $core.String? message,
    $core.int? cAbiCode,
    $core.String? nestedMessage,
    $fixnum.Int64? timestampMs,
    ErrorSeverity? severity,
    $core.String? component,
    $core.bool? retryable,
    $core.String? requestId,
    $core.String? param,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (category != null) result.category = category;
    if (message != null) result.message = message;
    if (cAbiCode != null) result.cAbiCode = cAbiCode;
    if (nestedMessage != null) result.nestedMessage = nestedMessage;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (severity != null) result.severity = severity;
    if (component != null) result.component = component;
    if (retryable != null) result.retryable = retryable;
    if (requestId != null) result.requestId = requestId;
    if (param != null) result.param = param;
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
    ..aI(4, _omitFieldNames ? '' : 'cAbiCode')
    ..aOS(5, _omitFieldNames ? '' : 'nestedMessage')
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..aE<ErrorSeverity>(7, _omitFieldNames ? '' : 'severity',
        enumValues: ErrorSeverity.values)
    ..aOS(8, _omitFieldNames ? '' : 'component')
    ..aOB(9, _omitFieldNames ? '' : 'retryable')
    ..aOS(10, _omitFieldNames ? '' : 'requestId')
    ..aOS(11, _omitFieldNames ? '' : 'param')
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

  /// Signed rac_result_t. Equals -code for codes <= 899. Unset for the
  /// Web-only WASM codes (>= 900), which have no C ABI counterpart, and for
  /// failures originating outside the C ABI.
  @$pb.TagNumber(4)
  $core.int get cAbiCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set cAbiCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCAbiCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearCAbiCode() => $_clearField(4);

  /// The "caused by" chain.
  @$pb.TagNumber(5)
  $core.String get nestedMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set nestedMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNestedMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearNestedMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestampMs() => $_clearField(6);

  @$pb.TagNumber(7)
  ErrorSeverity get severity => $_getN(6);
  @$pb.TagNumber(7)
  set severity(ErrorSeverity value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasSeverity() => $_has(6);
  @$pb.TagNumber(7)
  void clearSeverity() => $_clearField(7);

  /// Which subsystem raised the error, written as SDKComponent's
  /// rac_wire_string ("llm", "stt", "rag", "rerank"). Producers MUST write
  /// the wire string, never the proto constant name. Errors raised outside
  /// any SDKComponent may carry their own lowercase key.
  @$pb.TagNumber(8)
  $core.String get component => $_getSZ(7);
  @$pb.TagNumber(8)
  set component($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasComponent() => $_has(7);
  @$pb.TagNumber(8)
  void clearComponent() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get retryable => $_getBF(8);
  @$pb.TagNumber(9)
  set retryable($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasRetryable() => $_has(8);
  @$pb.TagNumber(9)
  void clearRetryable() => $_clearField(9);

  /// Ties this failure to the operation that produced it. Named for
  /// Anthropic's body-level `request_id`. Producers MUST set it.
  @$pb.TagNumber(10)
  $core.String get requestId => $_getSZ(9);
  @$pb.TagNumber(10)
  set requestId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRequestId() => $_has(9);
  @$pb.TagNumber(10)
  void clearRequestId() => $_clearField(10);

  /// "<Message>.<field>" for validation errors, e.g. "STTOptions.sampleRate".
  /// OpenAI's `param`. The generated validate() emits this.
  @$pb.TagNumber(11)
  $core.String get param => $_getSZ(10);
  @$pb.TagNumber(11)
  set param($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasParam() => $_has(10);
  @$pb.TagNumber(11)
  void clearParam() => $_clearField(11);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
