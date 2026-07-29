// This is a generated file - do not edit.
//
// Generated from thinking_tag_pattern.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// The single home for reasoning/thinking control. Replaces the retired
/// per-message toggles (LLMGenerationOptions.disable_thinking,
/// ToolCallingOptions.disable_thinking, RAGQueryOptions.disable_thinking,
/// ToolCallingSessionCreateRequest.disable_thinking,
/// LLMGenerateRequest.emit_thoughts). Referenced from LLM and VLM generation
/// options; every composed surface (tool calling, RAG, voice agent) inherits
/// it through the embedded LLMGenerationOptions.
/// ---------------------------------------------------------------------------
class ReasoningMode extends $pb.ProtobufEnum {
  /// Model default: reasoning-capable models think, others don't.
  static const ReasoningMode REASONING_MODE_UNSPECIFIED =
      ReasoningMode._(0, _omitEnumNames ? '' : 'REASONING_MODE_UNSPECIFIED');

  /// Suppress the thinking phase (commons applies the model's no-think
  /// directive at the prompt level).
  static const ReasoningMode REASONING_MODE_OFF =
      ReasoningMode._(1, _omitEnumNames ? '' : 'REASONING_MODE_OFF');

  /// Request the thinking phase on models where it is optional.
  static const ReasoningMode REASONING_MODE_ON =
      ReasoningMode._(2, _omitEnumNames ? '' : 'REASONING_MODE_ON');

  static const $core.List<ReasoningMode> values = <ReasoningMode>[
    REASONING_MODE_UNSPECIFIED,
    REASONING_MODE_OFF,
    REASONING_MODE_ON,
  ];

  static final $core.List<ReasoningMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ReasoningMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReasoningMode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
