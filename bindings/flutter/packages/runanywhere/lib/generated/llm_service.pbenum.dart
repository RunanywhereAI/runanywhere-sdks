// This is a generated file - do not edit.
//
// Generated from llm_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class LLMStreamEventKind extends $pb.ProtobufEnum {
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_UNSPECIFIED =
      LLMStreamEventKind._(
          0, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_UNSPECIFIED');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_STARTED =
      LLMStreamEventKind._(
          1, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_STARTED');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_TOKEN =
      LLMStreamEventKind._(
          2, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_TOKEN');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_THINKING =
      LLMStreamEventKind._(
          3, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_THINKING');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_TOOL_CALL =
      LLMStreamEventKind._(
          4, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_TOOL_CALL');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_PROGRESS =
      LLMStreamEventKind._(
          5, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_PROGRESS');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_COMPLETED =
      LLMStreamEventKind._(
          6, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_COMPLETED');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_ERROR =
      LLMStreamEventKind._(
          7, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_ERROR');

  static const $core.List<LLMStreamEventKind> values = <LLMStreamEventKind>[
    LLM_STREAM_EVENT_KIND_UNSPECIFIED,
    LLM_STREAM_EVENT_KIND_STARTED,
    LLM_STREAM_EVENT_KIND_TOKEN,
    LLM_STREAM_EVENT_KIND_THINKING,
    LLM_STREAM_EVENT_KIND_TOOL_CALL,
    LLM_STREAM_EVENT_KIND_PROGRESS,
    LLM_STREAM_EVENT_KIND_COMPLETED,
    LLM_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<LLMStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static LLMStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const LLMStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
