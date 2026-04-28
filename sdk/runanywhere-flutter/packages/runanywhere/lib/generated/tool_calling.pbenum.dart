///
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class ToolParameterType extends $pb.ProtobufEnum {
  static const ToolParameterType TOOL_PARAMETER_TYPE_UNSPECIFIED = ToolParameterType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_PARAMETER_TYPE_UNSPECIFIED');
  static const ToolParameterType TOOL_PARAMETER_TYPE_STRING = ToolParameterType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_PARAMETER_TYPE_STRING');
  static const ToolParameterType TOOL_PARAMETER_TYPE_NUMBER = ToolParameterType._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_PARAMETER_TYPE_NUMBER');
  static const ToolParameterType TOOL_PARAMETER_TYPE_BOOLEAN = ToolParameterType._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_PARAMETER_TYPE_BOOLEAN');
  static const ToolParameterType TOOL_PARAMETER_TYPE_OBJECT = ToolParameterType._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_PARAMETER_TYPE_OBJECT');
  static const ToolParameterType TOOL_PARAMETER_TYPE_ARRAY = ToolParameterType._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_PARAMETER_TYPE_ARRAY');

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

class ToolCallFormatName extends $pb.ProtobufEnum {
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_UNSPECIFIED = ToolCallFormatName._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_UNSPECIFIED');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_JSON = ToolCallFormatName._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_JSON');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_XML = ToolCallFormatName._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_XML');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_NATIVE = ToolCallFormatName._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_NATIVE');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_PYTHONIC = ToolCallFormatName._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_PYTHONIC');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS = ToolCallFormatName._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_HERMES = ToolCallFormatName._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'TOOL_CALL_FORMAT_NAME_HERMES');

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

