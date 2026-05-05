//
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class LLMStreamEventKind extends $pb.ProtobufEnum {
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_UNSPECIFIED = LLMStreamEventKind._(0, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_UNSPECIFIED');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_STARTED = LLMStreamEventKind._(1, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_STARTED');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_TOKEN = LLMStreamEventKind._(2, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_TOKEN');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_THINKING = LLMStreamEventKind._(3, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_THINKING');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_TOOL_CALL = LLMStreamEventKind._(4, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_TOOL_CALL');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_PROGRESS = LLMStreamEventKind._(5, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_PROGRESS');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_COMPLETED = LLMStreamEventKind._(6, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_COMPLETED');
  static const LLMStreamEventKind LLM_STREAM_EVENT_KIND_ERROR = LLMStreamEventKind._(7, _omitEnumNames ? '' : 'LLM_STREAM_EVENT_KIND_ERROR');

  static const $core.List<LLMStreamEventKind> values = <LLMStreamEventKind> [
    LLM_STREAM_EVENT_KIND_UNSPECIFIED,
    LLM_STREAM_EVENT_KIND_STARTED,
    LLM_STREAM_EVENT_KIND_TOKEN,
    LLM_STREAM_EVENT_KIND_THINKING,
    LLM_STREAM_EVENT_KIND_TOOL_CALL,
    LLM_STREAM_EVENT_KIND_PROGRESS,
    LLM_STREAM_EVENT_KIND_COMPLETED,
    LLM_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.Map<$core.int, LLMStreamEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static LLMStreamEventKind? valueOf($core.int value) => _byValue[value];

  const LLMStreamEventKind._($core.int v, $core.String n) : super(v, n);
}

class LLMTokenKind extends $pb.ProtobufEnum {
  static const LLMTokenKind LLM_TOKEN_KIND_UNSPECIFIED = LLMTokenKind._(0, _omitEnumNames ? '' : 'LLM_TOKEN_KIND_UNSPECIFIED');
  static const LLMTokenKind LLM_TOKEN_KIND_ANSWER = LLMTokenKind._(1, _omitEnumNames ? '' : 'LLM_TOKEN_KIND_ANSWER');
  static const LLMTokenKind LLM_TOKEN_KIND_THOUGHT = LLMTokenKind._(2, _omitEnumNames ? '' : 'LLM_TOKEN_KIND_THOUGHT');
  static const LLMTokenKind LLM_TOKEN_KIND_TOOL_CALL = LLMTokenKind._(3, _omitEnumNames ? '' : 'LLM_TOKEN_KIND_TOOL_CALL');

  static const $core.List<LLMTokenKind> values = <LLMTokenKind> [
    LLM_TOKEN_KIND_UNSPECIFIED,
    LLM_TOKEN_KIND_ANSWER,
    LLM_TOKEN_KIND_THOUGHT,
    LLM_TOKEN_KIND_TOOL_CALL,
  ];

  static final $core.Map<$core.int, LLMTokenKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static LLMTokenKind? valueOf($core.int value) => _byValue[value];

  const LLMTokenKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
