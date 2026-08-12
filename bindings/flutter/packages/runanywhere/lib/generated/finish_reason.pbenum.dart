// This is a generated file - do not edit.
//
// Generated from finish_reason.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// One declared vocabulary, used in every place a finish reason is reported
/// on the LLM generation path (LLMGenerationResult, LLMStreamEvent,
/// ToolCallingResult).
class FinishReason extends $pb.ProtobufEnum {
  static const FinishReason FINISH_REASON_UNSPECIFIED =
      FinishReason._(0, _omitEnumNames ? '' : 'FINISH_REASON_UNSPECIFIED');

  /// End-of-turn token. OpenAI "stop" / Anthropic "end_turn".
  static const FinishReason FINISH_REASON_STOP =
      FinishReason._(1, _omitEnumNames ? '' : 'FINISH_REASON_STOP');

  /// Hit max_output_tokens. OpenAI "length" / Anthropic "max_tokens".
  static const FinishReason FINISH_REASON_LENGTH =
      FinishReason._(2, _omitEnumNames ? '' : 'FINISH_REASON_LENGTH');

  /// One of options.stop_sequences fired; see `stop_sequence`.
  static const FinishReason FINISH_REASON_STOP_SEQUENCE =
      FinishReason._(3, _omitEnumNames ? '' : 'FINISH_REASON_STOP_SEQUENCE');

  /// Model wants a tool run before it can continue.
  static const FinishReason FINISH_REASON_TOOL_CALLS =
      FinishReason._(4, _omitEnumNames ? '' : 'FINISH_REASON_TOOL_CALLS');

  /// Caller cancelled. No cloud analogue.
  static const FinishReason FINISH_REASON_CANCELLED =
      FinishReason._(5, _omitEnumNames ? '' : 'FINISH_REASON_CANCELLED');

  /// Conversation exceeded the allocated context window.
  static const FinishReason FINISH_REASON_CONTEXT_OVERFLOW =
      FinishReason._(6, _omitEnumNames ? '' : 'FINISH_REASON_CONTEXT_OVERFLOW');

  /// Generation failed; see `error`.
  static const FinishReason FINISH_REASON_ERROR =
      FinishReason._(7, _omitEnumNames ? '' : 'FINISH_REASON_ERROR');

  static const $core.List<FinishReason> values = <FinishReason>[
    FINISH_REASON_UNSPECIFIED,
    FINISH_REASON_STOP,
    FINISH_REASON_LENGTH,
    FINISH_REASON_STOP_SEQUENCE,
    FINISH_REASON_TOOL_CALLS,
    FINISH_REASON_CANCELLED,
    FINISH_REASON_CONTEXT_OVERFLOW,
    FINISH_REASON_ERROR,
  ];

  static final $core.List<FinishReason?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static FinishReason? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FinishReason._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
