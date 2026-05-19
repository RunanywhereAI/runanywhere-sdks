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

class LLMGenerationState extends $pb.ProtobufEnum {
  static const LLMGenerationState LLM_GENERATION_STATE_UNSPECIFIED =
      LLMGenerationState._(
          0, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_UNSPECIFIED');
  static const LLMGenerationState LLM_GENERATION_STATE_QUEUED =
      LLMGenerationState._(
          1, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_QUEUED');
  static const LLMGenerationState LLM_GENERATION_STATE_PREFILLING =
      LLMGenerationState._(
          2, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_PREFILLING');
  static const LLMGenerationState LLM_GENERATION_STATE_DECODING =
      LLMGenerationState._(
          3, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_DECODING');
  static const LLMGenerationState LLM_GENERATION_STATE_TOOL_CALLING =
      LLMGenerationState._(
          4, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_TOOL_CALLING');
  static const LLMGenerationState LLM_GENERATION_STATE_COMPLETED =
      LLMGenerationState._(
          5, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_COMPLETED');
  static const LLMGenerationState LLM_GENERATION_STATE_CANCELLED =
      LLMGenerationState._(
          6, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_CANCELLED');
  static const LLMGenerationState LLM_GENERATION_STATE_FAILED =
      LLMGenerationState._(
          7, _omitEnumNames ? '' : 'LLM_GENERATION_STATE_FAILED');

  static const $core.List<LLMGenerationState> values = <LLMGenerationState>[
    LLM_GENERATION_STATE_UNSPECIFIED,
    LLM_GENERATION_STATE_QUEUED,
    LLM_GENERATION_STATE_PREFILLING,
    LLM_GENERATION_STATE_DECODING,
    LLM_GENERATION_STATE_TOOL_CALLING,
    LLM_GENERATION_STATE_COMPLETED,
    LLM_GENERATION_STATE_CANCELLED,
    LLM_GENERATION_STATE_FAILED,
  ];

  static final $core.List<LLMGenerationState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static LLMGenerationState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LLMGenerationState._(super.value, super.name);
}

/// ---------------------------------------------------------------------------
/// Routing destination for a generation (Web SDK ExecutionTarget in
/// types/models.ts:79). Drives the cloud-vs-on-device dispatcher.
/// ---------------------------------------------------------------------------
class ExecutionTarget extends $pb.ProtobufEnum {
  static const ExecutionTarget EXECUTION_TARGET_UNSPECIFIED = ExecutionTarget._(
      0, _omitEnumNames ? '' : 'EXECUTION_TARGET_UNSPECIFIED');
  static const ExecutionTarget EXECUTION_TARGET_ON_DEVICE =
      ExecutionTarget._(1, _omitEnumNames ? '' : 'EXECUTION_TARGET_ON_DEVICE');
  static const ExecutionTarget EXECUTION_TARGET_CLOUD =
      ExecutionTarget._(2, _omitEnumNames ? '' : 'EXECUTION_TARGET_CLOUD');

  /// Let the SDK decide based on policy (cost, latency, privacy, etc.).
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
