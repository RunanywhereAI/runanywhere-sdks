//
//  Generated code. Do not modify.
//  source: tool_calling.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use toolParameterTypeDescriptor instead')
const ToolParameterType$json = {
  '1': 'ToolParameterType',
  '2': [
    {'1': 'TOOL_PARAMETER_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'TOOL_PARAMETER_TYPE_STRING', '2': 1},
    {'1': 'TOOL_PARAMETER_TYPE_NUMBER', '2': 2},
    {'1': 'TOOL_PARAMETER_TYPE_BOOLEAN', '2': 3},
    {'1': 'TOOL_PARAMETER_TYPE_OBJECT', '2': 4},
    {'1': 'TOOL_PARAMETER_TYPE_ARRAY', '2': 5},
  ],
};

/// Descriptor for `ToolParameterType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List toolParameterTypeDescriptor = $convert.base64Decode(
    'ChFUb29sUGFyYW1ldGVyVHlwZRIjCh9UT09MX1BBUkFNRVRFUl9UWVBFX1VOU1BFQ0lGSUVEEA'
    'ASHgoaVE9PTF9QQVJBTUVURVJfVFlQRV9TVFJJTkcQARIeChpUT09MX1BBUkFNRVRFUl9UWVBF'
    'X05VTUJFUhACEh8KG1RPT0xfUEFSQU1FVEVSX1RZUEVfQk9PTEVBThADEh4KGlRPT0xfUEFSQU'
    '1FVEVSX1RZUEVfT0JKRUNUEAQSHQoZVE9PTF9QQVJBTUVURVJfVFlQRV9BUlJBWRAF');

@$core.Deprecated('Use toolCallFormatNameDescriptor instead')
const ToolCallFormatName$json = {
  '1': 'ToolCallFormatName',
  '2': [
    {'1': 'TOOL_CALL_FORMAT_NAME_UNSPECIFIED', '2': 0},
    {'1': 'TOOL_CALL_FORMAT_NAME_JSON', '2': 1},
    {'1': 'TOOL_CALL_FORMAT_NAME_XML', '2': 2},
    {'1': 'TOOL_CALL_FORMAT_NAME_NATIVE', '2': 3},
    {'1': 'TOOL_CALL_FORMAT_NAME_PYTHONIC', '2': 4},
    {'1': 'TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS', '2': 5},
    {'1': 'TOOL_CALL_FORMAT_NAME_HERMES', '2': 6},
  ],
};

/// Descriptor for `ToolCallFormatName`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List toolCallFormatNameDescriptor = $convert.base64Decode(
    'ChJUb29sQ2FsbEZvcm1hdE5hbWUSJQohVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX1VOU1BFQ0lGSU'
    'VEEAASHgoaVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX0pTT04QARIdChlUT09MX0NBTExfRk9STUFU'
    'X05BTUVfWE1MEAISIAocVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX05BVElWRRADEiIKHlRPT0xfQ0'
    'FMTF9GT1JNQVRfTkFNRV9QWVRIT05JQxAEEioKJlRPT0xfQ0FMTF9GT1JNQVRfTkFNRV9PUEVO'
    'QUlfRlVOQ1RJT05TEAUSIAocVE9PTF9DQUxMX0ZPUk1BVF9OQU1FX0hFUk1FUxAG');

@$core.Deprecated('Use toolValueDescriptor instead')
const ToolValue$json = {
  '1': 'ToolValue',
  '2': [
    {'1': 'string_value', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'stringValue'},
    {'1': 'number_value', '3': 2, '4': 1, '5': 1, '9': 0, '10': 'numberValue'},
    {'1': 'bool_value', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'boolValue'},
    {'1': 'array_value', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValueArray', '9': 0, '10': 'arrayValue'},
    {'1': 'object_value', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValueObject', '9': 0, '10': 'objectValue'},
    {'1': 'null_value', '3': 6, '4': 1, '5': 8, '9': 0, '10': 'nullValue'},
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `ToolValue`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolValueDescriptor = $convert.base64Decode(
    'CglUb29sVmFsdWUSIwoMc3RyaW5nX3ZhbHVlGAEgASgJSABSC3N0cmluZ1ZhbHVlEiMKDG51bW'
    'Jlcl92YWx1ZRgCIAEoAUgAUgtudW1iZXJWYWx1ZRIfCgpib29sX3ZhbHVlGAMgASgISABSCWJv'
    'b2xWYWx1ZRJBCgthcnJheV92YWx1ZRgEIAEoCzIeLnJ1bmFueXdoZXJlLnYxLlRvb2xWYWx1ZU'
    'FycmF5SABSCmFycmF5VmFsdWUSRAoMb2JqZWN0X3ZhbHVlGAUgASgLMh8ucnVuYW55d2hlcmUu'
    'djEuVG9vbFZhbHVlT2JqZWN0SABSC29iamVjdFZhbHVlEh8KCm51bGxfdmFsdWUYBiABKAhIAF'
    'IJbnVsbFZhbHVlQgYKBGtpbmQ=');

@$core.Deprecated('Use toolValueArrayDescriptor instead')
const ToolValueArray$json = {
  '1': 'ToolValueArray',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolValue', '10': 'values'},
  ],
};

/// Descriptor for `ToolValueArray`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolValueArrayDescriptor = $convert.base64Decode(
    'Cg5Ub29sVmFsdWVBcnJheRIxCgZ2YWx1ZXMYASADKAsyGS5ydW5hbnl3aGVyZS52MS5Ub29sVm'
    'FsdWVSBnZhbHVlcw==');

@$core.Deprecated('Use toolValueObjectDescriptor instead')
const ToolValueObject$json = {
  '1': 'ToolValueObject',
  '2': [
    {'1': 'fields', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolValueObject.FieldsEntry', '10': 'fields'},
  ],
  '3': [ToolValueObject_FieldsEntry$json],
};

@$core.Deprecated('Use toolValueObjectDescriptor instead')
const ToolValueObject_FieldsEntry$json = {
  '1': 'FieldsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValue', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ToolValueObject`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolValueObjectDescriptor = $convert.base64Decode(
    'Cg9Ub29sVmFsdWVPYmplY3QSQwoGZmllbGRzGAEgAygLMisucnVuYW55d2hlcmUudjEuVG9vbF'
    'ZhbHVlT2JqZWN0LkZpZWxkc0VudHJ5UgZmaWVsZHMaVAoLRmllbGRzRW50cnkSEAoDa2V5GAEg'
    'ASgJUgNrZXkSLwoFdmFsdWUYAiABKAsyGS5ydW5hbnl3aGVyZS52MS5Ub29sVmFsdWVSBXZhbH'
    'VlOgI4AQ==');

@$core.Deprecated('Use toolParameterDescriptor instead')
const ToolParameter$json = {
  '1': 'ToolParameter',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'type', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolParameterType', '10': 'type'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'required', '3': 4, '4': 1, '5': 8, '10': 'required'},
    {'1': 'enum_values', '3': 5, '4': 3, '5': 9, '10': 'enumValues'},
  ],
};

/// Descriptor for `ToolParameter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolParameterDescriptor = $convert.base64Decode(
    'Cg1Ub29sUGFyYW1ldGVyEhIKBG5hbWUYASABKAlSBG5hbWUSNQoEdHlwZRgCIAEoDjIhLnJ1bm'
    'FueXdoZXJlLnYxLlRvb2xQYXJhbWV0ZXJUeXBlUgR0eXBlEiAKC2Rlc2NyaXB0aW9uGAMgASgJ'
    'UgtkZXNjcmlwdGlvbhIaCghyZXF1aXJlZBgEIAEoCFIIcmVxdWlyZWQSHwoLZW51bV92YWx1ZX'
    'MYBSADKAlSCmVudW1WYWx1ZXM=');

@$core.Deprecated('Use toolDefinitionDescriptor instead')
const ToolDefinition$json = {
  '1': 'ToolDefinition',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'parameters', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolParameter', '10': 'parameters'},
    {'1': 'category', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'category', '17': true},
  ],
  '8': [
    {'1': '_category'},
  ],
};

/// Descriptor for `ToolDefinition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolDefinitionDescriptor = $convert.base64Decode(
    'Cg5Ub29sRGVmaW5pdGlvbhISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAIgAS'
    'gJUgtkZXNjcmlwdGlvbhI9CgpwYXJhbWV0ZXJzGAMgAygLMh0ucnVuYW55d2hlcmUudjEuVG9v'
    'bFBhcmFtZXRlclIKcGFyYW1ldGVycxIfCghjYXRlZ29yeRgEIAEoCUgAUghjYXRlZ29yeYgBAU'
    'ILCglfY2F0ZWdvcnk=');

@$core.Deprecated('Use toolCallDescriptor instead')
const ToolCall$json = {
  '1': 'ToolCall',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'arguments_json', '3': 3, '4': 1, '5': 9, '10': 'argumentsJson'},
    {'1': 'type', '3': 4, '4': 1, '5': 9, '10': 'type'},
    {'1': 'arguments', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall.ArgumentsEntry', '10': 'arguments'},
    {'1': 'call_id', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'callId', '17': true},
  ],
  '3': [ToolCall_ArgumentsEntry$json],
  '8': [
    {'1': '_call_id'},
  ],
};

@$core.Deprecated('Use toolCallDescriptor instead')
const ToolCall_ArgumentsEntry$json = {
  '1': 'ArgumentsEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValue', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ToolCall`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallDescriptor = $convert.base64Decode(
    'CghUb29sQ2FsbBIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIlCg5hcmd1bW'
    'VudHNfanNvbhgDIAEoCVINYXJndW1lbnRzSnNvbhISCgR0eXBlGAQgASgJUgR0eXBlEkUKCWFy'
    'Z3VtZW50cxgFIAMoCzInLnJ1bmFueXdoZXJlLnYxLlRvb2xDYWxsLkFyZ3VtZW50c0VudHJ5Ug'
    'lhcmd1bWVudHMSHAoHY2FsbF9pZBgGIAEoCUgAUgZjYWxsSWSIAQEaVwoOQXJndW1lbnRzRW50'
    'cnkSEAoDa2V5GAEgASgJUgNrZXkSLwoFdmFsdWUYAiABKAsyGS5ydW5hbnl3aGVyZS52MS5Ub2'
    '9sVmFsdWVSBXZhbHVlOgI4AUIKCghfY2FsbF9pZA==');

@$core.Deprecated('Use toolResultDescriptor instead')
const ToolResult$json = {
  '1': 'ToolResult',
  '2': [
    {'1': 'tool_call_id', '3': 1, '4': 1, '5': 9, '10': 'toolCallId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'result_json', '3': 3, '4': 1, '5': 9, '10': 'resultJson'},
    {'1': 'error', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'error', '17': true},
    {'1': 'success', '3': 5, '4': 1, '5': 8, '10': 'success'},
    {'1': 'result', '3': 6, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolResult.ResultEntry', '10': 'result'},
    {'1': 'call_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'callId', '17': true},
  ],
  '3': [ToolResult_ResultEntry$json],
  '8': [
    {'1': '_error'},
    {'1': '_call_id'},
  ],
};

@$core.Deprecated('Use toolResultDescriptor instead')
const ToolResult_ResultEntry$json = {
  '1': 'ResultEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValue', '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ToolResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolResultDescriptor = $convert.base64Decode(
    'CgpUb29sUmVzdWx0EiAKDHRvb2xfY2FsbF9pZBgBIAEoCVIKdG9vbENhbGxJZBISCgRuYW1lGA'
    'IgASgJUgRuYW1lEh8KC3Jlc3VsdF9qc29uGAMgASgJUgpyZXN1bHRKc29uEhkKBWVycm9yGAQg'
    'ASgJSABSBWVycm9yiAEBEhgKB3N1Y2Nlc3MYBSABKAhSB3N1Y2Nlc3MSPgoGcmVzdWx0GAYgAy'
    'gLMiYucnVuYW55d2hlcmUudjEuVG9vbFJlc3VsdC5SZXN1bHRFbnRyeVIGcmVzdWx0EhwKB2Nh'
    'bGxfaWQYByABKAlIAVIGY2FsbElkiAEBGlQKC1Jlc3VsdEVudHJ5EhAKA2tleRgBIAEoCVIDa2'
    'V5Ei8KBXZhbHVlGAIgASgLMhkucnVuYW55d2hlcmUudjEuVG9vbFZhbHVlUgV2YWx1ZToCOAFC'
    'CAoGX2Vycm9yQgoKCF9jYWxsX2lk');

@$core.Deprecated('Use toolCallingOptionsDescriptor instead')
const ToolCallingOptions$json = {
  '1': 'ToolCallingOptions',
  '2': [
    {'1': 'tools', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolDefinition', '10': 'tools'},
    {'1': 'max_iterations', '3': 2, '4': 1, '5': 5, '10': 'maxIterations'},
    {'1': 'auto_execute', '3': 3, '4': 1, '5': 8, '10': 'autoExecute'},
    {'1': 'temperature', '3': 4, '4': 1, '5': 2, '9': 0, '10': 'temperature', '17': true},
    {'1': 'max_tokens', '3': 5, '4': 1, '5': 5, '9': 1, '10': 'maxTokens', '17': true},
    {'1': 'system_prompt', '3': 6, '4': 1, '5': 9, '9': 2, '10': 'systemPrompt', '17': true},
    {'1': 'replace_system_prompt', '3': 7, '4': 1, '5': 8, '10': 'replaceSystemPrompt'},
    {'1': 'keep_tools_available', '3': 8, '4': 1, '5': 8, '10': 'keepToolsAvailable'},
    {'1': 'format_hint', '3': 9, '4': 1, '5': 9, '10': 'formatHint'},
    {'1': 'format', '3': 10, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolCallFormatName', '9': 3, '10': 'format', '17': true},
    {'1': 'custom_system_prompt', '3': 11, '4': 1, '5': 9, '9': 4, '10': 'customSystemPrompt', '17': true},
    {'1': 'max_tool_calls', '3': 12, '4': 1, '5': 5, '9': 5, '10': 'maxToolCalls', '17': true},
  ],
  '8': [
    {'1': '_temperature'},
    {'1': '_max_tokens'},
    {'1': '_system_prompt'},
    {'1': '_format'},
    {'1': '_custom_system_prompt'},
    {'1': '_max_tool_calls'},
  ],
};

/// Descriptor for `ToolCallingOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingOptionsDescriptor = $convert.base64Decode(
    'ChJUb29sQ2FsbGluZ09wdGlvbnMSNAoFdG9vbHMYASADKAsyHi5ydW5hbnl3aGVyZS52MS5Ub2'
    '9sRGVmaW5pdGlvblIFdG9vbHMSJQoObWF4X2l0ZXJhdGlvbnMYAiABKAVSDW1heEl0ZXJhdGlv'
    'bnMSIQoMYXV0b19leGVjdXRlGAMgASgIUgthdXRvRXhlY3V0ZRIlCgt0ZW1wZXJhdHVyZRgEIA'
    'EoAkgAUgt0ZW1wZXJhdHVyZYgBARIiCgptYXhfdG9rZW5zGAUgASgFSAFSCW1heFRva2Vuc4gB'
    'ARIoCg1zeXN0ZW1fcHJvbXB0GAYgASgJSAJSDHN5c3RlbVByb21wdIgBARIyChVyZXBsYWNlX3'
    'N5c3RlbV9wcm9tcHQYByABKAhSE3JlcGxhY2VTeXN0ZW1Qcm9tcHQSMAoUa2VlcF90b29sc19h'
    'dmFpbGFibGUYCCABKAhSEmtlZXBUb29sc0F2YWlsYWJsZRIfCgtmb3JtYXRfaGludBgJIAEoCV'
    'IKZm9ybWF0SGludBI/CgZmb3JtYXQYCiABKA4yIi5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbEZv'
    'cm1hdE5hbWVIA1IGZm9ybWF0iAEBEjUKFGN1c3RvbV9zeXN0ZW1fcHJvbXB0GAsgASgJSARSEm'
    'N1c3RvbVN5c3RlbVByb21wdIgBARIpCg5tYXhfdG9vbF9jYWxscxgMIAEoBUgFUgxtYXhUb29s'
    'Q2FsbHOIAQFCDgoMX3RlbXBlcmF0dXJlQg0KC19tYXhfdG9rZW5zQhAKDl9zeXN0ZW1fcHJvbX'
    'B0QgkKB19mb3JtYXRCFwoVX2N1c3RvbV9zeXN0ZW1fcHJvbXB0QhEKD19tYXhfdG9vbF9jYWxs'
    'cw==');

@$core.Deprecated('Use toolCallingResultDescriptor instead')
const ToolCallingResult$json = {
  '1': 'ToolCallingResult',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'tool_calls', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCalls'},
    {'1': 'tool_results', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolResult', '10': 'toolResults'},
    {'1': 'is_complete', '3': 4, '4': 1, '5': 8, '10': 'isComplete'},
    {'1': 'conversation_id', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'conversationId', '17': true},
    {'1': 'iterations_used', '3': 6, '4': 1, '5': 5, '10': 'iterationsUsed'},
  ],
  '8': [
    {'1': '_conversation_id'},
  ],
};

/// Descriptor for `ToolCallingResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingResultDescriptor = $convert.base64Decode(
    'ChFUb29sQ2FsbGluZ1Jlc3VsdBISCgR0ZXh0GAEgASgJUgR0ZXh0EjcKCnRvb2xfY2FsbHMYAi'
    'ADKAsyGC5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbFIJdG9vbENhbGxzEj0KDHRvb2xfcmVzdWx0'
    'cxgDIAMoCzIaLnJ1bmFueXdoZXJlLnYxLlRvb2xSZXN1bHRSC3Rvb2xSZXN1bHRzEh8KC2lzX2'
    'NvbXBsZXRlGAQgASgIUgppc0NvbXBsZXRlEiwKD2NvbnZlcnNhdGlvbl9pZBgFIAEoCUgAUg5j'
    'b252ZXJzYXRpb25JZIgBARInCg9pdGVyYXRpb25zX3VzZWQYBiABKAVSDml0ZXJhdGlvbnNVc2'
    'VkQhIKEF9jb252ZXJzYXRpb25faWQ=');

