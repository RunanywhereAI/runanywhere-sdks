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

@$core.Deprecated('Use lLMStreamEventKindDescriptor instead')
const LLMStreamEventKind$json = {
  '1': 'LLMStreamEventKind',
  '2': [
    {'1': 'LLM_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'LLM_STREAM_EVENT_KIND_STARTED', '2': 1},
    {'1': 'LLM_STREAM_EVENT_KIND_TOKEN', '2': 2},
    {'1': 'LLM_STREAM_EVENT_KIND_THINKING', '2': 3},
    {'1': 'LLM_STREAM_EVENT_KIND_TOOL_CALL', '2': 4},
    {'1': 'LLM_STREAM_EVENT_KIND_PROGRESS', '2': 5},
    {'1': 'LLM_STREAM_EVENT_KIND_COMPLETED', '2': 6},
    {'1': 'LLM_STREAM_EVENT_KIND_ERROR', '2': 7},
  ],
};

/// Descriptor for `LLMStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List lLMStreamEventKindDescriptor = $convert.base64Decode(
    'ChJMTE1TdHJlYW1FdmVudEtpbmQSJQohTExNX1NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSU'
    'VEEAASIQodTExNX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVJURUQQARIfChtMTE1fU1RSRUFNX0VW'
    'RU5UX0tJTkRfVE9LRU4QAhIiCh5MTE1fU1RSRUFNX0VWRU5UX0tJTkRfVEhJTktJTkcQAxIjCh'
    '9MTE1fU1RSRUFNX0VWRU5UX0tJTkRfVE9PTF9DQUxMEAQSIgoeTExNX1NUUkVBTV9FVkVOVF9L'
    'SU5EX1BST0dSRVNTEAUSIwofTExNX1NUUkVBTV9FVkVOVF9LSU5EX0NPTVBMRVRFRBAGEh8KG0'
    'xMTV9TVFJFQU1fRVZFTlRfS0lORF9FUlJPUhAH');

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
    {'1': 'repetition_penalty', '3': 8, '4': 1, '5': 2, '10': 'repetitionPenalty'},
    {'1': 'stop_sequences', '3': 9, '4': 3, '5': 9, '10': 'stopSequences'},
    {'1': 'streaming_enabled', '3': 10, '4': 1, '5': 8, '10': 'streamingEnabled'},
    {'1': 'preferred_framework', '3': 11, '4': 1, '5': 9, '10': 'preferredFramework'},
    {'1': 'json_schema', '3': 12, '4': 1, '5': 9, '10': 'jsonSchema'},
    {'1': 'execution_target', '3': 13, '4': 1, '5': 9, '10': 'executionTarget'},
    {'1': 'request_id', '3': 14, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'model_id', '3': 15, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'conversation_id', '3': 16, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'seed', '3': 17, '4': 1, '5': 3, '10': 'seed'},
    {'1': 'frequency_penalty', '3': 18, '4': 1, '5': 2, '10': 'frequencyPenalty'},
    {'1': 'presence_penalty', '3': 19, '4': 1, '5': 2, '10': 'presencePenalty'},
    {'1': 'min_p', '3': 20, '4': 1, '5': 2, '10': 'minP'},
    {'1': 'grammar', '3': 21, '4': 1, '5': 9, '10': 'grammar'},
    {'1': 'response_format', '3': 22, '4': 1, '5': 9, '10': 'responseFormat'},
    {'1': 'echo_prompt', '3': 23, '4': 1, '5': 8, '10': 'echoPrompt'},
    {'1': 'n_threads', '3': 24, '4': 1, '5': 5, '10': 'nThreads'},
    {'1': 'metadata', '3': 25, '4': 3, '5': 11, '6': '.runanywhere.v1.LLMGenerateRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [LLMGenerateRequest_MetadataEntry$json],
};

@$core.Deprecated('Use lLMGenerateRequestDescriptor instead')
const LLMGenerateRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `LLMGenerateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerateRequestDescriptor = $convert.base64Decode(
    'ChJMTE1HZW5lcmF0ZVJlcXVlc3QSFgoGcHJvbXB0GAEgASgJUgZwcm9tcHQSHQoKbWF4X3Rva2'
    'VucxgCIAEoBVIJbWF4VG9rZW5zEiAKC3RlbXBlcmF0dXJlGAMgASgCUgt0ZW1wZXJhdHVyZRIT'
    'CgV0b3BfcBgEIAEoAlIEdG9wUBITCgV0b3BfaxgFIAEoBVIEdG9wSxIjCg1zeXN0ZW1fcHJvbX'
    'B0GAYgASgJUgxzeXN0ZW1Qcm9tcHQSIwoNZW1pdF90aG91Z2h0cxgHIAEoCFIMZW1pdFRob3Vn'
    'aHRzEi0KEnJlcGV0aXRpb25fcGVuYWx0eRgIIAEoAlIRcmVwZXRpdGlvblBlbmFsdHkSJQoOc3'
    'RvcF9zZXF1ZW5jZXMYCSADKAlSDXN0b3BTZXF1ZW5jZXMSKwoRc3RyZWFtaW5nX2VuYWJsZWQY'
    'CiABKAhSEHN0cmVhbWluZ0VuYWJsZWQSLwoTcHJlZmVycmVkX2ZyYW1ld29yaxgLIAEoCVIScH'
    'JlZmVycmVkRnJhbWV3b3JrEh8KC2pzb25fc2NoZW1hGAwgASgJUgpqc29uU2NoZW1hEikKEGV4'
    'ZWN1dGlvbl90YXJnZXQYDSABKAlSD2V4ZWN1dGlvblRhcmdldBIdCgpyZXF1ZXN0X2lkGA4gAS'
    'gJUglyZXF1ZXN0SWQSGQoIbW9kZWxfaWQYDyABKAlSB21vZGVsSWQSJwoPY29udmVyc2F0aW9u'
    'X2lkGBAgASgJUg5jb252ZXJzYXRpb25JZBISCgRzZWVkGBEgASgDUgRzZWVkEisKEWZyZXF1ZW'
    '5jeV9wZW5hbHR5GBIgASgCUhBmcmVxdWVuY3lQZW5hbHR5EikKEHByZXNlbmNlX3BlbmFsdHkY'
    'EyABKAJSD3ByZXNlbmNlUGVuYWx0eRITCgVtaW5fcBgUIAEoAlIEbWluUBIYCgdncmFtbWFyGB'
    'UgASgJUgdncmFtbWFyEicKD3Jlc3BvbnNlX2Zvcm1hdBgWIAEoCVIOcmVzcG9uc2VGb3JtYXQS'
    'HwoLZWNob19wcm9tcHQYFyABKAhSCmVjaG9Qcm9tcHQSGwoJbl90aHJlYWRzGBggASgFUghuVG'
    'hyZWFkcxJMCghtZXRhZGF0YRgZIAMoCzIwLnJ1bmFueXdoZXJlLnYxLkxMTUdlbmVyYXRlUmVx'
    'dWVzdC5NZXRhZGF0YUVudHJ5UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIA'
    'EoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use lLMStreamFinalResultDescriptor instead')
const LLMStreamFinalResult$json = {
  '1': 'LLMStreamFinalResult',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'thinking_content', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'thinkingContent', '17': true},
    {'1': 'prompt_tokens', '3': 3, '4': 1, '5': 5, '10': 'promptTokens'},
    {'1': 'completion_tokens', '3': 4, '4': 1, '5': 5, '10': 'completionTokens'},
    {'1': 'total_tokens', '3': 5, '4': 1, '5': 5, '10': 'totalTokens'},
    {'1': 'total_time_ms', '3': 6, '4': 1, '5': 3, '10': 'totalTimeMs'},
    {'1': 'time_to_first_token_ms', '3': 7, '4': 1, '5': 3, '10': 'timeToFirstTokenMs'},
    {'1': 'tokens_per_second', '3': 8, '4': 1, '5': 2, '10': 'tokensPerSecond'},
    {'1': 'finish_reason', '3': 9, '4': 1, '5': 9, '10': 'finishReason'},
    {'1': 'error_code', '3': 10, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'error_message', '3': 11, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'prompt_eval_time_ms', '3': 12, '4': 1, '5': 3, '10': 'promptEvalTimeMs'},
    {'1': 'decode_time_ms', '3': 13, '4': 1, '5': 3, '10': 'decodeTimeMs'},
  ],
  '8': [
    {'1': '_thinking_content'},
  ],
};

/// Descriptor for `LLMStreamFinalResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMStreamFinalResultDescriptor = $convert.base64Decode(
    'ChRMTE1TdHJlYW1GaW5hbFJlc3VsdBISCgR0ZXh0GAEgASgJUgR0ZXh0Ei4KEHRoaW5raW5nX2'
    'NvbnRlbnQYAiABKAlIAFIPdGhpbmtpbmdDb250ZW50iAEBEiMKDXByb21wdF90b2tlbnMYAyAB'
    'KAVSDHByb21wdFRva2VucxIrChFjb21wbGV0aW9uX3Rva2VucxgEIAEoBVIQY29tcGxldGlvbl'
    'Rva2VucxIhCgx0b3RhbF90b2tlbnMYBSABKAVSC3RvdGFsVG9rZW5zEiIKDXRvdGFsX3RpbWVf'
    'bXMYBiABKANSC3RvdGFsVGltZU1zEjIKFnRpbWVfdG9fZmlyc3RfdG9rZW5fbXMYByABKANSEn'
    'RpbWVUb0ZpcnN0VG9rZW5NcxIqChF0b2tlbnNfcGVyX3NlY29uZBgIIAEoAlIPdG9rZW5zUGVy'
    'U2Vjb25kEiMKDWZpbmlzaF9yZWFzb24YCSABKAlSDGZpbmlzaFJlYXNvbhIdCgplcnJvcl9jb2'
    'RlGAogASgFUgllcnJvckNvZGUSIwoNZXJyb3JfbWVzc2FnZRgLIAEoCVIMZXJyb3JNZXNzYWdl'
    'Ei0KE3Byb21wdF9ldmFsX3RpbWVfbXMYDCABKANSEHByb21wdEV2YWxUaW1lTXMSJAoOZGVjb2'
    'RlX3RpbWVfbXMYDSABKANSDGRlY29kZVRpbWVNc0ITChFfdGhpbmtpbmdfY29udGVudA==');

@$core.Deprecated('Use lLMStreamEventDescriptor instead')
const LLMStreamEvent$json = {
  '1': 'LLMStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'token', '3': 3, '4': 1, '5': 9, '10': 'token'},
    {'1': 'is_final', '3': 4, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'kind', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.LLMTokenKind', '10': 'kind'},
    {'1': 'token_id', '3': 6, '4': 1, '5': 13, '10': 'tokenId'},
    {'1': 'logprob', '3': 7, '4': 1, '5': 2, '10': 'logprob'},
    {'1': 'finish_reason', '3': 8, '4': 1, '5': 9, '10': 'finishReason'},
    {'1': 'error_message', '3': 9, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'result', '3': 10, '4': 1, '5': 11, '6': '.runanywhere.v1.LLMStreamFinalResult', '9': 0, '10': 'result', '17': true},
    {'1': 'error_code', '3': 11, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'event_kind', '3': 12, '4': 1, '5': 14, '6': '.runanywhere.v1.LLMStreamEventKind', '10': 'eventKind'},
    {'1': 'request_id', '3': 13, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'conversation_id', '3': 14, '4': 1, '5': 9, '10': 'conversationId'},
    {'1': 'prompt_tokens_processed', '3': 15, '4': 1, '5': 5, '10': 'promptTokensProcessed'},
    {'1': 'completion_tokens_generated', '3': 16, '4': 1, '5': 5, '10': 'completionTokensGenerated'},
    {'1': 'elapsed_ms', '3': 17, '4': 1, '5': 3, '10': 'elapsedMs'},
  ],
  '8': [
    {'1': '_result'},
  ],
};

/// Descriptor for `LLMStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMStreamEventDescriptor = $convert.base64Decode(
    'Cg5MTE1TdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKA'
    'NSC3RpbWVzdGFtcFVzEhQKBXRva2VuGAMgASgJUgV0b2tlbhIZCghpc19maW5hbBgEIAEoCFIH'
    'aXNGaW5hbBIwCgRraW5kGAUgASgOMhwucnVuYW55d2hlcmUudjEuTExNVG9rZW5LaW5kUgRraW'
    '5kEhkKCHRva2VuX2lkGAYgASgNUgd0b2tlbklkEhgKB2xvZ3Byb2IYByABKAJSB2xvZ3Byb2IS'
    'IwoNZmluaXNoX3JlYXNvbhgIIAEoCVIMZmluaXNoUmVhc29uEiMKDWVycm9yX21lc3NhZ2UYCS'
    'ABKAlSDGVycm9yTWVzc2FnZRJBCgZyZXN1bHQYCiABKAsyJC5ydW5hbnl3aGVyZS52MS5MTE1T'
    'dHJlYW1GaW5hbFJlc3VsdEgAUgZyZXN1bHSIAQESHQoKZXJyb3JfY29kZRgLIAEoBVIJZXJyb3'
    'JDb2RlEkEKCmV2ZW50X2tpbmQYDCABKA4yIi5ydW5hbnl3aGVyZS52MS5MTE1TdHJlYW1FdmVu'
    'dEtpbmRSCWV2ZW50S2luZBIdCgpyZXF1ZXN0X2lkGA0gASgJUglyZXF1ZXN0SWQSJwoPY29udm'
    'Vyc2F0aW9uX2lkGA4gASgJUg5jb252ZXJzYXRpb25JZBI2Chdwcm9tcHRfdG9rZW5zX3Byb2Nl'
    'c3NlZBgPIAEoBVIVcHJvbXB0VG9rZW5zUHJvY2Vzc2VkEj4KG2NvbXBsZXRpb25fdG9rZW5zX2'
    'dlbmVyYXRlZBgQIAEoBVIZY29tcGxldGlvblRva2Vuc0dlbmVyYXRlZBIdCgplbGFwc2VkX21z'
    'GBEgASgDUgllbGFwc2VkTXNCCQoHX3Jlc3VsdA==');

const $core.Map<$core.String, $core.dynamic> LLMServiceBase$json = {
  '1': 'LLM',
  '2': [
    {'1': 'Generate', '2': '.runanywhere.v1.LLMGenerateRequest', '3': '.runanywhere.v1.LLMStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use lLMServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> LLMServiceBase$messageJson = {
  '.runanywhere.v1.LLMGenerateRequest': LLMGenerateRequest$json,
  '.runanywhere.v1.LLMGenerateRequest.MetadataEntry': LLMGenerateRequest_MetadataEntry$json,
  '.runanywhere.v1.LLMStreamEvent': LLMStreamEvent$json,
  '.runanywhere.v1.LLMStreamFinalResult': LLMStreamFinalResult$json,
};

/// Descriptor for `LLM`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List lLMServiceDescriptor = $convert.base64Decode(
    'CgNMTE0SUAoIR2VuZXJhdGUSIi5ydW5hbnl3aGVyZS52MS5MTE1HZW5lcmF0ZVJlcXVlc3QaHi'
    '5ydW5hbnl3aGVyZS52MS5MTE1TdHJlYW1FdmVudDAB');

