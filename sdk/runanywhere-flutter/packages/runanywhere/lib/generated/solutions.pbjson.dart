///
//  Generated code. Do not modify.
//  source: solutions.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use solutionTypeDescriptor instead')
const SolutionType$json = const {
  '1': 'SolutionType',
  '2': const [
    const {'1': 'SOLUTION_TYPE_UNSPECIFIED', '2': 0},
    const {'1': 'SOLUTION_TYPE_VOICE_AGENT', '2': 1},
    const {'1': 'SOLUTION_TYPE_RAG', '2': 2},
    const {'1': 'SOLUTION_TYPE_WAKEWORD', '2': 3},
    const {'1': 'SOLUTION_TYPE_TIME_SERIES', '2': 4},
    const {'1': 'SOLUTION_TYPE_AGENT_LOOP', '2': 5},
  ],
};

/// Descriptor for `SolutionType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List solutionTypeDescriptor = $convert.base64Decode('CgxTb2x1dGlvblR5cGUSHQoZU09MVVRJT05fVFlQRV9VTlNQRUNJRklFRBAAEh0KGVNPTFVUSU9OX1RZUEVfVk9JQ0VfQUdFTlQQARIVChFTT0xVVElPTl9UWVBFX1JBRxACEhoKFlNPTFVUSU9OX1RZUEVfV0FLRVdPUkQQAxIdChlTT0xVVElPTl9UWVBFX1RJTUVfU0VSSUVTEAQSHAoYU09MVVRJT05fVFlQRV9BR0VOVF9MT09QEAU=');
@$core.Deprecated('Use audioSourceDescriptor instead')
const AudioSource$json = const {
  '1': 'AudioSource',
  '2': const [
    const {'1': 'AUDIO_SOURCE_UNSPECIFIED', '2': 0},
    const {'1': 'AUDIO_SOURCE_MICROPHONE', '2': 1},
    const {'1': 'AUDIO_SOURCE_FILE', '2': 2},
    const {'1': 'AUDIO_SOURCE_CALLBACK', '2': 3},
  ],
};

/// Descriptor for `AudioSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioSourceDescriptor = $convert.base64Decode('CgtBdWRpb1NvdXJjZRIcChhBVURJT19TT1VSQ0VfVU5TUEVDSUZJRUQQABIbChdBVURJT19TT1VSQ0VfTUlDUk9QSE9ORRABEhUKEUFVRElPX1NPVVJDRV9GSUxFEAISGQoVQVVESU9fU09VUkNFX0NBTExCQUNLEAM=');
@$core.Deprecated('Use vectorStoreDescriptor instead')
const VectorStore$json = const {
  '1': 'VectorStore',
  '2': const [
    const {'1': 'VECTOR_STORE_UNSPECIFIED', '2': 0},
    const {'1': 'VECTOR_STORE_USEARCH', '2': 1},
    const {'1': 'VECTOR_STORE_PGVECTOR', '2': 2},
  ],
};

/// Descriptor for `VectorStore`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vectorStoreDescriptor = $convert.base64Decode('CgtWZWN0b3JTdG9yZRIcChhWRUNUT1JfU1RPUkVfVU5TUEVDSUZJRUQQABIYChRWRUNUT1JfU1RPUkVfVVNFQVJDSBABEhkKFVZFQ1RPUl9TVE9SRV9QR1ZFQ1RPUhAC');
@$core.Deprecated('Use solutionConfigDescriptor instead')
const SolutionConfig$json = const {
  '1': 'SolutionConfig',
  '2': const [
    const {'1': 'voice_agent', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceAgentConfig', '9': 0, '10': 'voiceAgent'},
    const {'1': 'rag', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGConfig', '9': 0, '10': 'rag'},
    const {'1': 'wake_word', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.WakeWordConfig', '9': 0, '10': 'wakeWord'},
    const {'1': 'agent_loop', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.AgentLoopConfig', '9': 0, '10': 'agentLoop'},
    const {'1': 'time_series', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.TimeSeriesConfig', '9': 0, '10': 'timeSeries'},
  ],
  '8': const [
    const {'1': 'config'},
  ],
};

/// Descriptor for `SolutionConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List solutionConfigDescriptor = $convert.base64Decode('Cg5Tb2x1dGlvbkNvbmZpZxJDCgt2b2ljZV9hZ2VudBgBIAEoCzIgLnJ1bmFueXdoZXJlLnYxLlZvaWNlQWdlbnRDb25maWdIAFIKdm9pY2VBZ2VudBItCgNyYWcYAiABKAsyGS5ydW5hbnl3aGVyZS52MS5SQUdDb25maWdIAFIDcmFnEj0KCXdha2Vfd29yZBgDIAEoCzIeLnJ1bmFueXdoZXJlLnYxLldha2VXb3JkQ29uZmlnSABSCHdha2VXb3JkEkAKCmFnZW50X2xvb3AYBCABKAsyHy5ydW5hbnl3aGVyZS52MS5BZ2VudExvb3BDb25maWdIAFIJYWdlbnRMb29wEkMKC3RpbWVfc2VyaWVzGAUgASgLMiAucnVuYW55d2hlcmUudjEuVGltZVNlcmllc0NvbmZpZ0gAUgp0aW1lU2VyaWVzQggKBmNvbmZpZw==');
@$core.Deprecated('Use solutionHandleDescriptor instead')
const SolutionHandle$json = const {
  '1': 'SolutionHandle',
  '2': const [
    const {'1': 'handle_id', '3': 1, '4': 1, '5': 9, '10': 'handleId'},
    const {'1': 'solution_type', '3': 2, '4': 1, '5': 9, '10': 'solutionType'},
    const {'1': 'created_at_ms', '3': 3, '4': 1, '5': 3, '10': 'createdAtMs'},
    const {'1': 'state', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'state', '17': true},
  ],
  '8': const [
    const {'1': '_state'},
  ],
};

/// Descriptor for `SolutionHandle`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List solutionHandleDescriptor = $convert.base64Decode('Cg5Tb2x1dGlvbkhhbmRsZRIbCgloYW5kbGVfaWQYASABKAlSCGhhbmRsZUlkEiMKDXNvbHV0aW9uX3R5cGUYAiABKAlSDHNvbHV0aW9uVHlwZRIiCg1jcmVhdGVkX2F0X21zGAMgASgDUgtjcmVhdGVkQXRNcxIZCgVzdGF0ZRgEIAEoCUgAUgVzdGF0ZYgBAUIICgZfc3RhdGU=');
@$core.Deprecated('Use voiceAgentConfigDescriptor instead')
const VoiceAgentConfig$json = const {
  '1': 'VoiceAgentConfig',
  '2': const [
    const {'1': 'llm_model_id', '3': 1, '4': 1, '5': 9, '10': 'llmModelId'},
    const {'1': 'stt_model_id', '3': 2, '4': 1, '5': 9, '10': 'sttModelId'},
    const {'1': 'tts_model_id', '3': 3, '4': 1, '5': 9, '10': 'ttsModelId'},
    const {'1': 'vad_model_id', '3': 4, '4': 1, '5': 9, '10': 'vadModelId'},
    const {'1': 'sample_rate_hz', '3': 5, '4': 1, '5': 5, '10': 'sampleRateHz'},
    const {'1': 'chunk_ms', '3': 6, '4': 1, '5': 5, '10': 'chunkMs'},
    const {'1': 'audio_source', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioSource', '10': 'audioSource'},
    const {'1': 'audio_file_path', '3': 15, '4': 1, '5': 9, '10': 'audioFilePath'},
    const {'1': 'enable_barge_in', '3': 8, '4': 1, '5': 8, '10': 'enableBargeIn'},
    const {'1': 'barge_in_threshold_ms', '3': 9, '4': 1, '5': 5, '10': 'bargeInThresholdMs'},
    const {'1': 'system_prompt', '3': 10, '4': 1, '5': 9, '10': 'systemPrompt'},
    const {'1': 'max_context_tokens', '3': 11, '4': 1, '5': 5, '10': 'maxContextTokens'},
    const {'1': 'temperature', '3': 12, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'emit_partials', '3': 13, '4': 1, '5': 8, '10': 'emitPartials'},
    const {'1': 'emit_thoughts', '3': 14, '4': 1, '5': 8, '10': 'emitThoughts'},
    const {'1': 'type_kind', '3': 16, '4': 1, '5': 14, '6': '.runanywhere.v1.SolutionType', '9': 0, '10': 'typeKind', '17': true},
  ],
  '8': const [
    const {'1': '_type_kind'},
  ],
};

/// Descriptor for `VoiceAgentConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentConfigDescriptor = $convert.base64Decode('ChBWb2ljZUFnZW50Q29uZmlnEiAKDGxsbV9tb2RlbF9pZBgBIAEoCVIKbGxtTW9kZWxJZBIgCgxzdHRfbW9kZWxfaWQYAiABKAlSCnN0dE1vZGVsSWQSIAoMdHRzX21vZGVsX2lkGAMgASgJUgp0dHNNb2RlbElkEiAKDHZhZF9tb2RlbF9pZBgEIAEoCVIKdmFkTW9kZWxJZBIkCg5zYW1wbGVfcmF0ZV9oehgFIAEoBVIMc2FtcGxlUmF0ZUh6EhkKCGNodW5rX21zGAYgASgFUgdjaHVua01zEj4KDGF1ZGlvX3NvdXJjZRgHIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkF1ZGlvU291cmNlUgthdWRpb1NvdXJjZRImCg9hdWRpb19maWxlX3BhdGgYDyABKAlSDWF1ZGlvRmlsZVBhdGgSJgoPZW5hYmxlX2JhcmdlX2luGAggASgIUg1lbmFibGVCYXJnZUluEjEKFWJhcmdlX2luX3RocmVzaG9sZF9tcxgJIAEoBVISYmFyZ2VJblRocmVzaG9sZE1zEiMKDXN5c3RlbV9wcm9tcHQYCiABKAlSDHN5c3RlbVByb21wdBIsChJtYXhfY29udGV4dF90b2tlbnMYCyABKAVSEG1heENvbnRleHRUb2tlbnMSIAoLdGVtcGVyYXR1cmUYDCABKAJSC3RlbXBlcmF0dXJlEiMKDWVtaXRfcGFydGlhbHMYDSABKAhSDGVtaXRQYXJ0aWFscxIjCg1lbWl0X3Rob3VnaHRzGA4gASgIUgxlbWl0VGhvdWdodHMSPgoJdHlwZV9raW5kGBAgASgOMhwucnVuYW55d2hlcmUudjEuU29sdXRpb25UeXBlSABSCHR5cGVLaW5kiAEBQgwKCl90eXBlX2tpbmQ=');
@$core.Deprecated('Use rAGConfigDescriptor instead')
const RAGConfig$json = const {
  '1': 'RAGConfig',
  '2': const [
    const {'1': 'embed_model_id', '3': 1, '4': 1, '5': 9, '10': 'embedModelId'},
    const {'1': 'rerank_model_id', '3': 2, '4': 1, '5': 9, '10': 'rerankModelId'},
    const {'1': 'llm_model_id', '3': 3, '4': 1, '5': 9, '10': 'llmModelId'},
    const {'1': 'vector_store', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.VectorStore', '10': 'vectorStore'},
    const {'1': 'vector_store_path', '3': 5, '4': 1, '5': 9, '10': 'vectorStorePath'},
    const {'1': 'retrieve_k', '3': 6, '4': 1, '5': 5, '10': 'retrieveK'},
    const {'1': 'rerank_top', '3': 7, '4': 1, '5': 5, '10': 'rerankTop'},
    const {'1': 'bm25_k1', '3': 8, '4': 1, '5': 2, '10': 'bm25K1'},
    const {'1': 'bm25_b', '3': 9, '4': 1, '5': 2, '10': 'bm25B'},
    const {'1': 'rrf_k', '3': 10, '4': 1, '5': 5, '10': 'rrfK'},
    const {'1': 'prompt_template', '3': 11, '4': 1, '5': 9, '10': 'promptTemplate'},
    const {'1': 'type_kind', '3': 12, '4': 1, '5': 14, '6': '.runanywhere.v1.SolutionType', '9': 0, '10': 'typeKind', '17': true},
  ],
  '8': const [
    const {'1': '_type_kind'},
  ],
};

/// Descriptor for `RAGConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGConfigDescriptor = $convert.base64Decode('CglSQUdDb25maWcSJAoOZW1iZWRfbW9kZWxfaWQYASABKAlSDGVtYmVkTW9kZWxJZBImCg9yZXJhbmtfbW9kZWxfaWQYAiABKAlSDXJlcmFua01vZGVsSWQSIAoMbGxtX21vZGVsX2lkGAMgASgJUgpsbG1Nb2RlbElkEj4KDHZlY3Rvcl9zdG9yZRgEIAEoDjIbLnJ1bmFueXdoZXJlLnYxLlZlY3RvclN0b3JlUgt2ZWN0b3JTdG9yZRIqChF2ZWN0b3Jfc3RvcmVfcGF0aBgFIAEoCVIPdmVjdG9yU3RvcmVQYXRoEh0KCnJldHJpZXZlX2sYBiABKAVSCXJldHJpZXZlSxIdCgpyZXJhbmtfdG9wGAcgASgFUglyZXJhbmtUb3ASFwoHYm0yNV9rMRgIIAEoAlIGYm0yNUsxEhUKBmJtMjVfYhgJIAEoAlIFYm0yNUISEwoFcnJmX2sYCiABKAVSBHJyZksSJwoPcHJvbXB0X3RlbXBsYXRlGAsgASgJUg5wcm9tcHRUZW1wbGF0ZRI+Cgl0eXBlX2tpbmQYDCABKA4yHC5ydW5hbnl3aGVyZS52MS5Tb2x1dGlvblR5cGVIAFIIdHlwZUtpbmSIAQFCDAoKX3R5cGVfa2luZA==');
@$core.Deprecated('Use wakeWordConfigDescriptor instead')
const WakeWordConfig$json = const {
  '1': 'WakeWordConfig',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'keyword', '3': 2, '4': 1, '5': 9, '10': 'keyword'},
    const {'1': 'threshold', '3': 3, '4': 1, '5': 2, '10': 'threshold'},
    const {'1': 'pre_roll_ms', '3': 4, '4': 1, '5': 5, '10': 'preRollMs'},
    const {'1': 'sample_rate_hz', '3': 5, '4': 1, '5': 5, '10': 'sampleRateHz'},
    const {'1': 'type_kind', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.SolutionType', '9': 0, '10': 'typeKind', '17': true},
  ],
  '8': const [
    const {'1': '_type_kind'},
  ],
};

/// Descriptor for `WakeWordConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wakeWordConfigDescriptor = $convert.base64Decode('Cg5XYWtlV29yZENvbmZpZxIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBIYCgdrZXl3b3JkGAIgASgJUgdrZXl3b3JkEhwKCXRocmVzaG9sZBgDIAEoAlIJdGhyZXNob2xkEh4KC3ByZV9yb2xsX21zGAQgASgFUglwcmVSb2xsTXMSJAoOc2FtcGxlX3JhdGVfaHoYBSABKAVSDHNhbXBsZVJhdGVIehI+Cgl0eXBlX2tpbmQYBiABKA4yHC5ydW5hbnl3aGVyZS52MS5Tb2x1dGlvblR5cGVIAFIIdHlwZUtpbmSIAQFCDAoKX3R5cGVfa2luZA==');
@$core.Deprecated('Use agentLoopConfigDescriptor instead')
const AgentLoopConfig$json = const {
  '1': 'AgentLoopConfig',
  '2': const [
    const {'1': 'llm_model_id', '3': 1, '4': 1, '5': 9, '10': 'llmModelId'},
    const {'1': 'system_prompt', '3': 2, '4': 1, '5': 9, '10': 'systemPrompt'},
    const {'1': 'tools', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolSpec', '10': 'tools'},
    const {'1': 'max_iterations', '3': 4, '4': 1, '5': 5, '10': 'maxIterations'},
    const {'1': 'max_context_tokens', '3': 5, '4': 1, '5': 5, '10': 'maxContextTokens'},
    const {'1': 'type_kind', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.SolutionType', '9': 0, '10': 'typeKind', '17': true},
  ],
  '8': const [
    const {'1': '_type_kind'},
  ],
};

/// Descriptor for `AgentLoopConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentLoopConfigDescriptor = $convert.base64Decode('Cg9BZ2VudExvb3BDb25maWcSIAoMbGxtX21vZGVsX2lkGAEgASgJUgpsbG1Nb2RlbElkEiMKDXN5c3RlbV9wcm9tcHQYAiABKAlSDHN5c3RlbVByb21wdBIuCgV0b29scxgDIAMoCzIYLnJ1bmFueXdoZXJlLnYxLlRvb2xTcGVjUgV0b29scxIlCg5tYXhfaXRlcmF0aW9ucxgEIAEoBVINbWF4SXRlcmF0aW9ucxIsChJtYXhfY29udGV4dF90b2tlbnMYBSABKAVSEG1heENvbnRleHRUb2tlbnMSPgoJdHlwZV9raW5kGAYgASgOMhwucnVuYW55d2hlcmUudjEuU29sdXRpb25UeXBlSABSCHR5cGVLaW5kiAEBQgwKCl90eXBlX2tpbmQ=');
@$core.Deprecated('Use toolSpecDescriptor instead')
const ToolSpec$json = const {
  '1': 'ToolSpec',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    const {'1': 'json_schema', '3': 3, '4': 1, '5': 9, '10': 'jsonSchema'},
  ],
};

/// Descriptor for `ToolSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolSpecDescriptor = $convert.base64Decode('CghUb29sU3BlYxISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAIgASgJUgtkZXNjcmlwdGlvbhIfCgtqc29uX3NjaGVtYRgDIAEoCVIKanNvblNjaGVtYQ==');
@$core.Deprecated('Use timeSeriesConfigDescriptor instead')
const TimeSeriesConfig$json = const {
  '1': 'TimeSeriesConfig',
  '2': const [
    const {'1': 'anomaly_model_id', '3': 1, '4': 1, '5': 9, '10': 'anomalyModelId'},
    const {'1': 'llm_model_id', '3': 2, '4': 1, '5': 9, '10': 'llmModelId'},
    const {'1': 'window_size', '3': 3, '4': 1, '5': 5, '10': 'windowSize'},
    const {'1': 'stride', '3': 4, '4': 1, '5': 5, '10': 'stride'},
    const {'1': 'anomaly_threshold', '3': 5, '4': 1, '5': 2, '10': 'anomalyThreshold'},
    const {'1': 'type_kind', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.SolutionType', '9': 0, '10': 'typeKind', '17': true},
  ],
  '8': const [
    const {'1': '_type_kind'},
  ],
};

/// Descriptor for `TimeSeriesConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timeSeriesConfigDescriptor = $convert.base64Decode('ChBUaW1lU2VyaWVzQ29uZmlnEigKEGFub21hbHlfbW9kZWxfaWQYASABKAlSDmFub21hbHlNb2RlbElkEiAKDGxsbV9tb2RlbF9pZBgCIAEoCVIKbGxtTW9kZWxJZBIfCgt3aW5kb3dfc2l6ZRgDIAEoBVIKd2luZG93U2l6ZRIWCgZzdHJpZGUYBCABKAVSBnN0cmlkZRIrChFhbm9tYWx5X3RocmVzaG9sZBgFIAEoAlIQYW5vbWFseVRocmVzaG9sZBI+Cgl0eXBlX2tpbmQYBiABKA4yHC5ydW5hbnl3aGVyZS52MS5Tb2x1dGlvblR5cGVIAFIIdHlwZUtpbmSIAQFCDAoKX3R5cGVfa2luZA==');
