///
//  Generated code. Do not modify.
//  source: llm_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use executionTargetDescriptor instead')
const ExecutionTarget$json = const {
  '1': 'ExecutionTarget',
  '2': const [
    const {'1': 'EXECUTION_TARGET_UNSPECIFIED', '2': 0},
    const {'1': 'EXECUTION_TARGET_ON_DEVICE', '2': 1},
    const {'1': 'EXECUTION_TARGET_CLOUD', '2': 2},
    const {'1': 'EXECUTION_TARGET_AUTO', '2': 3},
  ],
};

/// Descriptor for `ExecutionTarget`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List executionTargetDescriptor = $convert.base64Decode('Cg9FeGVjdXRpb25UYXJnZXQSIAocRVhFQ1VUSU9OX1RBUkdFVF9VTlNQRUNJRklFRBAAEh4KGkVYRUNVVElPTl9UQVJHRVRfT05fREVWSUNFEAESGgoWRVhFQ1VUSU9OX1RBUkdFVF9DTE9VRBACEhkKFUVYRUNVVElPTl9UQVJHRVRfQVVUTxAD');
@$core.Deprecated('Use lLMGenerationOptionsDescriptor instead')
const LLMGenerationOptions$json = const {
  '1': 'LLMGenerationOptions',
  '2': const [
    const {'1': 'max_tokens', '3': 1, '4': 1, '5': 5, '10': 'maxTokens'},
    const {'1': 'temperature', '3': 2, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'top_p', '3': 3, '4': 1, '5': 2, '10': 'topP'},
    const {'1': 'top_k', '3': 4, '4': 1, '5': 5, '10': 'topK'},
    const {'1': 'repetition_penalty', '3': 5, '4': 1, '5': 2, '10': 'repetitionPenalty'},
    const {'1': 'stop_sequences', '3': 6, '4': 3, '5': 9, '10': 'stopSequences'},
    const {'1': 'streaming_enabled', '3': 7, '4': 1, '5': 8, '10': 'streamingEnabled'},
    const {'1': 'preferred_framework', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'preferredFramework'},
    const {'1': 'system_prompt', '3': 9, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    const {'1': 'json_schema', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'jsonSchema', '17': true},
    const {'1': 'thinking_pattern', '3': 11, '4': 1, '5': 11, '6': '.runanywhere.v1.ThinkingTagPattern', '9': 2, '10': 'thinkingPattern', '17': true},
    const {'1': 'execution_target', '3': 12, '4': 1, '5': 14, '6': '.runanywhere.v1.ExecutionTarget', '9': 3, '10': 'executionTarget', '17': true},
    const {'1': 'structured_output', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.StructuredOutputOptions', '9': 4, '10': 'structuredOutput', '17': true},
  ],
  '8': const [
    const {'1': '_system_prompt'},
    const {'1': '_json_schema'},
    const {'1': '_thinking_pattern'},
    const {'1': '_execution_target'},
    const {'1': '_structured_output'},
  ],
};

/// Descriptor for `LLMGenerationOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerationOptionsDescriptor = $convert.base64Decode('ChRMTE1HZW5lcmF0aW9uT3B0aW9ucxIdCgptYXhfdG9rZW5zGAEgASgFUgltYXhUb2tlbnMSIAoLdGVtcGVyYXR1cmUYAiABKAJSC3RlbXBlcmF0dXJlEhMKBXRvcF9wGAMgASgCUgR0b3BQEhMKBXRvcF9rGAQgASgFUgR0b3BLEi0KEnJlcGV0aXRpb25fcGVuYWx0eRgFIAEoAlIRcmVwZXRpdGlvblBlbmFsdHkSJQoOc3RvcF9zZXF1ZW5jZXMYBiADKAlSDXN0b3BTZXF1ZW5jZXMSKwoRc3RyZWFtaW5nX2VuYWJsZWQYByABKAhSEHN0cmVhbWluZ0VuYWJsZWQSUwoTcHJlZmVycmVkX2ZyYW1ld29yaxgIIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya1IScHJlZmVycmVkRnJhbWV3b3JrEigKDXN5c3RlbV9wcm9tcHQYCSABKAlIAFIMc3lzdGVtUHJvbXB0iAEBEiQKC2pzb25fc2NoZW1hGAogASgJSAFSCmpzb25TY2hlbWGIAQESUgoQdGhpbmtpbmdfcGF0dGVybhgLIAEoCzIiLnJ1bmFueXdoZXJlLnYxLlRoaW5raW5nVGFnUGF0dGVybkgCUg90aGlua2luZ1BhdHRlcm6IAQESTwoQZXhlY3V0aW9uX3RhcmdldBgMIAEoDjIfLnJ1bmFueXdoZXJlLnYxLkV4ZWN1dGlvblRhcmdldEgDUg9leGVjdXRpb25UYXJnZXSIAQESWQoRc3RydWN0dXJlZF9vdXRwdXQYDSABKAsyJy5ydW5hbnl3aGVyZS52MS5TdHJ1Y3R1cmVkT3V0cHV0T3B0aW9uc0gEUhBzdHJ1Y3R1cmVkT3V0cHV0iAEBQhAKDl9zeXN0ZW1fcHJvbXB0Qg4KDF9qc29uX3NjaGVtYUITChFfdGhpbmtpbmdfcGF0dGVybkITChFfZXhlY3V0aW9uX3RhcmdldEIUChJfc3RydWN0dXJlZF9vdXRwdXQ=');
@$core.Deprecated('Use lLMGenerationResultDescriptor instead')
const LLMGenerationResult$json = const {
  '1': 'LLMGenerationResult',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'thinking_content', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'thinkingContent', '17': true},
    const {'1': 'input_tokens', '3': 3, '4': 1, '5': 5, '10': 'inputTokens'},
    const {'1': 'tokens_generated', '3': 4, '4': 1, '5': 5, '10': 'tokensGenerated'},
    const {'1': 'model_used', '3': 5, '4': 1, '5': 9, '10': 'modelUsed'},
    const {'1': 'generation_time_ms', '3': 6, '4': 1, '5': 1, '10': 'generationTimeMs'},
    const {'1': 'ttft_ms', '3': 7, '4': 1, '5': 1, '9': 1, '10': 'ttftMs', '17': true},
    const {'1': 'tokens_per_second', '3': 8, '4': 1, '5': 1, '10': 'tokensPerSecond'},
    const {'1': 'framework', '3': 9, '4': 1, '5': 9, '9': 2, '10': 'framework', '17': true},
    const {'1': 'finish_reason', '3': 10, '4': 1, '5': 9, '10': 'finishReason'},
    const {'1': 'thinking_tokens', '3': 11, '4': 1, '5': 5, '10': 'thinkingTokens'},
    const {'1': 'response_tokens', '3': 12, '4': 1, '5': 5, '10': 'responseTokens'},
    const {'1': 'json_output', '3': 13, '4': 1, '5': 9, '9': 3, '10': 'jsonOutput', '17': true},
    const {'1': 'performance', '3': 14, '4': 1, '5': 11, '6': '.runanywhere.v1.PerformanceMetrics', '9': 4, '10': 'performance', '17': true},
    const {'1': 'executed_on', '3': 15, '4': 1, '5': 14, '6': '.runanywhere.v1.ExecutionTarget', '9': 5, '10': 'executedOn', '17': true},
  ],
  '8': const [
    const {'1': '_thinking_content'},
    const {'1': '_ttft_ms'},
    const {'1': '_framework'},
    const {'1': '_json_output'},
    const {'1': '_performance'},
    const {'1': '_executed_on'},
  ],
};

/// Descriptor for `LLMGenerationResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMGenerationResultDescriptor = $convert.base64Decode('ChNMTE1HZW5lcmF0aW9uUmVzdWx0EhIKBHRleHQYASABKAlSBHRleHQSLgoQdGhpbmtpbmdfY29udGVudBgCIAEoCUgAUg90aGlua2luZ0NvbnRlbnSIAQESIQoMaW5wdXRfdG9rZW5zGAMgASgFUgtpbnB1dFRva2VucxIpChB0b2tlbnNfZ2VuZXJhdGVkGAQgASgFUg90b2tlbnNHZW5lcmF0ZWQSHQoKbW9kZWxfdXNlZBgFIAEoCVIJbW9kZWxVc2VkEiwKEmdlbmVyYXRpb25fdGltZV9tcxgGIAEoAVIQZ2VuZXJhdGlvblRpbWVNcxIcCgd0dGZ0X21zGAcgASgBSAFSBnR0ZnRNc4gBARIqChF0b2tlbnNfcGVyX3NlY29uZBgIIAEoAVIPdG9rZW5zUGVyU2Vjb25kEiEKCWZyYW1ld29yaxgJIAEoCUgCUglmcmFtZXdvcmuIAQESIwoNZmluaXNoX3JlYXNvbhgKIAEoCVIMZmluaXNoUmVhc29uEicKD3RoaW5raW5nX3Rva2VucxgLIAEoBVIOdGhpbmtpbmdUb2tlbnMSJwoPcmVzcG9uc2VfdG9rZW5zGAwgASgFUg5yZXNwb25zZVRva2VucxIkCgtqc29uX291dHB1dBgNIAEoCUgDUgpqc29uT3V0cHV0iAEBEkkKC3BlcmZvcm1hbmNlGA4gASgLMiIucnVuYW55d2hlcmUudjEuUGVyZm9ybWFuY2VNZXRyaWNzSARSC3BlcmZvcm1hbmNliAEBEkUKC2V4ZWN1dGVkX29uGA8gASgOMh8ucnVuYW55d2hlcmUudjEuRXhlY3V0aW9uVGFyZ2V0SAVSCmV4ZWN1dGVkT26IAQFCEwoRX3RoaW5raW5nX2NvbnRlbnRCCgoIX3R0ZnRfbXNCDAoKX2ZyYW1ld29ya0IOCgxfanNvbl9vdXRwdXRCDgoMX3BlcmZvcm1hbmNlQg4KDF9leGVjdXRlZF9vbg==');
@$core.Deprecated('Use lLMConfigurationDescriptor instead')
const LLMConfiguration$json = const {
  '1': 'LLMConfiguration',
  '2': const [
    const {'1': 'context_length', '3': 1, '4': 1, '5': 5, '10': 'contextLength'},
    const {'1': 'temperature', '3': 2, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
    const {'1': 'system_prompt', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    const {'1': 'streaming', '3': 5, '4': 1, '5': 8, '10': 'streaming'},
  ],
  '8': const [
    const {'1': '_system_prompt'},
  ],
};

/// Descriptor for `LLMConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List lLMConfigurationDescriptor = $convert.base64Decode('ChBMTE1Db25maWd1cmF0aW9uEiUKDmNvbnRleHRfbGVuZ3RoGAEgASgFUg1jb250ZXh0TGVuZ3RoEiAKC3RlbXBlcmF0dXJlGAIgASgCUgt0ZW1wZXJhdHVyZRIdCgptYXhfdG9rZW5zGAMgASgFUgltYXhUb2tlbnMSKAoNc3lzdGVtX3Byb21wdBgEIAEoCUgAUgxzeXN0ZW1Qcm9tcHSIAQESHAoJc3RyZWFtaW5nGAUgASgIUglzdHJlYW1pbmdCEAoOX3N5c3RlbV9wcm9tcHQ=');
@$core.Deprecated('Use generationHintsDescriptor instead')
const GenerationHints$json = const {
  '1': 'GenerationHints',
  '2': const [
    const {'1': 'temperature', '3': 1, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'max_tokens', '3': 2, '4': 1, '5': 5, '10': 'maxTokens'},
    const {'1': 'system_role', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'systemRole', '17': true},
  ],
  '8': const [
    const {'1': '_system_role'},
  ],
};

/// Descriptor for `GenerationHints`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generationHintsDescriptor = $convert.base64Decode('Cg9HZW5lcmF0aW9uSGludHMSIAoLdGVtcGVyYXR1cmUYASABKAJSC3RlbXBlcmF0dXJlEh0KCm1heF90b2tlbnMYAiABKAVSCW1heFRva2VucxIkCgtzeXN0ZW1fcm9sZRgDIAEoCUgAUgpzeXN0ZW1Sb2xliAEBQg4KDF9zeXN0ZW1fcm9sZQ==');
@$core.Deprecated('Use thinkingTagPatternDescriptor instead')
const ThinkingTagPattern$json = const {
  '1': 'ThinkingTagPattern',
  '2': const [
    const {'1': 'opening_tag', '3': 1, '4': 1, '5': 9, '10': 'openingTag'},
    const {'1': 'closing_tag', '3': 2, '4': 1, '5': 9, '10': 'closingTag'},
  ],
};

/// Descriptor for `ThinkingTagPattern`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List thinkingTagPatternDescriptor = $convert.base64Decode('ChJUaGlua2luZ1RhZ1BhdHRlcm4SHwoLb3BlbmluZ190YWcYASABKAlSCm9wZW5pbmdUYWcSHwoLY2xvc2luZ190YWcYAiABKAlSCmNsb3NpbmdUYWc=');
@$core.Deprecated('Use streamTokenDescriptor instead')
const StreamToken$json = const {
  '1': 'StreamToken',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    const {'1': 'index', '3': 3, '4': 1, '5': 5, '10': 'index'},
  ],
};

/// Descriptor for `StreamToken`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamTokenDescriptor = $convert.base64Decode('CgtTdHJlYW1Ub2tlbhISCgR0ZXh0GAEgASgJUgR0ZXh0EiEKDHRpbWVzdGFtcF9tcxgCIAEoA1ILdGltZXN0YW1wTXMSFAoFaW5kZXgYAyABKAVSBWluZGV4');
@$core.Deprecated('Use performanceMetricsDescriptor instead')
const PerformanceMetrics$json = const {
  '1': 'PerformanceMetrics',
  '2': const [
    const {'1': 'latency_ms', '3': 1, '4': 1, '5': 3, '10': 'latencyMs'},
    const {'1': 'memory_bytes', '3': 2, '4': 1, '5': 3, '10': 'memoryBytes'},
    const {'1': 'throughput_tokens_per_sec', '3': 3, '4': 1, '5': 2, '10': 'throughputTokensPerSec'},
    const {'1': 'prompt_tokens', '3': 4, '4': 1, '5': 5, '10': 'promptTokens'},
    const {'1': 'completion_tokens', '3': 5, '4': 1, '5': 5, '10': 'completionTokens'},
  ],
};

/// Descriptor for `PerformanceMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List performanceMetricsDescriptor = $convert.base64Decode('ChJQZXJmb3JtYW5jZU1ldHJpY3MSHQoKbGF0ZW5jeV9tcxgBIAEoA1IJbGF0ZW5jeU1zEiEKDG1lbW9yeV9ieXRlcxgCIAEoA1ILbWVtb3J5Qnl0ZXMSOQoZdGhyb3VnaHB1dF90b2tlbnNfcGVyX3NlYxgDIAEoAlIWdGhyb3VnaHB1dFRva2Vuc1BlclNlYxIjCg1wcm9tcHRfdG9rZW5zGAQgASgFUgxwcm9tcHRUb2tlbnMSKwoRY29tcGxldGlvbl90b2tlbnMYBSABKAVSEGNvbXBsZXRpb25Ub2tlbnM=');
