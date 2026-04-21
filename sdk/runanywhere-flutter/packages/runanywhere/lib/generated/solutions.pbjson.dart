//
//  Generated code. Do not modify.
//  source: solutions.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use audioSourceDescriptor instead')
const AudioSource$json = {
  '1': 'AudioSource',
  '2': [
    {'1': 'AUDIO_SOURCE_UNSPECIFIED', '2': 0},
    {'1': 'AUDIO_SOURCE_MICROPHONE', '2': 1},
    {'1': 'AUDIO_SOURCE_FILE', '2': 2},
    {'1': 'AUDIO_SOURCE_CALLBACK', '2': 3},
  ],
};

/// Descriptor for `AudioSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioSourceDescriptor = $convert.base64Decode(
    'CgtBdWRpb1NvdXJjZRIcChhBVURJT19TT1VSQ0VfVU5TUEVDSUZJRUQQABIbChdBVURJT19TT1'
    'VSQ0VfTUlDUk9QSE9ORRABEhUKEUFVRElPX1NPVVJDRV9GSUxFEAISGQoVQVVESU9fU09VUkNF'
    'X0NBTExCQUNLEAM=');

@$core.Deprecated('Use vectorStoreDescriptor instead')
const VectorStore$json = {
  '1': 'VectorStore',
  '2': [
    {'1': 'VECTOR_STORE_UNSPECIFIED', '2': 0},
    {'1': 'VECTOR_STORE_USEARCH', '2': 1},
    {'1': 'VECTOR_STORE_PGVECTOR', '2': 2},
  ],
};

/// Descriptor for `VectorStore`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vectorStoreDescriptor = $convert.base64Decode(
    'CgtWZWN0b3JTdG9yZRIcChhWRUNUT1JfU1RPUkVfVU5TUEVDSUZJRUQQABIYChRWRUNUT1JfU1'
    'RPUkVfVVNFQVJDSBABEhkKFVZFQ1RPUl9TVE9SRV9QR1ZFQ1RPUhAC');

@$core.Deprecated('Use solutionConfigDescriptor instead')
const SolutionConfig$json = {
  '1': 'SolutionConfig',
  '2': [
    {'1': 'voice_agent', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceAgentConfig', '9': 0, '10': 'voiceAgent'},
    {'1': 'rag', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGConfig', '9': 0, '10': 'rag'},
    {'1': 'wake_word', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.WakeWordConfig', '9': 0, '10': 'wakeWord'},
    {'1': 'agent_loop', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.AgentLoopConfig', '9': 0, '10': 'agentLoop'},
    {'1': 'time_series', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.TimeSeriesConfig', '9': 0, '10': 'timeSeries'},
  ],
  '8': [
    {'1': 'config'},
  ],
};

/// Descriptor for `SolutionConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List solutionConfigDescriptor = $convert.base64Decode(
    'Cg5Tb2x1dGlvbkNvbmZpZxJDCgt2b2ljZV9hZ2VudBgBIAEoCzIgLnJ1bmFueXdoZXJlLnYxLl'
    'ZvaWNlQWdlbnRDb25maWdIAFIKdm9pY2VBZ2VudBItCgNyYWcYAiABKAsyGS5ydW5hbnl3aGVy'
    'ZS52MS5SQUdDb25maWdIAFIDcmFnEj0KCXdha2Vfd29yZBgDIAEoCzIeLnJ1bmFueXdoZXJlLn'
    'YxLldha2VXb3JkQ29uZmlnSABSCHdha2VXb3JkEkAKCmFnZW50X2xvb3AYBCABKAsyHy5ydW5h'
    'bnl3aGVyZS52MS5BZ2VudExvb3BDb25maWdIAFIJYWdlbnRMb29wEkMKC3RpbWVfc2VyaWVzGA'
    'UgASgLMiAucnVuYW55d2hlcmUudjEuVGltZVNlcmllc0NvbmZpZ0gAUgp0aW1lU2VyaWVzQggK'
    'BmNvbmZpZw==');

@$core.Deprecated('Use voiceAgentConfigDescriptor instead')
const VoiceAgentConfig$json = {
  '1': 'VoiceAgentConfig',
  '2': [
    {'1': 'llm_model_id', '3': 1, '4': 1, '5': 9, '10': 'llmModelId'},
    {'1': 'stt_model_id', '3': 2, '4': 1, '5': 9, '10': 'sttModelId'},
    {'1': 'tts_model_id', '3': 3, '4': 1, '5': 9, '10': 'ttsModelId'},
    {'1': 'vad_model_id', '3': 4, '4': 1, '5': 9, '10': 'vadModelId'},
    {'1': 'sample_rate_hz', '3': 5, '4': 1, '5': 5, '10': 'sampleRateHz'},
    {'1': 'chunk_ms', '3': 6, '4': 1, '5': 5, '10': 'chunkMs'},
    {'1': 'audio_source', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioSource', '10': 'audioSource'},
    {'1': 'audio_file_path', '3': 15, '4': 1, '5': 9, '10': 'audioFilePath'},
    {'1': 'enable_barge_in', '3': 8, '4': 1, '5': 8, '10': 'enableBargeIn'},
    {'1': 'barge_in_threshold_ms', '3': 9, '4': 1, '5': 5, '10': 'bargeInThresholdMs'},
    {'1': 'system_prompt', '3': 10, '4': 1, '5': 9, '10': 'systemPrompt'},
    {'1': 'max_context_tokens', '3': 11, '4': 1, '5': 5, '10': 'maxContextTokens'},
    {'1': 'temperature', '3': 12, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'emit_partials', '3': 13, '4': 1, '5': 8, '10': 'emitPartials'},
    {'1': 'emit_thoughts', '3': 14, '4': 1, '5': 8, '10': 'emitThoughts'},
  ],
};

/// Descriptor for `VoiceAgentConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentConfigDescriptor = $convert.base64Decode(
    'ChBWb2ljZUFnZW50Q29uZmlnEiAKDGxsbV9tb2RlbF9pZBgBIAEoCVIKbGxtTW9kZWxJZBIgCg'
    'xzdHRfbW9kZWxfaWQYAiABKAlSCnN0dE1vZGVsSWQSIAoMdHRzX21vZGVsX2lkGAMgASgJUgp0'
    'dHNNb2RlbElkEiAKDHZhZF9tb2RlbF9pZBgEIAEoCVIKdmFkTW9kZWxJZBIkCg5zYW1wbGVfcm'
    'F0ZV9oehgFIAEoBVIMc2FtcGxlUmF0ZUh6EhkKCGNodW5rX21zGAYgASgFUgdjaHVua01zEj4K'
    'DGF1ZGlvX3NvdXJjZRgHIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkF1ZGlvU291cmNlUgthdWRpb1'
    'NvdXJjZRImCg9hdWRpb19maWxlX3BhdGgYDyABKAlSDWF1ZGlvRmlsZVBhdGgSJgoPZW5hYmxl'
    'X2JhcmdlX2luGAggASgIUg1lbmFibGVCYXJnZUluEjEKFWJhcmdlX2luX3RocmVzaG9sZF9tcx'
    'gJIAEoBVISYmFyZ2VJblRocmVzaG9sZE1zEiMKDXN5c3RlbV9wcm9tcHQYCiABKAlSDHN5c3Rl'
    'bVByb21wdBIsChJtYXhfY29udGV4dF90b2tlbnMYCyABKAVSEG1heENvbnRleHRUb2tlbnMSIA'
    'oLdGVtcGVyYXR1cmUYDCABKAJSC3RlbXBlcmF0dXJlEiMKDWVtaXRfcGFydGlhbHMYDSABKAhS'
    'DGVtaXRQYXJ0aWFscxIjCg1lbWl0X3Rob3VnaHRzGA4gASgIUgxlbWl0VGhvdWdodHM=');

@$core.Deprecated('Use rAGConfigDescriptor instead')
const RAGConfig$json = {
  '1': 'RAGConfig',
  '2': [
    {'1': 'embed_model_id', '3': 1, '4': 1, '5': 9, '10': 'embedModelId'},
    {'1': 'rerank_model_id', '3': 2, '4': 1, '5': 9, '10': 'rerankModelId'},
    {'1': 'llm_model_id', '3': 3, '4': 1, '5': 9, '10': 'llmModelId'},
    {'1': 'vector_store', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.VectorStore', '10': 'vectorStore'},
    {'1': 'vector_store_path', '3': 5, '4': 1, '5': 9, '10': 'vectorStorePath'},
    {'1': 'retrieve_k', '3': 6, '4': 1, '5': 5, '10': 'retrieveK'},
    {'1': 'rerank_top', '3': 7, '4': 1, '5': 5, '10': 'rerankTop'},
    {'1': 'bm25_k1', '3': 8, '4': 1, '5': 2, '10': 'bm25K1'},
    {'1': 'bm25_b', '3': 9, '4': 1, '5': 2, '10': 'bm25B'},
    {'1': 'rrf_k', '3': 10, '4': 1, '5': 5, '10': 'rrfK'},
    {'1': 'prompt_template', '3': 11, '4': 1, '5': 9, '10': 'promptTemplate'},
  ],
};

/// Descriptor for `RAGConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGConfigDescriptor = $convert.base64Decode(
    'CglSQUdDb25maWcSJAoOZW1iZWRfbW9kZWxfaWQYASABKAlSDGVtYmVkTW9kZWxJZBImCg9yZX'
    'JhbmtfbW9kZWxfaWQYAiABKAlSDXJlcmFua01vZGVsSWQSIAoMbGxtX21vZGVsX2lkGAMgASgJ'
    'UgpsbG1Nb2RlbElkEj4KDHZlY3Rvcl9zdG9yZRgEIAEoDjIbLnJ1bmFueXdoZXJlLnYxLlZlY3'
    'RvclN0b3JlUgt2ZWN0b3JTdG9yZRIqChF2ZWN0b3Jfc3RvcmVfcGF0aBgFIAEoCVIPdmVjdG9y'
    'U3RvcmVQYXRoEh0KCnJldHJpZXZlX2sYBiABKAVSCXJldHJpZXZlSxIdCgpyZXJhbmtfdG9wGA'
    'cgASgFUglyZXJhbmtUb3ASFwoHYm0yNV9rMRgIIAEoAlIGYm0yNUsxEhUKBmJtMjVfYhgJIAEo'
    'AlIFYm0yNUISEwoFcnJmX2sYCiABKAVSBHJyZksSJwoPcHJvbXB0X3RlbXBsYXRlGAsgASgJUg'
    '5wcm9tcHRUZW1wbGF0ZQ==');

@$core.Deprecated('Use wakeWordConfigDescriptor instead')
const WakeWordConfig$json = {
  '1': 'WakeWordConfig',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'keyword', '3': 2, '4': 1, '5': 9, '10': 'keyword'},
    {'1': 'threshold', '3': 3, '4': 1, '5': 2, '10': 'threshold'},
    {'1': 'pre_roll_ms', '3': 4, '4': 1, '5': 5, '10': 'preRollMs'},
    {'1': 'sample_rate_hz', '3': 5, '4': 1, '5': 5, '10': 'sampleRateHz'},
  ],
};

/// Descriptor for `WakeWordConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wakeWordConfigDescriptor = $convert.base64Decode(
    'Cg5XYWtlV29yZENvbmZpZxIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBIYCgdrZXl3b3JkGA'
    'IgASgJUgdrZXl3b3JkEhwKCXRocmVzaG9sZBgDIAEoAlIJdGhyZXNob2xkEh4KC3ByZV9yb2xs'
    'X21zGAQgASgFUglwcmVSb2xsTXMSJAoOc2FtcGxlX3JhdGVfaHoYBSABKAVSDHNhbXBsZVJhdG'
    'VIeg==');

@$core.Deprecated('Use agentLoopConfigDescriptor instead')
const AgentLoopConfig$json = {
  '1': 'AgentLoopConfig',
  '2': [
    {'1': 'llm_model_id', '3': 1, '4': 1, '5': 9, '10': 'llmModelId'},
    {'1': 'system_prompt', '3': 2, '4': 1, '5': 9, '10': 'systemPrompt'},
    {'1': 'tools', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ToolSpec', '10': 'tools'},
    {'1': 'max_iterations', '3': 4, '4': 1, '5': 5, '10': 'maxIterations'},
    {'1': 'max_context_tokens', '3': 5, '4': 1, '5': 5, '10': 'maxContextTokens'},
  ],
};

/// Descriptor for `AgentLoopConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentLoopConfigDescriptor = $convert.base64Decode(
    'Cg9BZ2VudExvb3BDb25maWcSIAoMbGxtX21vZGVsX2lkGAEgASgJUgpsbG1Nb2RlbElkEiMKDX'
    'N5c3RlbV9wcm9tcHQYAiABKAlSDHN5c3RlbVByb21wdBIuCgV0b29scxgDIAMoCzIYLnJ1bmFu'
    'eXdoZXJlLnYxLlRvb2xTcGVjUgV0b29scxIlCg5tYXhfaXRlcmF0aW9ucxgEIAEoBVINbWF4SX'
    'RlcmF0aW9ucxIsChJtYXhfY29udGV4dF90b2tlbnMYBSABKAVSEG1heENvbnRleHRUb2tlbnM=');

@$core.Deprecated('Use toolSpecDescriptor instead')
const ToolSpec$json = {
  '1': 'ToolSpec',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 2, '4': 1, '5': 9, '10': 'description'},
    {'1': 'json_schema', '3': 3, '4': 1, '5': 9, '10': 'jsonSchema'},
  ],
};

/// Descriptor for `ToolSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolSpecDescriptor = $convert.base64Decode(
    'CghUb29sU3BlYxISCgRuYW1lGAEgASgJUgRuYW1lEiAKC2Rlc2NyaXB0aW9uGAIgASgJUgtkZX'
    'NjcmlwdGlvbhIfCgtqc29uX3NjaGVtYRgDIAEoCVIKanNvblNjaGVtYQ==');

@$core.Deprecated('Use timeSeriesConfigDescriptor instead')
const TimeSeriesConfig$json = {
  '1': 'TimeSeriesConfig',
  '2': [
    {'1': 'anomaly_model_id', '3': 1, '4': 1, '5': 9, '10': 'anomalyModelId'},
    {'1': 'llm_model_id', '3': 2, '4': 1, '5': 9, '10': 'llmModelId'},
    {'1': 'window_size', '3': 3, '4': 1, '5': 5, '10': 'windowSize'},
    {'1': 'stride', '3': 4, '4': 1, '5': 5, '10': 'stride'},
    {'1': 'anomaly_threshold', '3': 5, '4': 1, '5': 2, '10': 'anomalyThreshold'},
  ],
};

/// Descriptor for `TimeSeriesConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List timeSeriesConfigDescriptor = $convert.base64Decode(
    'ChBUaW1lU2VyaWVzQ29uZmlnEigKEGFub21hbHlfbW9kZWxfaWQYASABKAlSDmFub21hbHlNb2'
    'RlbElkEiAKDGxsbV9tb2RlbF9pZBgCIAEoCVIKbGxtTW9kZWxJZBIfCgt3aW5kb3dfc2l6ZRgD'
    'IAEoBVIKd2luZG93U2l6ZRIWCgZzdHJpZGUYBCABKAVSBnN0cmlkZRIrChFhbm9tYWx5X3Rocm'
    'VzaG9sZBgFIAEoAlIQYW5vbWFseVRocmVzaG9sZA==');

