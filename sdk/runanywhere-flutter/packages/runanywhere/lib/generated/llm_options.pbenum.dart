///
//  Generated code. Do not modify.
//  source: llm_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class ExecutionTarget extends $pb.ProtobufEnum {
  static const ExecutionTarget EXECUTION_TARGET_UNSPECIFIED = ExecutionTarget._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EXECUTION_TARGET_UNSPECIFIED');
  static const ExecutionTarget EXECUTION_TARGET_ON_DEVICE = ExecutionTarget._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EXECUTION_TARGET_ON_DEVICE');
  static const ExecutionTarget EXECUTION_TARGET_CLOUD = ExecutionTarget._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EXECUTION_TARGET_CLOUD');
  static const ExecutionTarget EXECUTION_TARGET_AUTO = ExecutionTarget._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EXECUTION_TARGET_AUTO');

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

