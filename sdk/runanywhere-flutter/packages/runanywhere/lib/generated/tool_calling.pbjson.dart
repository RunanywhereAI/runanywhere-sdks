///
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use toolParameterTypeDescriptor instead')
const ToolParameterType$json = const {
  '1': 'ToolParameterType',
  '2': const [
    const {'1': 'TOOL_PARAMETER_TYPE_UNSPECIFIED', '2': 0},
    const {'1': 'TOOL_PARAMETER_TYPE_STRING', '2': 1},
    const {'1': 'TOOL_PARAMETER_TYPE_NUMBER', '2': 2},
    const {'1': 'TOOL_PARAMETER_TYPE_BOOLEAN', '2': 3},
    const {'1': 'TOOL_PARAMETER_TYPE_OBJECT', '2': 4},
    const {'1': 'TOOL_PARAMETER_TYPE_ARRAY', '2': 5},
  ],
};

/// Descriptor for `ToolParameterType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List toolParameterTypeDescriptor = $convert.base64Decode('ChFUb29sUGFyYW1ldGVyVHlwZRIjCh9UT09MX1BBUkFNRVRFUl9UWVBFX1VOU1BFQ0lGSUVEEAASHgoaVE9PTF9QQVJBTUVURVJfVFlQRV9TVFJJTkcQARIeChpUT09MX1BBUkFNRVRFUl9UWVBFX05VTUJFUhACEh8KG1RPT0xfUEFSQU1FVEVSX1RZUEVfQk9PTEVBThADEh4KGlRPT0xfUEFSQU1FVEVSX1RZUEVfT0JKRUNUEAQSHQoZVE9PTF9QQVJBTUVURVJfVFlQRV9BUlJBWRAF');
@$core.Deprecated('Use toolCallFormatNameDescriptor instead')
const ToolCallFormatName$json = const {
  '1': 'ToolCallFormatName',
  '2': const [
    const {'1': 'TOOL_CALL_FORMAT_NAME_UNSPECIFIED', '2': 0},
    const {'1': 'TOOL_CALL_FORMAT_NAME_JSON', '2': 1},
    const {'1': 'TOOL_CALL_FORMAT_NAME_XML', '2': 2},
    const {'1': 'TOOL_CALL_FORMAT_NAME_NATIVE', '2': 3},
    const {'1': 'TOOL_CALL_FORMAT_NAME_PYTHONIC', '2': 4},
    const {'1': 'TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS', '2': 5},
    const {'1': 'TOOL_CALL_FORMAT_NAME_HERMES', '2': 6},
  ],
};

/// Descriptor for `ToolCallFormatName`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List toolCallFormatNameDescriptor = $convert.base64Decode('ChJUb29sQ2FsbEZvcm1hdE5hbWUSJQohVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX1VOU1BFQ0lGSUVEEAASHgoaVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX0pTT04QARIdChlUT09MX0NBTExfRk9STUFUX05BTUVfWE1MEAISIAocVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX05BVElWRRADEiIKHlRPT0xfQ0FMTF9GT1JNQVRfTkFNRV9QWVRIT05JQxAEEioKJlRPT0xfQ0FMTF9GT1JNQVRfTkFNRV9PUEVOQUlfRlVOQ1RJT05TEAUSIAocVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX0hFUk1FUxAG');
@$core.Deprecated('Use toolValueDescriptor instead')
const ToolValue$json = const {
  '1': 'ToolValue',
  '2': const [
    const {'1': 'string_value', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'stringValue'},
    const {'1': 'number_value', '3': 2, '4': 1, '5': 1, '9': 0, '10': 'numberValue'},
    const {'1': 'bool_value', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'boolValue'},
    const {'1': 'array_value', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValueArray', '9': 0, '10': 'arrayValue'},
    const {'1': 'object_value', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValueObject', '9': 0, '10': 'objectValue'},
  ],
  '8': const [
    const {'1': 'kind'},
  ],
};

/// Descriptor for `ToolValue`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolValueDescriptor = $convert.base64Decode('CglUb29sVmFsdWUSIwoMc3RyaW5nX3ZhbHVlGAEgASgJSABSC3N0cmluZ1ZhbHVlEiMKDG51bWJlcl92YWx1ZRgCIAEoAUgAUgtudW1iZXJWYWx1ZRIfCgpib29sX3ZhbHVlGAMgASgISABSCWJvb2xWYWx1ZRJBCgthcnJheV92YWx1ZRgEIAEoCzIeLnJ1bmFueXdoZXJlLnYxLlRvb2xWYWx1ZUFycmF5SABSCmFycmF5VmFsdWUSRAoMb2JqZWN0X3ZhbHVlGAUgASgLMh8ucnVuYW55d2hlcmUudjEuVG9vbFZhbHVlT2JqZWN0SABSC29iamVjdFZhbHVlQgYKBGtpbmQ=');
@$core.Deprecated('Use toolValueArrayDescriptor instead')
const ToolValueArray$json = const {
  '1': 'ToolValueArray',
  '2': const [
    const {'1': 'values', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolValue', '10': 'values'},
  ],
};

/// Descriptor for `ToolValueArray`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolValueArrayDescriptor = $convert.base64Decode('Cg5Ub29sVmFsdWVBcnJheRIxCgZ2YWx1ZXMYASADKAsyGS5ydW5hbnl3aGVyZS52MS5Ub29sVmFsdWVSBnZhbHVlcw==');
@$core.Deprecated('Use toolValueObjectDescriptor instead')
const ToolValueObject$json = const {
  '1': 'ToolValueObject',
  '2': const [
    const {'1': 'fields', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolValueObject.FieldsEntry', '10': 'fields'},
  ],
  '3': const [ToolValueObject_FieldsEntry$json],
};

@$core.Deprecated('Use toolValueObjectDescriptor instead')
const ToolValueObject_FieldsEntry$json = const {
  '1': 'FieldsEntry',
  '2': const [
    const {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    const {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValue', '10': 'value'},
  ],
  '7': const {'7': true},
};

/// Descriptor for `ToolValueObject`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolValueObjectDescriptor = $convert.base64Decode('Cg9Ub29sVmFsdWVPYmplY3QSQwoGZmllbGRzGAEgAygLMisucnVuYW55d2hlcmUudjEuVG9vbFZhbHVlT2JqZWN0LkZpZWxkc0VudHJ5UgZmaWVsZHMaVAoLRmllbGRzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSLwoFdmFsdWUYAiABKAsyGS5ydW5hbnl3aGVyZS52MS5Ub29sVmFsdWVSBXZhbHVlOgI4AQ==');
@$core.Deprecated('Use toolParameterDescriptor instead')
const ToolParameter$json = const {
  '1': 'ToolParameter',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'type', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolParameterType', '10': 'type'},
    const {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    const {'1': 'required', '3': 4, '4': 1, '5': 8, '10': 'required'},
    const {'1': 'enum_values', '3': 5, '4': 3, '5': 9, '10': 'enumValues'},
  ],
};

/// Descriptor for `ToolParameter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolParameterDescriptor = $convert.base64Decode('Cg1Ub29sUGFyYW1ldGVyEhIKBG5hbWUYASABKAlSBG5hbWUSNQoEdHlwZRgCIAEoDjIhLnJ1bmFueXdoZXJlLnYxLlRvb2xQYXJhbWV0ZXJUeXBlUgR0eXBlEiAKC2Rlc2NyaXB0aW9uGAMgASgJUgtkZXNjcmlwdGlvbhIaCghyZXF1aXJlZBgEIAEoCFIIcmVxdWlyZWQSHwoLZW51bV92YWx1ZXMYBSADKAlSCmVudW1WYWx1ZXM=');
@$core.Deprecated('Use toolDefinitionDescriptor instead')
const ToolDefinition$json = const {
  '1': 'ToolDefinition',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    const {'1': 'parameters', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolParameter', '10': 'parameters'},
    const {'1': 'category', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'category', '17': true},
  ],
  '8': const [
    const {'1': '_category'},
  ],
};

/// Descriptor for `ToolDefinition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolDefinitionDescriptor = $convert.base64Decode('Cg5Ub29sRGVmaW5pdGlvbhISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAIgASgJUgtkZXNjcmlwdGlvbhI9CgpwYXJhbWV0ZXJzGAMgAygLMh0ucnVuYW55d2hlcmUudjEuVG9vbFBhcmFtZXRlclIKcGFyYW1ldGVycxIfCghjYXRlZ29yeRgEIAEoCUgAUghjYXRlZ29yeYgBAUILCglfY2F0ZWdvcnk=');
@$core.Deprecated('Use toolCallDescriptor instead')
const ToolCall$json = const {
  '1': 'ToolCall',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'arguments_json', '3': 3, '4': 1, '5': 9, '10': 'argumentsJson'},
    const {'1': 'type', '3': 4, '4': 1, '5': 9, '10': 'type'},
  ],
};

/// Descriptor for `ToolCall`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallDescriptor = $convert.base64Decode('CghUb29sQ2FsbBIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIlCg5hcmd1bWVudHNfanNvbhgDIAEoCVINYXJndW1lbnRzSnNvbhISCgR0eXBlGAQgASgJUgR0eXBl');
@$core.Deprecated('Use toolResultDescriptor instead')
const ToolResult$json = const {
  '1': 'ToolResult',
  '2': const [
    const {'1': 'tool_call_id', '3': 1, '4': 1, '5': 9, '10': 'toolCallId'},
    const {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'result_json', '3': 3, '4': 1, '5': 9, '10': 'resultJson'},
    const {'1': 'error', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'error', '17': true},
  ],
  '8': const [
    const {'1': '_error'},
  ],
};

/// Descriptor for `ToolResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolResultDescriptor = $convert.base64Decode('CgpUb29sUmVzdWx0EiAKDHRvb2xfY2FsbF9pZBgBIAEoCVIKdG9vbENhbGxJZBISCgRuYW1lGAIgASgJUgRuYW1lEh8KC3Jlc3VsdF9qc29uGAMgASgJUgpyZXN1bHRKc29uEhkKBWVycm9yGAQgASgJSABSBWVycm9yiAEBQggKBl9lcnJvcg==');
@$core.Deprecated('Use toolCallingOptionsDescriptor instead')
const ToolCallingOptions$json = const {
  '1': 'ToolCallingOptions',
  '2': const [
    const {'1': 'tools', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolDefinition', '10': 'tools'},
    const {'1': 'max_iterations', '3': 2, '4': 1, '5': 5, '10': 'maxIterations'},
    const {'1': 'auto_execute', '3': 3, '4': 1, '5': 8, '10': 'autoExecute'},
    const {'1': 'temperature', '3': 4, '4': 1, '5': 2, '9': 0, '10': 'temperature', '17': true},
    const {'1': 'max_tokens', '3': 5, '4': 1, '5': 5, '9': 1, '10': 'maxTokens', '17': true},
    const {'1': 'system_prompt', '3': 6, '4': 1, '5': 9, '9': 2, '10': 'systemPrompt', '17': true},
    const {'1': 'replace_system_prompt', '3': 7, '4': 1, '5': 8, '10': 'replaceSystemPrompt'},
    const {'1': 'keep_tools_available', '3': 8, '4': 1, '5': 8, '10': 'keepToolsAvailable'},
    const {'1': 'format_hint', '3': 9, '4': 1, '5': 9, '10': 'formatHint'},
    const {'1': 'format', '3': 10, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolCallFormatName', '9': 3, '10': 'format', '17': true},
    const {'1': 'custom_system_prompt', '3': 11, '4': 1, '5': 9, '9': 4, '10': 'customSystemPrompt', '17': true},
  ],
  '8': const [
    const {'1': '_temperature'},
    const {'1': '_max_tokens'},
    const {'1': '_system_prompt'},
    const {'1': '_format'},
    const {'1': '_custom_system_prompt'},
  ],
};

/// Descriptor for `ToolCallingOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingOptionsDescriptor = $convert.base64Decode('ChJUb29sQ2FsbGluZ09wdGlvbnMSNAoFdG9vbHMYASADKAsyHi5ydW5hbnl3aGVyZS52MS5Ub29sRGVmaW5pdGlvblIFdG9vbHMSJQoObWF4X2l0ZXJhdGlvbnMYAiABKAVSDW1heEl0ZXJhdGlvbnMSIQoMYXV0b19leGVjdXRlGAMgASgIUgthdXRvRXhlY3V0ZRIlCgt0ZW1wZXJhdHVyZRgEIAEoAkgAUgt0ZW1wZXJhdHVyZYgBARIiCgptYXhfdG9rZW5zGAUgASgFSAFSCW1heFRva2Vuc4gBARIoCg1zeXN0ZW1fcHJvbXB0GAYgASgJSAJSDHN5c3RlbVByb21wdIgBARIyChVyZXBsYWNlX3N5c3RlbV9wcm9tcHQYByABKAhSE3JlcGxhY2VTeXN0ZW1Qcm9tcHQSMAoUa2VlcF90b29sc19hdmFpbGFibGUYCCABKAhSEmtlZXBUb29sc0F2YWlsYWJsZRIfCgtmb3JtYXRfaGludBgJIAEoCVIKZm9ybWF0SGludBI/CgZmb3JtYXQYCiABKA4yIi5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbEZvcm1hdE5hbWVIA1IGZm9ybWF0iAEBEjUKFGN1c3RvbV9zeXN0ZW1fcHJvbXB0GAsgASgJSARSEmN1c3RvbVN5c3RlbVByb21wdIgBAUIOCgxfdGVtcGVyYXR1cmVCDQoLX21heF90b2tlbnNCEAoOX3N5c3RlbV9wcm9tcHRCCQoHX2Zvcm1hdEIXChVfY3VzdG9tX3N5c3RlbV9wcm9tcHQ=');
@$core.Deprecated('Use toolCallingResultDescriptor instead')
const ToolCallingResult$json = const {
  '1': 'ToolCallingResult',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'tool_calls', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCalls'},
    const {'1': 'tool_results', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolResult', '10': 'toolResults'},
    const {'1': 'is_complete', '3': 4, '4': 1, '5': 8, '10': 'isComplete'},
    const {'1': 'conversation_id', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'conversationId', '17': true},
    const {'1': 'iterations_used', '3': 6, '4': 1, '5': 5, '10': 'iterationsUsed'},
  ],
  '8': const [
    const {'1': '_conversation_id'},
  ],
};

/// Descriptor for `ToolCallingResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingResultDescriptor = $convert.base64Decode('ChFUb29sQ2FsbGluZ1Jlc3VsdBISCgR0ZXh0GAEgASgJUgR0ZXh0EjcKCnRvb2xfY2FsbHMYAiADKAsyGC5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbFIJdG9vbENhbGxzEj0KDHRvb2xfcmVzdWx0cxgDIAMoCzIaLnJ1bmFueXdoZXJlLnYxLlRvb2xSZXN1bHRSC3Rvb2xSZXN1bHRzEh8KC2lzX2NvbXBsZXRlGAQgASgIUgppc0NvbXBsZXRlEiwKD2NvbnZlcnNhdGlvbl9pZBgFIAEoCUgAUg5jb252ZXJzYXRpb25JZIgBARInCg9pdGVyYXRpb25zX3VzZWQYBiABKAVSDml0ZXJhdGlvbnNVc2VkQhIKEF9jb252ZXJzYXRpb25faWQ=');
