///
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class LLMTokenKind extends $pb.ProtobufEnum {
  static const LLMTokenKind LLM_TOKEN_KIND_UNSPECIFIED = LLMTokenKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'LLM_TOKEN_KIND_UNSPECIFIED');
  static const LLMTokenKind LLM_TOKEN_KIND_ANSWER = LLMTokenKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'LLM_TOKEN_KIND_ANSWER');
  static const LLMTokenKind LLM_TOKEN_KIND_THOUGHT = LLMTokenKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'LLM_TOKEN_KIND_THOUGHT');
  static const LLMTokenKind LLM_TOKEN_KIND_TOOL_CALL = LLMTokenKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'LLM_TOKEN_KIND_TOOL_CALL');

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

