///
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use lLMTokenKindDescriptor instead')
const LLMTokenKind$json = const {
  '1': 'LLMTokenKind',
  '2': const [
    const {'1': 'LLM_TOKEN_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'LLM_TOKEN_KIND_ANSWER', '2': 1},
    const {'1': 'LLM_TOKEN_KIND_THOUGHT', '2': 2},
    const {'1': 'LLM_TOKEN_KIND_TOOL_CALL', '2': 3},
  ],
};

/// Descriptor for `LLMTokenKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List lLMTokenKindDescriptor = $convert.base64Decode('CgxMTE1Ub2tlbktpbmQSHgoaTExNX1RPS0VOX0tJTkRfVU5TUEVDSUZJRUQQABIZChVMTE1fVE9LRU5fS0lORF9BTlNXRVIQARIaChZMTE1fVE9LRU5fS0lORF9USE9VR0hUEAISHAoYTExNX1RPS0VOX0tJTkRfVE9PTF9DQUxMEAM=');
@$core.Deprecated('Use lLMGenerateRequestDescriptor instead')
const LLMGenerateRequest$json = const {
  '1': 'LLMGenerateRequest',
  '2': const [
    const {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    const {'1': 'max_tokens', '3': 2, '4': 1, '5': 5, '10': 'maxTokens'},
    const {'1': 'temperature', '3': 3, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'top_p', '3': 4, '4': 1, '5': 2, '10': 'topP'},
    const {'1': 'top_k', '3': 5, '4': 1, '5': 5, '10': 'topK'},
    const {'1': 'system_prompt', '3': 6, '4': 1, '5': 9, '10': 'systemPrompt'},
    const {'1': 'emit_thoughts', '3': 7, '4': 1, '5': 8, '10': 'emitThoughts'},
  ],
};

/// Descriptor for `LLMGenerateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerateRequestDescriptor = $convert.base64Decode('ChJMTE1HZW5lcmF0ZVJlcXVlc3QSFgoGcHJvbXB0GAEgASgJUgZwcm9tcHQSHQoKbWF4X3Rva2VucxgCIAEoBVIJbWF4VG9rZW5zEiAKC3RlbXBlcmF0dXJlGAMgASgCUgt0ZW1wZXJhdHVyZRITCgV0b3BfcBgEIAEoAlIEdG9wUBITCgV0b3BfaxgFIAEoBVIEdG9wSxIjCg1zeXN0ZW1fcHJvbXB0GAYgASgJUgxzeXN0ZW1Qcm9tcHQSIwoNZW1pdF90aG91Z2h0cxgHIAEoCFIMZW1pdFRob3VnaHRz');
@$core.Deprecated('Use lLMStreamEventDescriptor instead')
const LLMStreamEvent$json = const {
  '1': 'LLMStreamEvent',
  '2': const [
    const {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    const {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    const {'1': 'token', '3': 3, '4': 1, '5': 9, '10': 'token'},
    const {'1': 'is_final', '3': 4, '4': 1, '5': 8, '10': 'isFinal'},
    const {'1': 'kind', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.LLMTokenKind', '10': 'kind'},
    const {'1': 'token_id', '3': 6, '4': 1, '5': 13, '10': 'tokenId'},
    const {'1': 'logprob', '3': 7, '4': 1, '5': 2, '10': 'logprob'},
    const {'1': 'finish_reason', '3': 8, '4': 1, '5': 9, '10': 'finishReason'},
    const {'1': 'error_message', '3': 9, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `LLMStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMStreamEventDescriptor = $convert.base64Decode('Cg5MTE1TdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKANSC3RpbWVzdGFtcFVzEhQKBXRva2VuGAMgASgJUgV0b2tlbhIZCghpc19maW5hbBgEIAEoCFIHaXNGaW5hbBIwCgRraW5kGAUgASgOMhwucnVuYW55d2hlcmUudjEuTExNVG9rZW5LaW5kUgRraW5kEhkKCHRva2VuX2lkGAYgASgNUgd0b2tlbklkEhgKB2xvZ3Byb2IYByABKAJSB2xvZ3Byb2ISIwoNZmluaXNoX3JlYXNvbhgIIAEoCVIMZmluaXNoUmVhc29uEiMKDWVycm9yX21lc3NhZ2UYCSABKAlSDGVycm9yTWVzc2FnZQ==');
const $core.Map<$core.String, $core.dynamic> LLMServiceBase$json = const {
  '1': 'LLM',
  '2': const [
    const {'1': 'Generate', '2': '.runanywhere.v1.LLMGenerateRequest', '3': '.runanywhere.v1.LLMStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use lLMServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> LLMServiceBase$messageJson = const {
  '.runanywhere.v1.LLMGenerateRequest': LLMGenerateRequest$json,
  '.runanywhere.v1.LLMStreamEvent': LLMStreamEvent$json,
};

/// Descriptor for `LLM`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List lLMServiceDescriptor = $convert.base64Decode('CgNMTE0SUAoIR2VuZXJhdGUSIi5ydW5hbnl3aGVyZS52MS5MTE1HZW5lcmF0ZVJlcXVlc3QaHi5ydW5hbnl3aGVyZS52MS5MTE1TdHJlYW1FdmVudDAB');
