// This is a generated file - do not edit.
//
// Generated from llm_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class ExecutionTarget extends $pb.ProtobufEnum {
  static const ExecutionTarget EXECUTION_TARGET_UNSPECIFIED = ExecutionTarget._(
      0, _omitEnumNames ? '' : 'EXECUTION_TARGET_UNSPECIFIED');
  static const ExecutionTarget EXECUTION_TARGET_ON_DEVICE =
      ExecutionTarget._(1, _omitEnumNames ? '' : 'EXECUTION_TARGET_ON_DEVICE');
  static const ExecutionTarget EXECUTION_TARGET_CLOUD =
      ExecutionTarget._(2, _omitEnumNames ? '' : 'EXECUTION_TARGET_CLOUD');
  static const ExecutionTarget EXECUTION_TARGET_AUTO =
      ExecutionTarget._(3, _omitEnumNames ? '' : 'EXECUTION_TARGET_AUTO');

  static const $core.List<ExecutionTarget> values = <ExecutionTarget>[
    EXECUTION_TARGET_UNSPECIFIED,
    EXECUTION_TARGET_ON_DEVICE,
    EXECUTION_TARGET_CLOUD,
    EXECUTION_TARGET_AUTO,
  ];

  static final $core.List<ExecutionTarget?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ExecutionTarget? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ExecutionTarget._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
