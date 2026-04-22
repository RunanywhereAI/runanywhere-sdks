//
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use lLMTokenKindDescriptor instead')
const LLMTokenKind$json = {
  '1': 'LLMTokenKind',
  '2': [
    {'1': 'LLM_TOKEN_KIND_UNSPECIFIED', '2': 0},
    {'1': 'LLM_TOKEN_KIND_ANSWER', '2': 1},
    {'1': 'LLM_TOKEN_KIND_THOUGHT', '2': 2},
    {'1': 'LLM_TOKEN_KIND_TOOL_CALL', '2': 3},
  ],
};

/// Descriptor for `LLMTokenKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List lLMTokenKindDescriptor = $convert.base64Decode(
    'CgxMTE1Ub2tlbktpbmQSHgoaTExNX1RPS0VOX0tJTkRfVU5TUEVDSUZJRUQQABIZChVMTE1fVE'
    '9LRU5fS0lORF9BTlNXRVIQARIaChZMTE1fVE9LRU5fS0lORF9USE9VR0hUEAISHAoYTExNX1RP'
    'S0VOX0tJTkRfVE9PTF9DQUxMEAM=');

@$core.Deprecated('Use lLMGenerateRequestDescriptor instead')
const LLMGenerateRequest$json = {
  '1': 'LLMGenerateRequest',
  '2': [
    {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    {'1': 'max_tokens', '3': 2, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'temperature', '3': 3, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'top_p', '3': 4, '4': 1, '5': 2, '10': 'topP'},
    {'1': 'top_k', '3': 5, '4': 1, '5': 5, '10': 'topK'},
    {'1': 'system_prompt', '3': 6, '4': 1, '5': 9, '10': 'systemPrompt'},
    {'1': 'emit_thoughts', '3': 7, '4': 1, '5': 8, '10': 'emitThoughts'},
  ],
};

/// Descriptor for `LLMGenerateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerateRequestDescriptor = $convert.base64Decode(
    'ChJMTE1HZW5lcmF0ZVJlcXVlc3QSFgoGcHJvbXB0GAEgASgJUgZwcm9tcHQSHQoKbWF4X3Rva2'
    'VucxgCIAEoBVIJbWF4VG9rZW5zEiAKC3RlbXBlcmF0dXJlGAMgASgCUgt0ZW1wZXJhdHVyZRIT'
    'CgV0b3BfcBgEIAEoAlIEdG9wUBITCgV0b3BfaxgFIAEoBVIEdG9wSxIjCg1zeXN0ZW1fcHJvbX'
    'B0GAYgASgJUgxzeXN0ZW1Qcm9tcHQSIwoNZW1pdF90aG91Z2h0cxgHIAEoCFIMZW1pdFRob3Vn'
    'aHRz');

@$core.Deprecated('Use lLMTokenDescriptor instead')
const LLMToken$json = {
  '1': 'LLMToken',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'kind', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.LLMTokenKind', '10': 'kind'},
    {'1': 'logprob', '3': 4, '4': 1, '5': 2, '10': 'logprob'},
    {'1': 'emit_us', '3': 5, '4': 1, '5': 3, '10': 'emitUs'},
  ],
};

/// Descriptor for `LLMToken`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMTokenDescriptor = $convert.base64Decode(
    'CghMTE1Ub2tlbhISCgR0ZXh0GAEgASgJUgR0ZXh0EhkKCGlzX2ZpbmFsGAIgASgIUgdpc0Zpbm'
    'FsEjAKBGtpbmQYAyABKA4yHC5ydW5hbnl3aGVyZS52MS5MTE1Ub2tlbktpbmRSBGtpbmQSGAoH'
    'bG9ncHJvYhgEIAEoAlIHbG9ncHJvYhIXCgdlbWl0X3VzGAUgASgDUgZlbWl0VXM=');

