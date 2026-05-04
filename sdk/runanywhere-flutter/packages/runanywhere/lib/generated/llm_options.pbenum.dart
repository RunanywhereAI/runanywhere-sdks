//
//  Generated code. Do not modify.
//  source: llm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Routing destination for a generation (Web SDK ExecutionTarget in
/// types/models.ts:79). Drives the cloud-vs-on-device dispatcher.
/// ---------------------------------------------------------------------------
class ExecutionTarget extends $pb.ProtobufEnum {
  static const ExecutionTarget EXECUTION_TARGET_UNSPECIFIED = ExecutionTarget._(0, _omitEnumNames ? '' : 'EXECUTION_TARGET_UNSPECIFIED');
  static const ExecutionTarget EXECUTION_TARGET_ON_DEVICE = ExecutionTarget._(1, _omitEnumNames ? '' : 'EXECUTION_TARGET_ON_DEVICE');
  static const ExecutionTarget EXECUTION_TARGET_CLOUD = ExecutionTarget._(2, _omitEnumNames ? '' : 'EXECUTION_TARGET_CLOUD');
  static const ExecutionTarget EXECUTION_TARGET_AUTO = ExecutionTarget._(3, _omitEnumNames ? '' : 'EXECUTION_TARGET_AUTO');

  static const $core.List<ExecutionTarget> values = <ExecutionTarget> [
    EXECUTION_TARGET_UNSPECIFIED,
    EXECUTION_TARGET_ON_DEVICE,
    EXECUTION_TARGET_CLOUD,
    EXECUTION_TARGET_AUTO,
  ];

  static final $core.Map<$core.int, ExecutionTarget> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ExecutionTarget? valueOf($core.int value) => _byValue[value];

  const ExecutionTarget._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
