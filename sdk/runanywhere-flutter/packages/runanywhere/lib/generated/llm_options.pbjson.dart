//
//  Generated code. Do not modify.
//  source: llm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use executionTargetDescriptor instead')
const ExecutionTarget$json = {
  '1': 'ExecutionTarget',
  '2': [
    {'1': 'EXECUTION_TARGET_UNSPECIFIED', '2': 0},
    {'1': 'EXECUTION_TARGET_ON_DEVICE', '2': 1},
    {'1': 'EXECUTION_TARGET_CLOUD', '2': 2},
    {'1': 'EXECUTION_TARGET_AUTO', '2': 3},
  ],
};

/// Descriptor for `ExecutionTarget`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List executionTargetDescriptor = $convert.base64Decode(
    'Cg9FeGVjdXRpb25UYXJnZXQSIAocRVhFQ1VUSU9OX1RBUkdFVF9VTlNQRUNJRklFRBAAEh4KGk'
    'VYRUNVVElPTl9UQVJHRVRfT05fREVWSUNFEAESGgoWRVhFQ1VUSU9OX1RBUkdFVF9DTE9VRBAC'
    'EhkKFUVYRUNVVElPTl9UQVJHRVRfQVVUTxAD');

@$core.Deprecated('Use lLMGenerationOptionsDescriptor instead')
const LLMGenerationOptions$json = {
  '1': 'LLMGenerationOptions',
  '2': [
    {'1': 'max_tokens', '3': 1, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'temperature', '3': 2, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'top_p', '3': 3, '4': 1, '5': 2, '10': 'topP'},
    {'1': 'top_k', '3': 4, '4': 1, '5': 5, '10': 'topK'},
    {'1': 'repetition_penalty', '3': 5, '4': 1, '5': 2, '10': 'repetitionPenalty'},
    {'1': 'stop_sequences', '3': 6, '4': 3, '5': 9, '10': 'stopSequences'},
    {'1': 'streaming_enabled', '3': 7, '4': 1, '5': 8, '10': 'streamingEnabled'},
    {'1': 'preferred_framework', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'preferredFramework'},
    {'1': 'system_prompt', '3': 9, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'json_schema', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'jsonSchema', '17': true},
    {'1': 'thinking_pattern', '3': 11, '4': 1, '5': 11, '6': '.runanywhere.v1.ThinkingTagPattern', '9': 2, '10': 'thinkingPattern', '17': true},
    {'1': 'execution_target', '3': 12, '4': 1, '5': 14, '6': '.runanywhere.v1.ExecutionTarget', '9': 3, '10': 'executionTarget', '17': true},
    {'1': 'structured_output', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputOptions', '9': 4, '10': 'structuredOutput', '17': true},
    {'1': 'enable_real_time_tracking', '3': 14, '4': 1, '5': 8, '10': 'enableRealTimeTracking'},
  ],
  '8': [
    {'1': '_system_prompt'},
    {'1': '_json_schema'},
    {'1': '_thinking_pattern'},
    {'1': '_execution_target'},
    {'1': '_structured_output'},
  ],
};

/// Descriptor for `LLMGenerationOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerationOptionsDescriptor = $convert.base64Decode(
    'ChRMTE1HZW5lcmF0aW9uT3B0aW9ucxIdCgptYXhfdG9rZW5zGAEgASgFUgltYXhUb2tlbnMSIA'
    'oLdGVtcGVyYXR1cmUYAiABKAJSC3RlbXBlcmF0dXJlEhMKBXRvcF9wGAMgASgCUgR0b3BQEhMK'
    'BXRvcF9rGAQgASgFUgR0b3BLEi0KEnJlcGV0aXRpb25fcGVuYWx0eRgFIAEoAlIRcmVwZXRpdG'
    'lvblBlbmFsdHkSJQoOc3RvcF9zZXF1ZW5jZXMYBiADKAlSDXN0b3BTZXF1ZW5jZXMSKwoRc3Ry'
    'ZWFtaW5nX2VuYWJsZWQYByABKAhSEHN0cmVhbWluZ0VuYWJsZWQSUwoTcHJlZmVycmVkX2ZyYW'
    '1ld29yaxgIIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya1IScHJlZmVy'
    'cmVkRnJhbWV3b3JrEigKDXN5c3RlbV9wcm9tcHQYCSABKAlIAFIMc3lzdGVtUHJvbXB0iAEBEi'
    'QKC2pzb25fc2NoZW1hGAogASgJSAFSCmpzb25TY2hlbWGIAQESUgoQdGhpbmtpbmdfcGF0dGVy'
    'bhgLIAEoCzIiLnJ1bmFueXdoZXJlLnYxLlRoaW5raW5nVGFnUGF0dGVybkgCUg90aGlua2luZ1'
    'BhdHRlcm6IAQESTwoQZXhlY3V0aW9uX3RhcmdldBgMIAEoDjIfLnJ1bmFueXdoZXJlLnYxLkV4'
    'ZWN1dGlvblRhcmdldEgDUg9leGVjdXRpb25UYXJnZXSIAQESWQoRc3RydWN0dXJlZF9vdXRwdX'
    'QYDSABKAsyJy5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0T3B0aW9uc0gEUhBzdHJ1'
    'Y3R1cmVkT3V0cHV0iAEBEjkKGWVuYWJsZV9yZWFsX3RpbWVfdHJhY2tpbmcYDiABKAhSFmVuYW'
    'JsZVJlYWxUaW1lVHJhY2tpbmdCEAoOX3N5c3RlbV9wcm9tcHRCDgoMX2pzb25fc2NoZW1hQhMK'
    'EV90aGlua2luZ19wYXR0ZXJuQhMKEV9leGVjdXRpb25fdGFyZ2V0QhQKEl9zdHJ1Y3R1cmVkX2'
    '91dHB1dA==');

@$core.Deprecated('Use lLMGenerationResultDescriptor instead')
const LLMGenerationResult$json = {
  '1': 'LLMGenerationResult',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'thinking_content', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'thinkingContent', '17': true},
    {'1': 'input_tokens', '3': 3, '4': 1, '5': 5, '10': 'inputTokens'},
    {'1': 'tokens_generated', '3': 4, '4': 1, '5': 5, '10': 'tokensGenerated'},
    {'1': 'model_used', '3': 5, '4': 1, '5': 9, '10': 'modelUsed'},
    {'1': 'generation_time_ms', '3': 6, '4': 1, '5': 1, '10': 'generationTimeMs'},
    {'1': 'ttft_ms', '3': 7, '4': 1, '5': 1, '9': 1, '10': 'ttftMs', '17': true},
    {'1': 'tokens_per_second', '3': 8, '4': 1, '5': 1, '10': 'tokensPerSecond'},
    {'1': 'framework', '3': 9, '4': 1, '5': 9, '9': 2, '10': 'framework', '17': true},
    {'1': 'finish_reason', '3': 10, '4': 1, '5': 9, '10': 'finishReason'},
    {'1': 'thinking_tokens', '3': 11, '4': 1, '5': 5, '10': 'thinkingTokens'},
    {'1': 'response_tokens', '3': 12, '4': 1, '5': 5, '10': 'responseTokens'},
    {'1': 'json_output', '3': 13, '4': 1, '5': 9, '9': 3, '10': 'jsonOutput', '17': true},
    {'1': 'performance', '3': 14, '4': 1, '5': 11, '6': '.runanywhere.v1.PerformanceMetrics', '9': 4, '10': 'performance', '17': true},
    {'1': 'executed_on', '3': 15, '4': 1, '5': 14, '6': '.runanywhere.v1.ExecutionTarget', '9': 5, '10': 'executedOn', '17': true},
    {'1': 'structured_output_validation', '3': 16, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputValidation', '9': 6, '10': 'structuredOutputValidation', '17': true},
    {'1': 'total_tokens', '3': 17, '4': 1, '5': 5, '10': 'totalTokens'},
    {'1': 'error_message', '3': 18, '4': 1, '5': 9, '9': 7, '10': 'errorMessage', '17': true},
  ],
  '8': [
    {'1': '_thinking_content'},
    {'1': '_ttft_ms'},
    {'1': '_framework'},
    {'1': '_json_output'},
    {'1': '_performance'},
    {'1': '_executed_on'},
    {'1': '_structured_output_validation'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `LLMGenerationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerationResultDescriptor = $convert.base64Decode(
    'ChNMTE1HZW5lcmF0aW9uUmVzdWx0EhIKBHRleHQYASABKAlSBHRleHQSLgoQdGhpbmtpbmdfY2'
    '9udGVudBgCIAEoCUgAUg90aGlua2luZ0NvbnRlbnSIAQESIQoMaW5wdXRfdG9rZW5zGAMgASgF'
    'UgtpbnB1dFRva2VucxIpChB0b2tlbnNfZ2VuZXJhdGVkGAQgASgFUg90b2tlbnNHZW5lcmF0ZW'
    'QSHQoKbW9kZWxfdXNlZBgFIAEoCVIJbW9kZWxVc2VkEiwKEmdlbmVyYXRpb25fdGltZV9tcxgG'
    'IAEoAVIQZ2VuZXJhdGlvblRpbWVNcxIcCgd0dGZ0X21zGAcgASgBSAFSBnR0ZnRNc4gBARIqCh'
    'F0b2tlbnNfcGVyX3NlY29uZBgIIAEoAVIPdG9rZW5zUGVyU2Vjb25kEiEKCWZyYW1ld29yaxgJ'
    'IAEoCUgCUglmcmFtZXdvcmuIAQESIwoNZmluaXNoX3JlYXNvbhgKIAEoCVIMZmluaXNoUmVhc2'
    '9uEicKD3RoaW5raW5nX3Rva2VucxgLIAEoBVIOdGhpbmtpbmdUb2tlbnMSJwoPcmVzcG9uc2Vf'
    'dG9rZW5zGAwgASgFUg5yZXNwb25zZVRva2VucxIkCgtqc29uX291dHB1dBgNIAEoCUgDUgpqc2'
    '9uT3V0cHV0iAEBEkkKC3BlcmZvcm1hbmNlGA4gASgLMiIucnVuYW55d2hlcmUudjEuUGVyZm9y'
    'bWFuY2VNZXRyaWNzSARSC3BlcmZvcm1hbmNliAEBEkUKC2V4ZWN1dGVkX29uGA8gASgOMh8ucn'
    'VuYW55d2hlcmUudjEuRXhlY3V0aW9uVGFyZ2V0SAVSCmV4ZWN1dGVkT26IAQEScQocc3RydWN0'
    'dXJlZF9vdXRwdXRfdmFsaWRhdGlvbhgQIAEoCzIqLnJ1bmFueXdoZXJlLnYxLlN0cnVjdHVyZW'
    'RPdXRwdXRWYWxpZGF0aW9uSAZSGnN0cnVjdHVyZWRPdXRwdXRWYWxpZGF0aW9uiAEBEiEKDHRv'
    'dGFsX3Rva2VucxgRIAEoBVILdG90YWxUb2tlbnMSKAoNZXJyb3JfbWVzc2FnZRgSIAEoCUgHUg'
    'xlcnJvck1lc3NhZ2WIAQFCEwoRX3RoaW5raW5nX2NvbnRlbnRCCgoIX3R0ZnRfbXNCDAoKX2Zy'
    'YW1ld29ya0IOCgxfanNvbl9vdXRwdXRCDgoMX3BlcmZvcm1hbmNlQg4KDF9leGVjdXRlZF9vbk'
    'IfCh1fc3RydWN0dXJlZF9vdXRwdXRfdmFsaWRhdGlvbkIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use lLMConfigurationDescriptor instead')
const LLMConfiguration$json = {
  '1': 'LLMConfiguration',
  '2': [
    {'1': 'context_length', '3': 1, '4': 1, '5': 5, '10': 'contextLength'},
    {'1': 'temperature', '3': 2, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'system_prompt', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'streaming', '3': 5, '4': 1, '5': 8, '10': 'streaming'},
    {'1': 'model_id', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'modelId', '17': true},
    {'1': 'preferred_framework', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 2, '10': 'preferredFramework', '17': true},
  ],
  '8': [
    {'1': '_system_prompt'},
    {'1': '_model_id'},
    {'1': '_preferred_framework'},
  ],
};

/// Descriptor for `LLMConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMConfigurationDescriptor = $convert.base64Decode(
    'ChBMTE1Db25maWd1cmF0aW9uEiUKDmNvbnRleHRfbGVuZ3RoGAEgASgFUg1jb250ZXh0TGVuZ3'
    'RoEiAKC3RlbXBlcmF0dXJlGAIgASgCUgt0ZW1wZXJhdHVyZRIdCgptYXhfdG9rZW5zGAMgASgF'
    'UgltYXhUb2tlbnMSKAoNc3lzdGVtX3Byb21wdBgEIAEoCUgAUgxzeXN0ZW1Qcm9tcHSIAQESHA'
    'oJc3RyZWFtaW5nGAUgASgIUglzdHJlYW1pbmcSHgoIbW9kZWxfaWQYBiABKAlIAVIHbW9kZWxJ'
    'ZIgBARJYChNwcmVmZXJyZWRfZnJhbWV3b3JrGAcgASgOMiIucnVuYW55d2hlcmUudjEuSW5mZX'
    'JlbmNlRnJhbWV3b3JrSAJSEnByZWZlcnJlZEZyYW1ld29ya4gBAUIQCg5fc3lzdGVtX3Byb21w'
    'dEILCglfbW9kZWxfaWRCFgoUX3ByZWZlcnJlZF9mcmFtZXdvcms=');

@$core.Deprecated('Use generationHintsDescriptor instead')
const GenerationHints$json = {
  '1': 'GenerationHints',
  '2': [
    {'1': 'temperature', '3': 1, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'max_tokens', '3': 2, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'system_role', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'systemRole', '17': true},
  ],
  '8': [
    {'1': '_system_role'},
  ],
};

/// Descriptor for `GenerationHints`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generationHintsDescriptor = $convert.base64Decode(
    'Cg9HZW5lcmF0aW9uSGludHMSIAoLdGVtcGVyYXR1cmUYASABKAJSC3RlbXBlcmF0dXJlEh0KCm'
    '1heF90b2tlbnMYAiABKAVSCW1heFRva2VucxIkCgtzeXN0ZW1fcm9sZRgDIAEoCUgAUgpzeXN0'
    'ZW1Sb2xliAEBQg4KDF9zeXN0ZW1fcm9sZQ==');

@$core.Deprecated('Use thinkingTagPatternDescriptor instead')
const ThinkingTagPattern$json = {
  '1': 'ThinkingTagPattern',
  '2': [
    {'1': 'opening_tag', '3': 1, '4': 1, '5': 9, '10': 'openingTag'},
    {'1': 'closing_tag', '3': 2, '4': 1, '5': 9, '10': 'closingTag'},
  ],
};

/// Descriptor for `ThinkingTagPattern`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thinkingTagPatternDescriptor = $convert.base64Decode(
    'ChJUaGlua2luZ1RhZ1BhdHRlcm4SHwoLb3BlbmluZ190YWcYASABKAlSCm9wZW5pbmdUYWcSHw'
    'oLY2xvc2luZ190YWcYAiABKAlSCmNsb3NpbmdUYWc=');

@$core.Deprecated('Use streamTokenDescriptor instead')
const StreamToken$json = {
  '1': 'StreamToken',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'index', '3': 3, '4': 1, '5': 5, '10': 'index'},
  ],
};

/// Descriptor for `StreamToken`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamTokenDescriptor = $convert.base64Decode(
    'CgtTdHJlYW1Ub2tlbhISCgR0ZXh0GAEgASgJUgR0ZXh0EiEKDHRpbWVzdGFtcF9tcxgCIAEoA1'
    'ILdGltZXN0YW1wTXMSFAoFaW5kZXgYAyABKAVSBWluZGV4');

@$core.Deprecated('Use performanceMetricsDescriptor instead')
const PerformanceMetrics$json = {
  '1': 'PerformanceMetrics',
  '2': [
    {'1': 'latency_ms', '3': 1, '4': 1, '5': 3, '10': 'latencyMs'},
    {'1': 'memory_bytes', '3': 2, '4': 1, '5': 3, '10': 'memoryBytes'},
    {'1': 'throughput_tokens_per_sec', '3': 3, '4': 1, '5': 2, '10': 'throughputTokensPerSec'},
    {'1': 'prompt_tokens', '3': 4, '4': 1, '5': 5, '10': 'promptTokens'},
    {'1': 'completion_tokens', '3': 5, '4': 1, '5': 5, '10': 'completionTokens'},
  ],
};

/// Descriptor for `PerformanceMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List performanceMetricsDescriptor = $convert.base64Decode(
    'ChJQZXJmb3JtYW5jZU1ldHJpY3MSHQoKbGF0ZW5jeV9tcxgBIAEoA1IJbGF0ZW5jeU1zEiEKDG'
    '1lbW9yeV9ieXRlcxgCIAEoA1ILbWVtb3J5Qnl0ZXMSOQoZdGhyb3VnaHB1dF90b2tlbnNfcGVy'
    'X3NlYxgDIAEoAlIWdGhyb3VnaHB1dFRva2Vuc1BlclNlYxIjCg1wcm9tcHRfdG9rZW5zGAQgAS'
    'gFUgxwcm9tcHRUb2tlbnMSKwoRY29tcGxldGlvbl90b2tlbnMYBSABKAVSEGNvbXBsZXRpb25U'
    'b2tlbnM=');

