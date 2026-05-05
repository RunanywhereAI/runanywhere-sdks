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

@$core.Deprecated('Use toolChoiceModeDescriptor instead')
const ToolChoiceMode$json = {
  '1': 'ToolChoiceMode',
  '2': [
    {'1': 'TOOL_CHOICE_MODE_UNSPECIFIED', '2': 0},
    {'1': 'TOOL_CHOICE_MODE_AUTO', '2': 1},
    {'1': 'TOOL_CHOICE_MODE_NONE', '2': 2},
    {'1': 'TOOL_CHOICE_MODE_REQUIRED', '2': 3},
    {'1': 'TOOL_CHOICE_MODE_SPECIFIC', '2': 4},
  ],
};

/// Descriptor for `ToolChoiceMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List toolChoiceModeDescriptor = $convert.base64Decode(
    'Cg5Ub29sQ2hvaWNlTW9kZRIgChxUT09MX0NIT0lDRV9NT0RFX1VOU1BFQ0lGSUVEEAASGQoVVE'
    '9PTF9DSE9JQ0VfTU9ERV9BVVRPEAESGQoVVE9PTF9DSE9JQ0VfTU9ERV9OT05FEAISHQoZVE9P'
    'TF9DSE9JQ0VfTU9ERV9SRVFVSVJFRBADEh0KGVRPT0xfQ0hPSUNFX01PREVfU1BFQ0lGSUMQBA'
    '==');

@$core.Deprecated('Use toolCallingStreamEventKindDescriptor instead')
const ToolCallingStreamEventKind$json = {
  '1': 'ToolCallingStreamEventKind',
  '2': [
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN', '2': 1},
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED', '2': 2},
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED', '2': 3},
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED', '2': 4},
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED', '2': 5},
    {'1': 'TOOL_CALLING_STREAM_EVENT_KIND_ERROR', '2': 6},
  ],
};

/// Descriptor for `ToolCallingStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List toolCallingStreamEventKindDescriptor = $convert.base64Decode(
    'ChpUb29sQ2FsbGluZ1N0cmVhbUV2ZW50S2luZBIuCipUT09MX0NBTExJTkdfU1RSRUFNX0VWRU'
    '5UX0tJTkRfVU5TUEVDSUZJRUQQABIuCipUT09MX0NBTExJTkdfU1RSRUFNX0VWRU5UX0tJTkRf'
    'TU9ERUxfVE9LRU4QARIzCi9UT09MX0NBTExJTkdfU1RSRUFNX0VWRU5UX0tJTkRfVE9PTF9DQU'
    'xMX1BBUlNFRBACEjkKNVRPT0xfQ0FMTElOR19TVFJFQU1fRVZFTlRfS0lORF9UT09MX0VYRUNV'
    'VElPTl9TVEFSVEVEEAMSOwo3VE9PTF9DQUxMSU5HX1NUUkVBTV9FVkVOVF9LSU5EX1RPT0xfRV'
    'hFQ1VUSU9OX0NPTVBMRVRFRBAEEiwKKFRPT0xfQ0FMTElOR19TVFJFQU1fRVZFTlRfS0lORF9D'
    'T01QTEVURUQQBRIoCiRUT09MX0NBTExJTkdfU1RSRUFNX0VWRU5UX0tJTkRfRVJST1IQBg==');

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
    {'1': 'json_schema', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'jsonSchema', '17': true},
    {'1': 'default_value', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolValue', '9': 1, '10': 'defaultValue', '17': true},
  ],
  '8': [
    {'1': '_json_schema'},
    {'1': '_default_value'},
  ],
};

/// Descriptor for `ToolParameter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolParameterDescriptor = $convert.base64Decode(
    'Cg1Ub29sUGFyYW1ldGVyEhIKBG5hbWUYASABKAlSBG5hbWUSNQoEdHlwZRgCIAEoDjIhLnJ1bm'
    'FueXdoZXJlLnYxLlRvb2xQYXJhbWV0ZXJUeXBlUgR0eXBlEiAKC2Rlc2NyaXB0aW9uGAMgASgJ'
    'UgtkZXNjcmlwdGlvbhIaCghyZXF1aXJlZBgEIAEoCFIIcmVxdWlyZWQSHwoLZW51bV92YWx1ZX'
    'MYBSADKAlSCmVudW1WYWx1ZXMSJAoLanNvbl9zY2hlbWEYBiABKAlIAFIKanNvblNjaGVtYYgB'
    'ARJDCg1kZWZhdWx0X3ZhbHVlGAcgASgLMhkucnVuYW55d2hlcmUudjEuVG9vbFZhbHVlSAFSDG'
    'RlZmF1bHRWYWx1ZYgBAUIOCgxfanNvbl9zY2hlbWFCEAoOX2RlZmF1bHRfdmFsdWU=');

@$core.Deprecated('Use toolDefinitionDescriptor instead')
const ToolDefinition$json = {
  '1': 'ToolDefinition',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'parameters', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolParameter', '10': 'parameters'},
    {'1': 'category', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'category', '17': true},
    {'1': 'json_schema', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'jsonSchema', '17': true},
    {'1': 'metadata', '3': 6, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolDefinition.MetadataEntry', '10': 'metadata'},
  ],
  '3': [ToolDefinition_MetadataEntry$json],
  '8': [
    {'1': '_category'},
    {'1': '_json_schema'},
  ],
};

@$core.Deprecated('Use toolDefinitionDescriptor instead')
const ToolDefinition_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ToolDefinition`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolDefinitionDescriptor = $convert.base64Decode(
    'Cg5Ub29sRGVmaW5pdGlvbhISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAIgAS'
    'gJUgtkZXNjcmlwdGlvbhI9CgpwYXJhbWV0ZXJzGAMgAygLMh0ucnVuYW55d2hlcmUudjEuVG9v'
    'bFBhcmFtZXRlclIKcGFyYW1ldGVycxIfCghjYXRlZ29yeRgEIAEoCUgAUghjYXRlZ29yeYgBAR'
    'IkCgtqc29uX3NjaGVtYRgFIAEoCUgBUgpqc29uU2NoZW1hiAEBEkgKCG1ldGFkYXRhGAYgAygL'
    'MiwucnVuYW55d2hlcmUudjEuVG9vbERlZmluaXRpb24uTWV0YWRhdGFFbnRyeVIIbWV0YWRhdG'
    'EaOwoNTWV0YWRhdGFFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFs'
    'dWU6AjgBQgsKCV9jYXRlZ29yeUIOCgxfanNvbl9zY2hlbWE=');

@$core.Deprecated('Use toolCallDescriptor instead')
const ToolCall$json = {
  '1': 'ToolCall',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'arguments_json', '3': 3, '4': 1, '5': 9, '10': 'argumentsJson'},
    {'1': 'type', '3': 4, '4': 1, '5': 9, '10': 'type'},
    {'1': 'call_id', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'callId', '17': true},
    {'1': 'created_at_ms', '3': 7, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'raw_text', '3': 8, '4': 1, '5': 9, '9': 1, '10': 'rawText', '17': true},
  ],
  '8': [
    {'1': '_call_id'},
    {'1': '_raw_text'},
  ],
  '9': [
    {'1': 5, '2': 6},
  ],
  '10': ['arguments'],
};

/// Descriptor for `ToolCall`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallDescriptor = $convert.base64Decode(
    'CghUb29sQ2FsbBIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIlCg5hcmd1bW'
    'VudHNfanNvbhgDIAEoCVINYXJndW1lbnRzSnNvbhISCgR0eXBlGAQgASgJUgR0eXBlEhwKB2Nh'
    'bGxfaWQYBiABKAlIAFIGY2FsbElkiAEBEiIKDWNyZWF0ZWRfYXRfbXMYByABKANSC2NyZWF0ZW'
    'RBdE1zEh4KCHJhd190ZXh0GAggASgJSAFSB3Jhd1RleHSIAQFCCgoIX2NhbGxfaWRCCwoJX3Jh'
    'd190ZXh0SgQIBRAGUglhcmd1bWVudHM=');

@$core.Deprecated('Use toolResultDescriptor instead')
const ToolResult$json = {
  '1': 'ToolResult',
  '2': [
    {'1': 'tool_call_id', '3': 1, '4': 1, '5': 9, '10': 'toolCallId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'result_json', '3': 3, '4': 1, '5': 9, '10': 'resultJson'},
    {'1': 'error', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'error', '17': true},
    {'1': 'success', '3': 5, '4': 1, '5': 8, '10': 'success'},
    {'1': 'call_id', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'callId', '17': true},
    {'1': 'started_at_ms', '3': 8, '4': 1, '5': 3, '10': 'startedAtMs'},
    {'1': 'completed_at_ms', '3': 9, '4': 1, '5': 3, '10': 'completedAtMs'},
  ],
  '8': [
    {'1': '_error'},
    {'1': '_call_id'},
  ],
  '9': [
    {'1': 6, '2': 7},
  ],
  '10': ['result'],
};

/// Descriptor for `ToolResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolResultDescriptor = $convert.base64Decode(
    'CgpUb29sUmVzdWx0EiAKDHRvb2xfY2FsbF9pZBgBIAEoCVIKdG9vbENhbGxJZBISCgRuYW1lGA'
    'IgASgJUgRuYW1lEh8KC3Jlc3VsdF9qc29uGAMgASgJUgpyZXN1bHRKc29uEhkKBWVycm9yGAQg'
    'ASgJSABSBWVycm9yiAEBEhgKB3N1Y2Nlc3MYBSABKAhSB3N1Y2Nlc3MSHAoHY2FsbF9pZBgHIA'
    'EoCUgBUgZjYWxsSWSIAQESIgoNc3RhcnRlZF9hdF9tcxgIIAEoA1ILc3RhcnRlZEF0TXMSJgoP'
    'Y29tcGxldGVkX2F0X21zGAkgASgDUg1jb21wbGV0ZWRBdE1zQggKBl9lcnJvckIKCghfY2FsbF'
    '9pZEoECAYQB1IGcmVzdWx0');

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
    {'1': 'tool_choice', '3': 13, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolChoiceMode', '10': 'toolChoice'},
    {'1': 'forced_tool_name', '3': 14, '4': 1, '5': 9, '9': 6, '10': 'forcedToolName', '17': true},
    {'1': 'parallel_tool_calls', '3': 15, '4': 1, '5': 8, '10': 'parallelToolCalls'},
    {'1': 'require_json_arguments', '3': 16, '4': 1, '5': 8, '10': 'requireJsonArguments'},
  ],
  '8': [
    {'1': '_temperature'},
    {'1': '_max_tokens'},
    {'1': '_system_prompt'},
    {'1': '_format'},
    {'1': '_custom_system_prompt'},
    {'1': '_max_tool_calls'},
    {'1': '_forced_tool_name'},
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
    'Q2FsbHOIAQESPwoLdG9vbF9jaG9pY2UYDSABKA4yHi5ydW5hbnl3aGVyZS52MS5Ub29sQ2hvaW'
    'NlTW9kZVIKdG9vbENob2ljZRItChBmb3JjZWRfdG9vbF9uYW1lGA4gASgJSAZSDmZvcmNlZFRv'
    'b2xOYW1liAEBEi4KE3BhcmFsbGVsX3Rvb2xfY2FsbHMYDyABKAhSEXBhcmFsbGVsVG9vbENhbG'
    'xzEjQKFnJlcXVpcmVfanNvbl9hcmd1bWVudHMYECABKAhSFHJlcXVpcmVKc29uQXJndW1lbnRz'
    'Qg4KDF90ZW1wZXJhdHVyZUINCgtfbWF4X3Rva2Vuc0IQCg5fc3lzdGVtX3Byb21wdEIJCgdfZm'
    '9ybWF0QhcKFV9jdXN0b21fc3lzdGVtX3Byb21wdEIRCg9fbWF4X3Rvb2xfY2FsbHNCEwoRX2Zv'
    'cmNlZF90b29sX25hbWU=');

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
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 8, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'raw_text', '3': 9, '4': 1, '5': 9, '10': 'rawText'},
  ],
  '8': [
    {'1': '_conversation_id'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ToolCallingResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingResultDescriptor = $convert.base64Decode(
    'ChFUb29sQ2FsbGluZ1Jlc3VsdBISCgR0ZXh0GAEgASgJUgR0ZXh0EjcKCnRvb2xfY2FsbHMYAi'
    'ADKAsyGC5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbFIJdG9vbENhbGxzEj0KDHRvb2xfcmVzdWx0'
    'cxgDIAMoCzIaLnJ1bmFueXdoZXJlLnYxLlRvb2xSZXN1bHRSC3Rvb2xSZXN1bHRzEh8KC2lzX2'
    'NvbXBsZXRlGAQgASgIUgppc0NvbXBsZXRlEiwKD2NvbnZlcnNhdGlvbl9pZBgFIAEoCUgAUg5j'
    'b252ZXJzYXRpb25JZIgBARInCg9pdGVyYXRpb25zX3VzZWQYBiABKAVSDml0ZXJhdGlvbnNVc2'
    'VkEigKDWVycm9yX21lc3NhZ2UYByABKAlIAVIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2Nv'
    'ZGUYCCABKAVSCWVycm9yQ29kZRIZCghyYXdfdGV4dBgJIAEoCVIHcmF3VGV4dEISChBfY29udm'
    'Vyc2F0aW9uX2lkQhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use toolParseRequestDescriptor instead')
const ToolParseRequest$json = {
  '1': 'ToolParseRequest',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCallingOptions', '9': 0, '10': 'options', '17': true},
  ],
  '8': [
    {'1': '_options'},
  ],
};

/// Descriptor for `ToolParseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolParseRequestDescriptor = $convert.base64Decode(
    'ChBUb29sUGFyc2VSZXF1ZXN0EhIKBHRleHQYASABKAlSBHRleHQSQQoHb3B0aW9ucxgCIAEoCz'
    'IiLnJ1bmFueXdoZXJlLnYxLlRvb2xDYWxsaW5nT3B0aW9uc0gAUgdvcHRpb25ziAEBQgoKCF9v'
    'cHRpb25z');

@$core.Deprecated('Use toolParseResultDescriptor instead')
const ToolParseResult$json = {
  '1': 'ToolParseResult',
  '2': [
    {'1': 'has_tool_call', '3': 1, '4': 1, '5': 8, '10': 'hasToolCall'},
    {'1': 'tool_calls', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCalls'},
    {'1': 'remaining_text', '3': 3, '4': 1, '5': 9, '10': 'remainingText'},
    {'1': 'error_message', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ToolParseResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolParseResultDescriptor = $convert.base64Decode(
    'Cg9Ub29sUGFyc2VSZXN1bHQSIgoNaGFzX3Rvb2xfY2FsbBgBIAEoCFILaGFzVG9vbENhbGwSNw'
    'oKdG9vbF9jYWxscxgCIAMoCzIYLnJ1bmFueXdoZXJlLnYxLlRvb2xDYWxsUgl0b29sQ2FsbHMS'
    'JQoOcmVtYWluaW5nX3RleHQYAyABKAlSDXJlbWFpbmluZ1RleHQSKAoNZXJyb3JfbWVzc2FnZR'
    'gEIAEoCUgAUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3JfY29kZRgFIAEoBVIJZXJyb3JDb2Rl'
    'QhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use toolPromptFormatRequestDescriptor instead')
const ToolPromptFormatRequest$json = {
  '1': 'ToolPromptFormatRequest',
  '2': [
    {'1': 'user_prompt', '3': 1, '4': 1, '5': 9, '10': 'userPrompt'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCallingOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'tool_results', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolResult', '10': 'toolResults'},
    {'1': 'assistant_text', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'assistantText', '17': true},
  ],
  '8': [
    {'1': '_options'},
    {'1': '_assistant_text'},
  ],
};

/// Descriptor for `ToolPromptFormatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolPromptFormatRequestDescriptor = $convert.base64Decode(
    'ChdUb29sUHJvbXB0Rm9ybWF0UmVxdWVzdBIfCgt1c2VyX3Byb21wdBgBIAEoCVIKdXNlclByb2'
    '1wdBJBCgdvcHRpb25zGAIgASgLMiIucnVuYW55d2hlcmUudjEuVG9vbENhbGxpbmdPcHRpb25z'
    'SABSB29wdGlvbnOIAQESPQoMdG9vbF9yZXN1bHRzGAMgAygLMhoucnVuYW55d2hlcmUudjEuVG'
    '9vbFJlc3VsdFILdG9vbFJlc3VsdHMSKgoOYXNzaXN0YW50X3RleHQYBCABKAlIAVINYXNzaXN0'
    'YW50VGV4dIgBAUIKCghfb3B0aW9uc0IRCg9fYXNzaXN0YW50X3RleHQ=');

@$core.Deprecated('Use toolPromptFormatResultDescriptor instead')
const ToolPromptFormatResult$json = {
  '1': 'ToolPromptFormatResult',
  '2': [
    {'1': 'formatted_prompt', '3': 1, '4': 1, '5': 9, '10': 'formattedPrompt'},
    {'1': 'format', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolCallFormatName', '10': 'format'},
    {'1': 'format_hint', '3': 3, '4': 1, '5': 9, '10': 'formatHint'},
    {'1': 'error_message', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ToolPromptFormatResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolPromptFormatResultDescriptor = $convert.base64Decode(
    'ChZUb29sUHJvbXB0Rm9ybWF0UmVzdWx0EikKEGZvcm1hdHRlZF9wcm9tcHQYASABKAlSD2Zvcm'
    '1hdHRlZFByb21wdBI6CgZmb3JtYXQYAiABKA4yIi5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbEZv'
    'cm1hdE5hbWVSBmZvcm1hdBIfCgtmb3JtYXRfaGludBgDIAEoCVIKZm9ybWF0SGludBIoCg1lcn'
    'Jvcl9tZXNzYWdlGAQgASgJSABSDGVycm9yTWVzc2FnZYgBARIdCgplcnJvcl9jb2RlGAUgASgF'
    'UgllcnJvckNvZGVCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use toolCallValidationRequestDescriptor instead')
const ToolCallValidationRequest$json = {
  '1': 'ToolCallValidationRequest',
  '2': [
    {'1': 'tool_call', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCall', '10': 'toolCall'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCallingOptions', '9': 0, '10': 'options', '17': true},
  ],
  '8': [
    {'1': '_options'},
  ],
};

/// Descriptor for `ToolCallValidationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallValidationRequestDescriptor = $convert.base64Decode(
    'ChlUb29sQ2FsbFZhbGlkYXRpb25SZXF1ZXN0EjUKCXRvb2xfY2FsbBgBIAEoCzIYLnJ1bmFueX'
    'doZXJlLnYxLlRvb2xDYWxsUgh0b29sQ2FsbBJBCgdvcHRpb25zGAIgASgLMiIucnVuYW55d2hl'
    'cmUudjEuVG9vbENhbGxpbmdPcHRpb25zSABSB29wdGlvbnOIAQFCCgoIX29wdGlvbnM=');

@$core.Deprecated('Use toolCallValidationResultDescriptor instead')
const ToolCallValidationResult$json = {
  '1': 'ToolCallValidationResult',
  '2': [
    {'1': 'is_valid', '3': 1, '4': 1, '5': 8, '10': 'isValid'},
    {'1': 'validation_errors', '3': 2, '4': 3, '5': 9, '10': 'validationErrors'},
    {'1': 'matched_tool', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolDefinition', '9': 0, '10': 'matchedTool', '17': true},
    {'1': 'normalized_arguments_json', '3': 4, '4': 1, '5': 9, '10': 'normalizedArgumentsJson'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 6, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_matched_tool'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ToolCallValidationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallValidationResultDescriptor = $convert.base64Decode(
    'ChhUb29sQ2FsbFZhbGlkYXRpb25SZXN1bHQSGQoIaXNfdmFsaWQYASABKAhSB2lzVmFsaWQSKw'
    'oRdmFsaWRhdGlvbl9lcnJvcnMYAiADKAlSEHZhbGlkYXRpb25FcnJvcnMSRgoMbWF0Y2hlZF90'
    'b29sGAMgASgLMh4ucnVuYW55d2hlcmUudjEuVG9vbERlZmluaXRpb25IAFILbWF0Y2hlZFRvb2'
    'yIAQESOgoZbm9ybWFsaXplZF9hcmd1bWVudHNfanNvbhgEIAEoCVIXbm9ybWFsaXplZEFyZ3Vt'
    'ZW50c0pzb24SKAoNZXJyb3JfbWVzc2FnZRgFIAEoCUgBUgxlcnJvck1lc3NhZ2WIAQESHQoKZX'
    'Jyb3JfY29kZRgGIAEoBVIJZXJyb3JDb2RlQg8KDV9tYXRjaGVkX3Rvb2xCEAoOX2Vycm9yX21l'
    'c3NhZ2U=');

@$core.Deprecated('Use toolCallingStreamEventDescriptor instead')
const ToolCallingStreamEvent$json = {
  '1': 'ToolCallingStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'conversation_id', '3': 3, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ToolCallingStreamEventKind', '10': 'kind'},
    {'1': 'token', '3': 5, '4': 1, '5': 9, '10': 'token'},
    {'1': 'tool_call', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCall', '9': 0, '10': 'toolCall', '17': true},
    {'1': 'tool_result', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolResult', '9': 1, '10': 'toolResult', '17': true},
    {'1': 'result', '3': 8, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCallingResult', '9': 2, '10': 'result', '17': true},
    {'1': 'error_message', '3': 9, '4': 1, '5': 9, '9': 3, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 10, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_tool_call'},
    {'1': '_tool_result'},
    {'1': '_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `ToolCallingStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingStreamEventDescriptor = $convert.base64Decode(
    'ChZUb29sQ2FsbGluZ1N0cmVhbUV2ZW50EhAKA3NlcRgBIAEoBFIDc2VxEiEKDHRpbWVzdGFtcF'
    '91cxgCIAEoA1ILdGltZXN0YW1wVXMSJwoPY29udmVyc2F0aW9uX2lkGAMgASgJUg5jb252ZXJz'
    'YXRpb25JZBI+CgRraW5kGAQgASgOMioucnVuYW55d2hlcmUudjEuVG9vbENhbGxpbmdTdHJlYW'
    '1FdmVudEtpbmRSBGtpbmQSFAoFdG9rZW4YBSABKAlSBXRva2VuEjoKCXRvb2xfY2FsbBgGIAEo'
    'CzIYLnJ1bmFueXdoZXJlLnYxLlRvb2xDYWxsSABSCHRvb2xDYWxsiAEBEkAKC3Rvb2xfcmVzdW'
    'x0GAcgASgLMhoucnVuYW55d2hlcmUudjEuVG9vbFJlc3VsdEgBUgp0b29sUmVzdWx0iAEBEj4K'
    'BnJlc3VsdBgIIAEoCzIhLnJ1bmFueXdoZXJlLnYxLlRvb2xDYWxsaW5nUmVzdWx0SAJSBnJlc3'
    'VsdIgBARIoCg1lcnJvcl9tZXNzYWdlGAkgASgJSANSDGVycm9yTWVzc2FnZYgBARIdCgplcnJv'
    'cl9jb2RlGAogASgFUgllcnJvckNvZGVCDAoKX3Rvb2xfY2FsbEIOCgxfdG9vbF9yZXN1bHRCCQ'
    'oHX3Jlc3VsdEIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use toolRegistrySnapshotDescriptor instead')
const ToolRegistrySnapshot$json = {
  '1': 'ToolRegistrySnapshot',
  '2': [
    {'1': 'tools', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolDefinition', '10': 'tools'},
    {'1': 'updated_at_ms', '3': 2, '4': 1, '5': 3, '10': 'updatedAtMs'},
  ],
};

/// Descriptor for `ToolRegistrySnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolRegistrySnapshotDescriptor = $convert.base64Decode(
    'ChRUb29sUmVnaXN0cnlTbmFwc2hvdBI0CgV0b29scxgBIAMoCzIeLnJ1bmFueXdoZXJlLnYxLl'
    'Rvb2xEZWZpbml0aW9uUgV0b29scxIiCg11cGRhdGVkX2F0X21zGAIgASgDUgt1cGRhdGVkQXRN'
    'cw==');

@$core.Deprecated('Use toolCallingSessionCreateRequestDescriptor instead')
const ToolCallingSessionCreateRequest$json = {
  '1': 'ToolCallingSessionCreateRequest',
  '2': [
    {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    {'1': 'max_tokens', '3': 11, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'temperature', '3': 12, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'top_p', '3': 13, '4': 1, '5': 2, '10': 'topP'},
    {'1': 'system_prompt', '3': 14, '4': 1, '5': 9, '10': 'systemPrompt'},
    {'1': 'tools', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolDefinition', '10': 'tools'},
    {'1': 'format_hint', '3': 3, '4': 1, '5': 9, '10': 'formatHint'},
    {'1': 'max_iterations', '3': 4, '4': 1, '5': 13, '10': 'maxIterations'},
    {'1': 'keep_tools_available', '3': 5, '4': 1, '5': 8, '10': 'keepToolsAvailable'},
    {'1': 'validate_calls', '3': 6, '4': 1, '5': 8, '10': 'validateCalls'},
  ],
};

/// Descriptor for `ToolCallingSessionCreateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingSessionCreateRequestDescriptor = $convert.base64Decode(
    'Ch9Ub29sQ2FsbGluZ1Nlc3Npb25DcmVhdGVSZXF1ZXN0EhYKBnByb21wdBgBIAEoCVIGcHJvbX'
    'B0Eh0KCm1heF90b2tlbnMYCyABKAVSCW1heFRva2VucxIgCgt0ZW1wZXJhdHVyZRgMIAEoAlIL'
    'dGVtcGVyYXR1cmUSEwoFdG9wX3AYDSABKAJSBHRvcFASIwoNc3lzdGVtX3Byb21wdBgOIAEoCV'
    'IMc3lzdGVtUHJvbXB0EjQKBXRvb2xzGAIgAygLMh4ucnVuYW55d2hlcmUudjEuVG9vbERlZmlu'
    'aXRpb25SBXRvb2xzEh8KC2Zvcm1hdF9oaW50GAMgASgJUgpmb3JtYXRIaW50EiUKDm1heF9pdG'
    'VyYXRpb25zGAQgASgNUg1tYXhJdGVyYXRpb25zEjAKFGtlZXBfdG9vbHNfYXZhaWxhYmxlGAUg'
    'ASgIUhJrZWVwVG9vbHNBdmFpbGFibGUSJQoOdmFsaWRhdGVfY2FsbHMYBiABKAhSDXZhbGlkYX'
    'RlQ2FsbHM=');

@$core.Deprecated('Use toolCallingSessionCreateResultDescriptor instead')
const ToolCallingSessionCreateResult$json = {
  '1': 'ToolCallingSessionCreateResult',
  '2': [
    {'1': 'session_handle', '3': 1, '4': 1, '5': 4, '10': 'sessionHandle'},
  ],
};

/// Descriptor for `ToolCallingSessionCreateResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingSessionCreateResultDescriptor = $convert.base64Decode(
    'Ch5Ub29sQ2FsbGluZ1Nlc3Npb25DcmVhdGVSZXN1bHQSJQoOc2Vzc2lvbl9oYW5kbGUYASABKA'
    'RSDXNlc3Npb25IYW5kbGU=');

@$core.Deprecated('Use toolCallingSessionEventDescriptor instead')
const ToolCallingSessionEvent$json = {
  '1': 'ToolCallingSessionEvent',
  '2': [
    {'1': 'llm_stream_event_bytes', '3': 1, '4': 1, '5': 12, '9': 0, '10': 'llmStreamEventBytes'},
    {'1': 'tool_call', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCall', '9': 0, '10': 'toolCall'},
    {'1': 'final_result', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.ToolCallingResult', '9': 0, '10': 'finalResult'},
    {'1': 'error_bytes', '3': 4, '4': 1, '5': 12, '9': 0, '10': 'errorBytes'},
    {'1': 'seq', '3': 5, '4': 1, '5': 4, '10': 'seq'},
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `ToolCallingSessionEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingSessionEventDescriptor = $convert.base64Decode(
    'ChdUb29sQ2FsbGluZ1Nlc3Npb25FdmVudBI1ChZsbG1fc3RyZWFtX2V2ZW50X2J5dGVzGAEgAS'
    'gMSABSE2xsbVN0cmVhbUV2ZW50Qnl0ZXMSNwoJdG9vbF9jYWxsGAIgASgLMhgucnVuYW55d2hl'
    'cmUudjEuVG9vbENhbGxIAFIIdG9vbENhbGwSRgoMZmluYWxfcmVzdWx0GAMgASgLMiEucnVuYW'
    '55d2hlcmUudjEuVG9vbENhbGxpbmdSZXN1bHRIAFILZmluYWxSZXN1bHQSIQoLZXJyb3JfYnl0'
    'ZXMYBCABKAxIAFIKZXJyb3JCeXRlcxIQCgNzZXEYBSABKARSA3NlcUIGCgRraW5k');

@$core.Deprecated('Use toolCallingSessionStepWithResultRequestDescriptor instead')
const ToolCallingSessionStepWithResultRequest$json = {
  '1': 'ToolCallingSessionStepWithResultRequest',
  '2': [
    {'1': 'session_handle', '3': 1, '4': 1, '5': 4, '10': 'sessionHandle'},
    {'1': 'tool_call_id', '3': 2, '4': 1, '5': 9, '10': 'toolCallId'},
    {'1': 'result_json', '3': 3, '4': 1, '5': 9, '10': 'resultJson'},
    {'1': 'error', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'error', '17': true},
  ],
  '8': [
    {'1': '_error'},
  ],
};

/// Descriptor for `ToolCallingSessionStepWithResultRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingSessionStepWithResultRequestDescriptor = $convert.base64Decode(
    'CidUb29sQ2FsbGluZ1Nlc3Npb25TdGVwV2l0aFJlc3VsdFJlcXVlc3QSJQoOc2Vzc2lvbl9oYW'
    '5kbGUYASABKARSDXNlc3Npb25IYW5kbGUSIAoMdG9vbF9jYWxsX2lkGAIgASgJUgp0b29sQ2Fs'
    'bElkEh8KC3Jlc3VsdF9qc29uGAMgASgJUgpyZXN1bHRKc29uEhkKBWVycm9yGAQgASgJSABSBW'
    'Vycm9yiAEBQggKBl9lcnJvcg==');

@$core.Deprecated('Use toolCallingSessionDestroyRequestDescriptor instead')
const ToolCallingSessionDestroyRequest$json = {
  '1': 'ToolCallingSessionDestroyRequest',
  '2': [
    {'1': 'session_handle', '3': 1, '4': 1, '5': 4, '10': 'sessionHandle'},
  ],
};

/// Descriptor for `ToolCallingSessionDestroyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolCallingSessionDestroyRequestDescriptor = $convert.base64Decode(
    'CiBUb29sQ2FsbGluZ1Nlc3Npb25EZXN0cm95UmVxdWVzdBIlCg5zZXNzaW9uX2hhbmRsZRgBIA'
    'EoBFINc2Vzc2lvbkhhbmRsZQ==');

const $core.Map<$core.String, $core.dynamic> ToolCallingServiceBase$json = {
  '1': 'ToolCalling',
  '2': [
    {'1': 'Parse', '2': '.runanywhere.v1.ToolParseRequest', '3': '.runanywhere.v1.ToolParseResult'},
    {'1': 'FormatPrompt', '2': '.runanywhere.v1.ToolPromptFormatRequest', '3': '.runanywhere.v1.ToolPromptFormatResult'},
    {'1': 'ValidateCall', '2': '.runanywhere.v1.ToolCallValidationRequest', '3': '.runanywhere.v1.ToolCallValidationResult'},
  ],
};

@$core.Deprecated('Use toolCallingServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> ToolCallingServiceBase$messageJson = {
  '.runanywhere.v1.ToolParseRequest': ToolParseRequest$json,
  '.runanywhere.v1.ToolCallingOptions': ToolCallingOptions$json,
  '.runanywhere.v1.ToolDefinition': ToolDefinition$json,
  '.runanywhere.v1.ToolParameter': ToolParameter$json,
  '.runanywhere.v1.ToolValue': ToolValue$json,
  '.runanywhere.v1.ToolValueArray': ToolValueArray$json,
  '.runanywhere.v1.ToolValueObject': ToolValueObject$json,
  '.runanywhere.v1.ToolValueObject.FieldsEntry': ToolValueObject_FieldsEntry$json,
  '.runanywhere.v1.ToolDefinition.MetadataEntry': ToolDefinition_MetadataEntry$json,
  '.runanywhere.v1.ToolParseResult': ToolParseResult$json,
  '.runanywhere.v1.ToolCall': ToolCall$json,
  '.runanywhere.v1.ToolPromptFormatRequest': ToolPromptFormatRequest$json,
  '.runanywhere.v1.ToolResult': ToolResult$json,
  '.runanywhere.v1.ToolPromptFormatResult': ToolPromptFormatResult$json,
  '.runanywhere.v1.ToolCallValidationRequest': ToolCallValidationRequest$json,
  '.runanywhere.v1.ToolCallValidationResult': ToolCallValidationResult$json,
};

/// Descriptor for `ToolCalling`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List toolCallingServiceDescriptor = $convert.base64Decode(
    'CgtUb29sQ2FsbGluZxJKCgVQYXJzZRIgLnJ1bmFueXdoZXJlLnYxLlRvb2xQYXJzZVJlcXVlc3'
    'QaHy5ydW5hbnl3aGVyZS52MS5Ub29sUGFyc2VSZXN1bHQSXwoMRm9ybWF0UHJvbXB0EicucnVu'
    'YW55d2hlcmUudjEuVG9vbFByb21wdEZvcm1hdFJlcXVlc3QaJi5ydW5hbnl3aGVyZS52MS5Ub2'
    '9sUHJvbXB0Rm9ybWF0UmVzdWx0EmMKDFZhbGlkYXRlQ2FsbBIpLnJ1bmFueXdoZXJlLnYxLlRv'
    'b2xDYWxsVmFsaWRhdGlvblJlcXVlc3QaKC5ydW5hbnl3aGVyZS52MS5Ub29sQ2FsbFZhbGlkYX'
    'Rpb25SZXN1bHQ=');

