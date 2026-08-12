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

/// Conversational role of one prior turn in `history`.
class ToolCallingRole extends $pb.ProtobufEnum {
  static const ToolCallingRole TOOL_CALLING_ROLE_UNSPECIFIED =
      ToolCallingRole._(
          0, _omitEnumNames ? '' : 'TOOL_CALLING_ROLE_UNSPECIFIED');
  static const ToolCallingRole TOOL_CALLING_ROLE_USER =
      ToolCallingRole._(1, _omitEnumNames ? '' : 'TOOL_CALLING_ROLE_USER');
  static const ToolCallingRole TOOL_CALLING_ROLE_ASSISTANT =
      ToolCallingRole._(2, _omitEnumNames ? '' : 'TOOL_CALLING_ROLE_ASSISTANT');
  static const ToolCallingRole TOOL_CALLING_ROLE_SYSTEM =
      ToolCallingRole._(3, _omitEnumNames ? '' : 'TOOL_CALLING_ROLE_SYSTEM');

  static const $core.List<ToolCallingRole> values = <ToolCallingRole>[
    TOOL_CALLING_ROLE_UNSPECIFIED,
    TOOL_CALLING_ROLE_USER,
    TOOL_CALLING_ROLE_ASSISTANT,
    TOOL_CALLING_ROLE_SYSTEM,
  ];

  static final $core.List<ToolCallingRole?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ToolCallingRole? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ToolCallingRole._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
