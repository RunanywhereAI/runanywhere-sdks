//
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Supported parameter types.
/// ---------------------------------------------------------------------------
class ToolParameterType extends $pb.ProtobufEnum {
  static const ToolParameterType TOOL_PARAMETER_TYPE_UNSPECIFIED = ToolParameterType._(0, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_UNSPECIFIED');
  static const ToolParameterType TOOL_PARAMETER_TYPE_STRING = ToolParameterType._(1, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_STRING');
  static const ToolParameterType TOOL_PARAMETER_TYPE_NUMBER = ToolParameterType._(2, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_NUMBER');
  static const ToolParameterType TOOL_PARAMETER_TYPE_BOOLEAN = ToolParameterType._(3, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_BOOLEAN');
  static const ToolParameterType TOOL_PARAMETER_TYPE_OBJECT = ToolParameterType._(4, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_OBJECT');
  static const ToolParameterType TOOL_PARAMETER_TYPE_ARRAY = ToolParameterType._(5, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_ARRAY');

  static const $core.List<ToolParameterType> values = <ToolParameterType> [
    TOOL_PARAMETER_TYPE_UNSPECIFIED,
    TOOL_PARAMETER_TYPE_STRING,
    TOOL_PARAMETER_TYPE_NUMBER,
    TOOL_PARAMETER_TYPE_BOOLEAN,
    TOOL_PARAMETER_TYPE_OBJECT,
    TOOL_PARAMETER_TYPE_ARRAY,
  ];

  static final $core.Map<$core.int, ToolParameterType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ToolParameterType? valueOf($core.int value) => _byValue[value];

  const ToolParameterType._($core.int v, $core.String n) : super(v, n);
}

///  ---------------------------------------------------------------------------
///  Tool-call wire formats various LLM families emit. Strongly-typed counterpart
///  to `ToolCallingOptions.format_hint` (which remains a free-form string for
///  back-compat — the legacy values "default"/"lfm2"/"openai"/"auto" do not map
///  1:1 to this enum).
///
///  Drift across SDKs:
///    - Swift's `ToolCallFormatName` (Public/Extensions/LLM/ToolCallingTypes.swift)
///      today only exposes `default` and `lfm2` constants on a string-typed
///      field — it is not yet an enum.
///    - Kotlin/RN/Flutter/Web mirror the same string-keyed shape.
///  This enum is the union of formats LLM families actually emit; SDK frontends
///  should map their existing strings onto these values when surfacing the
///  strongly-typed field. Keep `format_hint` (string) populated for legacy
///  consumers until all SDKs migrate.
///  ---------------------------------------------------------------------------
class ToolCallFormatName extends $pb.ProtobufEnum {
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_UNSPECIFIED = ToolCallFormatName._(0, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_UNSPECIFIED');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_JSON = ToolCallFormatName._(1, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_JSON');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_XML = ToolCallFormatName._(2, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_XML');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_NATIVE = ToolCallFormatName._(3, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_NATIVE');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_PYTHONIC = ToolCallFormatName._(4, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_PYTHONIC');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS = ToolCallFormatName._(5, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_HERMES = ToolCallFormatName._(6, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_HERMES');

  static const $core.List<ToolCallFormatName> values = <ToolCallFormatName> [
    TOOL_CALL_FORMAT_NAME_UNSPECIFIED,
    TOOL_CALL_FORMAT_NAME_JSON,
    TOOL_CALL_FORMAT_NAME_XML,
    TOOL_CALL_FORMAT_NAME_NATIVE,
    TOOL_CALL_FORMAT_NAME_PYTHONIC,
    TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS,
    TOOL_CALL_FORMAT_NAME_HERMES,
  ];

  static final $core.Map<$core.int, ToolCallFormatName> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ToolCallFormatName? valueOf($core.int value) => _byValue[value];

  const ToolCallFormatName._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
