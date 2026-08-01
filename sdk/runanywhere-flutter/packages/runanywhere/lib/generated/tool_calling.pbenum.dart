// This is a generated file - do not edit.
//
// Generated from tool_calling.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Supported parameter types.
/// ---------------------------------------------------------------------------
class ToolParameterType extends $pb.ProtobufEnum {
  static const ToolParameterType TOOL_PARAMETER_TYPE_UNSPECIFIED =
      ToolParameterType._(
          0, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_UNSPECIFIED');
  static const ToolParameterType TOOL_PARAMETER_TYPE_STRING =
      ToolParameterType._(
          1, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_STRING');
  static const ToolParameterType TOOL_PARAMETER_TYPE_NUMBER =
      ToolParameterType._(
          2, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_NUMBER');
  static const ToolParameterType TOOL_PARAMETER_TYPE_BOOLEAN =
      ToolParameterType._(
          3, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_BOOLEAN');
  static const ToolParameterType TOOL_PARAMETER_TYPE_OBJECT =
      ToolParameterType._(
          4, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_OBJECT');
  static const ToolParameterType TOOL_PARAMETER_TYPE_ARRAY =
      ToolParameterType._(5, _omitEnumNames ? '' : 'TOOL_PARAMETER_TYPE_ARRAY');

  static const $core.List<ToolParameterType> values = <ToolParameterType>[
    TOOL_PARAMETER_TYPE_UNSPECIFIED,
    TOOL_PARAMETER_TYPE_STRING,
    TOOL_PARAMETER_TYPE_NUMBER,
    TOOL_PARAMETER_TYPE_BOOLEAN,
    TOOL_PARAMETER_TYPE_OBJECT,
    TOOL_PARAMETER_TYPE_ARRAY,
  ];

  static final $core.List<ToolParameterType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ToolParameterType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ToolParameterType._(super.value, super.name);
}

/// ---------------------------------------------------------------------------
/// Tool-call wire formats various LLM families emit. This enum is the single
/// portable format selector across commons and every generated SDK binding.
/// ---------------------------------------------------------------------------
class ToolCallFormatName extends $pb.ProtobufEnum {
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_UNSPECIFIED =
      ToolCallFormatName._(
          0, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_UNSPECIFIED');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_JSON =
      ToolCallFormatName._(
          1, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_JSON');
  static const ToolCallFormatName TOOL_CALL_FORMAT_NAME_LFM2 =
      ToolCallFormatName._(
          7, _omitEnumNames ? '' : 'TOOL_CALL_FORMAT_NAME_LFM2');

  static const $core.List<ToolCallFormatName> values = <ToolCallFormatName>[
    TOOL_CALL_FORMAT_NAME_UNSPECIFIED,
    TOOL_CALL_FORMAT_NAME_JSON,
    TOOL_CALL_FORMAT_NAME_LFM2,
  ];

  static final $core.Map<$core.int, ToolCallFormatName> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static ToolCallFormatName? valueOf($core.int value) => _byValue[value];

  const ToolCallFormatName._(super.value, super.name);
}

class ToolChoiceMode extends $pb.ProtobufEnum {
  static const ToolChoiceMode TOOL_CHOICE_MODE_UNSPECIFIED =
      ToolChoiceMode._(0, _omitEnumNames ? '' : 'TOOL_CHOICE_MODE_UNSPECIFIED');
  static const ToolChoiceMode TOOL_CHOICE_MODE_AUTO =
      ToolChoiceMode._(1, _omitEnumNames ? '' : 'TOOL_CHOICE_MODE_AUTO');
  static const ToolChoiceMode TOOL_CHOICE_MODE_NONE =
      ToolChoiceMode._(2, _omitEnumNames ? '' : 'TOOL_CHOICE_MODE_NONE');
  static const ToolChoiceMode TOOL_CHOICE_MODE_REQUIRED =
      ToolChoiceMode._(3, _omitEnumNames ? '' : 'TOOL_CHOICE_MODE_REQUIRED');
  static const ToolChoiceMode TOOL_CHOICE_MODE_SPECIFIC =
      ToolChoiceMode._(4, _omitEnumNames ? '' : 'TOOL_CHOICE_MODE_SPECIFIC');

  static const $core.List<ToolChoiceMode> values = <ToolChoiceMode>[
    TOOL_CHOICE_MODE_UNSPECIFIED,
    TOOL_CHOICE_MODE_AUTO,
    TOOL_CHOICE_MODE_NONE,
    TOOL_CHOICE_MODE_REQUIRED,
    TOOL_CHOICE_MODE_SPECIFIC,
  ];

  static final $core.List<ToolChoiceMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static ToolChoiceMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ToolChoiceMode._(super.value, super.name);
}

class ToolCallingStreamEventKind extends $pb.ProtobufEnum {
  static const ToolCallingStreamEventKind
      TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED = ToolCallingStreamEventKind._(
          0,
          _omitEnumNames ? '' : 'TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED');
  static const ToolCallingStreamEventKind
      TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN = ToolCallingStreamEventKind._(
          1,
          _omitEnumNames ? '' : 'TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN');
  static const ToolCallingStreamEventKind
      TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED =
      ToolCallingStreamEventKind._(
          2,
          _omitEnumNames
              ? ''
              : 'TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED');
  static const ToolCallingStreamEventKind
      TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED =
      ToolCallingStreamEventKind._(
          3,
          _omitEnumNames
              ? ''
              : 'TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED');
  static const ToolCallingStreamEventKind
      TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED =
      ToolCallingStreamEventKind._(
          4,
          _omitEnumNames
              ? ''
              : 'TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED');
  static const ToolCallingStreamEventKind
      TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED = ToolCallingStreamEventKind._(
          5, _omitEnumNames ? '' : 'TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED');
  static const ToolCallingStreamEventKind TOOL_CALLING_STREAM_EVENT_KIND_ERROR =
      ToolCallingStreamEventKind._(
          6, _omitEnumNames ? '' : 'TOOL_CALLING_STREAM_EVENT_KIND_ERROR');

  static const $core.List<ToolCallingStreamEventKind> values =
      <ToolCallingStreamEventKind>[
    TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED,
    TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN,
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED,
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED,
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED,
    TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED,
    TOOL_CALLING_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<ToolCallingStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static ToolCallingStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ToolCallingStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
