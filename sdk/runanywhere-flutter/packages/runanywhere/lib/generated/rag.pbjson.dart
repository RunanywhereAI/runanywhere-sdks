//
//  Generated code. Do not modify.
//  source: rag.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use rAGConfigurationDescriptor instead')
const RAGConfiguration$json = {
  '1': 'RAGConfiguration',
  '2': [
    {'1': 'embedding_model_path', '3': 1, '4': 1, '5': 9, '10': 'embeddingModelPath'},
    {'1': 'llm_model_path', '3': 2, '4': 1, '5': 9, '10': 'llmModelPath'},
    {'1': 'embedding_dimension', '3': 3, '4': 1, '5': 5, '10': 'embeddingDimension'},
    {'1': 'top_k', '3': 4, '4': 1, '5': 5, '10': 'topK'},
    {'1': 'similarity_threshold', '3': 5, '4': 1, '5': 2, '10': 'similarityThreshold'},
    {'1': 'chunk_size', '3': 6, '4': 1, '5': 5, '10': 'chunkSize'},
    {'1': 'chunk_overlap', '3': 7, '4': 1, '5': 5, '10': 'chunkOverlap'},
    {'1': 'max_context_tokens', '3': 8, '4': 1, '5': 5, '10': 'maxContextTokens'},
    {'1': 'prompt_template', '3': 9, '4': 1, '5': 9, '9': 0, '10': 'promptTemplate', '17': true},
    {'1': 'embedding_config_json', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'embeddingConfigJson', '17': true},
    {'1': 'llm_config_json', '3': 11, '4': 1, '5': 9, '9': 2, '10': 'llmConfigJson', '17': true},
  ],
  '8': [
    {'1': '_prompt_template'},
    {'1': '_embedding_config_json'},
    {'1': '_llm_config_json'},
  ],
};

/// Descriptor for `RAGConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGConfigurationDescriptor = $convert.base64Decode(
    'ChBSQUdDb25maWd1cmF0aW9uEjAKFGVtYmVkZGluZ19tb2RlbF9wYXRoGAEgASgJUhJlbWJlZG'
    'RpbmdNb2RlbFBhdGgSJAoObGxtX21vZGVsX3BhdGgYAiABKAlSDGxsbU1vZGVsUGF0aBIvChNl'
    'bWJlZGRpbmdfZGltZW5zaW9uGAMgASgFUhJlbWJlZGRpbmdEaW1lbnNpb24SEwoFdG9wX2sYBC'
    'ABKAVSBHRvcEsSMQoUc2ltaWxhcml0eV90aHJlc2hvbGQYBSABKAJSE3NpbWlsYXJpdHlUaHJl'
    'c2hvbGQSHQoKY2h1bmtfc2l6ZRgGIAEoBVIJY2h1bmtTaXplEiMKDWNodW5rX292ZXJsYXAYBy'
    'ABKAVSDGNodW5rT3ZlcmxhcBIsChJtYXhfY29udGV4dF90b2tlbnMYCCABKAVSEG1heENvbnRl'
    'eHRUb2tlbnMSLAoPcHJvbXB0X3RlbXBsYXRlGAkgASgJSABSDnByb21wdFRlbXBsYXRliAEBEj'
    'cKFWVtYmVkZGluZ19jb25maWdfanNvbhgKIAEoCUgBUhNlbWJlZGRpbmdDb25maWdKc29uiAEB'
    'EisKD2xsbV9jb25maWdfanNvbhgLIAEoCUgCUg1sbG1Db25maWdKc29uiAEBQhIKEF9wcm9tcH'
    'RfdGVtcGxhdGVCGAoWX2VtYmVkZGluZ19jb25maWdfanNvbkISChBfbGxtX2NvbmZpZ19qc29u');

@$core.Deprecated('Use rAGDocumentDescriptor instead')
const RAGDocument$json = {
  '1': 'RAGDocument',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'metadata_json', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'metadataJson', '17': true},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGDocument.MetadataEntry', '10': 'metadata'},
  ],
  '3': [RAGDocument_MetadataEntry$json],
  '8': [
    {'1': '_metadata_json'},
  ],
};

@$core.Deprecated('Use rAGDocumentDescriptor instead')
const RAGDocument_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `RAGDocument`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGDocumentDescriptor = $convert.base64Decode(
    'CgtSQUdEb2N1bWVudBIOCgJpZBgBIAEoCVICaWQSEgoEdGV4dBgCIAEoCVIEdGV4dBIoCg1tZX'
    'RhZGF0YV9qc29uGAMgASgJSABSDG1ldGFkYXRhSnNvbogBARJFCghtZXRhZGF0YRgEIAMoCzIp'
    'LnJ1bmFueXdoZXJlLnYxLlJBR0RvY3VtZW50Lk1ldGFkYXRhRW50cnlSCG1ldGFkYXRhGjsKDU'
    '1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4'
    'AUIQCg5fbWV0YWRhdGFfanNvbg==');

@$core.Deprecated('Use rAGQueryOptionsDescriptor instead')
const RAGQueryOptions$json = {
  '1': 'RAGQueryOptions',
  '2': [
    {'1': 'question', '3': 1, '4': 1, '5': 9, '10': 'question'},
    {'1': 'system_prompt', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'temperature', '3': 4, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'top_p', '3': 5, '4': 1, '5': 2, '10': 'topP'},
    {'1': 'top_k', '3': 6, '4': 1, '5': 5, '10': 'topK'},
  ],
  '8': [
    {'1': '_system_prompt'},
  ],
};

/// Descriptor for `RAGQueryOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGQueryOptionsDescriptor = $convert.base64Decode(
    'Cg9SQUdRdWVyeU9wdGlvbnMSGgoIcXVlc3Rpb24YASABKAlSCHF1ZXN0aW9uEigKDXN5c3RlbV'
    '9wcm9tcHQYAiABKAlIAFIMc3lzdGVtUHJvbXB0iAEBEh0KCm1heF90b2tlbnMYAyABKAVSCW1h'
    'eFRva2VucxIgCgt0ZW1wZXJhdHVyZRgEIAEoAlILdGVtcGVyYXR1cmUSEwoFdG9wX3AYBSABKA'
    'JSBHRvcFASEwoFdG9wX2sYBiABKAVSBHRvcEtCEAoOX3N5c3RlbV9wcm9tcHQ=');

@$core.Deprecated('Use rAGSearchResultDescriptor instead')
const RAGSearchResult$json = {
  '1': 'RAGSearchResult',
  '2': [
    {'1': 'chunk_id', '3': 1, '4': 1, '5': 9, '10': 'chunkId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'similarity_score', '3': 3, '4': 1, '5': 2, '10': 'similarityScore'},
    {'1': 'source_document', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'sourceDocument', '17': true},
    {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGSearchResult.MetadataEntry', '10': 'metadata'},
    {'1': 'metadata_json', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'metadataJson', '17': true},
  ],
  '3': [RAGSearchResult_MetadataEntry$json],
  '8': [
    {'1': '_source_document'},
    {'1': '_metadata_json'},
  ],
};

@$core.Deprecated('Use rAGSearchResultDescriptor instead')
const RAGSearchResult_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `RAGSearchResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGSearchResultDescriptor = $convert.base64Decode(
    'Cg9SQUdTZWFyY2hSZXN1bHQSGQoIY2h1bmtfaWQYASABKAlSB2NodW5rSWQSEgoEdGV4dBgCIA'
    'EoCVIEdGV4dBIpChBzaW1pbGFyaXR5X3Njb3JlGAMgASgCUg9zaW1pbGFyaXR5U2NvcmUSLAoP'
    'c291cmNlX2RvY3VtZW50GAQgASgJSABSDnNvdXJjZURvY3VtZW50iAEBEkkKCG1ldGFkYXRhGA'
    'UgAygLMi0ucnVuYW55d2hlcmUudjEuUkFHU2VhcmNoUmVzdWx0Lk1ldGFkYXRhRW50cnlSCG1l'
    'dGFkYXRhEigKDW1ldGFkYXRhX2pzb24YBiABKAlIAVIMbWV0YWRhdGFKc29uiAEBGjsKDU1ldG'
    'FkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AUIS'
    'ChBfc291cmNlX2RvY3VtZW50QhAKDl9tZXRhZGF0YV9qc29u');

@$core.Deprecated('Use rAGResultDescriptor instead')
const RAGResult$json = {
  '1': 'RAGResult',
  '2': [
    {'1': 'answer', '3': 1, '4': 1, '5': 9, '10': 'answer'},
    {'1': 'retrieved_chunks', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGSearchResult', '10': 'retrievedChunks'},
    {'1': 'context_used', '3': 3, '4': 1, '5': 9, '10': 'contextUsed'},
    {'1': 'retrieval_time_ms', '3': 4, '4': 1, '5': 3, '10': 'retrievalTimeMs'},
    {'1': 'generation_time_ms', '3': 5, '4': 1, '5': 3, '10': 'generationTimeMs'},
    {'1': 'total_time_ms', '3': 6, '4': 1, '5': 3, '10': 'totalTimeMs'},
  ],
};

/// Descriptor for `RAGResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGResultDescriptor = $convert.base64Decode(
    'CglSQUdSZXN1bHQSFgoGYW5zd2VyGAEgASgJUgZhbnN3ZXISSgoQcmV0cmlldmVkX2NodW5rcx'
    'gCIAMoCzIfLnJ1bmFueXdoZXJlLnYxLlJBR1NlYXJjaFJlc3VsdFIPcmV0cmlldmVkQ2h1bmtz'
    'EiEKDGNvbnRleHRfdXNlZBgDIAEoCVILY29udGV4dFVzZWQSKgoRcmV0cmlldmFsX3RpbWVfbX'
    'MYBCABKANSD3JldHJpZXZhbFRpbWVNcxIsChJnZW5lcmF0aW9uX3RpbWVfbXMYBSABKANSEGdl'
    'bmVyYXRpb25UaW1lTXMSIgoNdG90YWxfdGltZV9tcxgGIAEoA1ILdG90YWxUaW1lTXM=');

@$core.Deprecated('Use rAGStatisticsDescriptor instead')
const RAGStatistics$json = {
  '1': 'RAGStatistics',
  '2': [
    {'1': 'indexed_documents', '3': 1, '4': 1, '5': 3, '10': 'indexedDocuments'},
    {'1': 'indexed_chunks', '3': 2, '4': 1, '5': 3, '10': 'indexedChunks'},
    {'1': 'total_tokens_indexed', '3': 3, '4': 1, '5': 3, '10': 'totalTokensIndexed'},
    {'1': 'last_updated_ms', '3': 4, '4': 1, '5': 3, '10': 'lastUpdatedMs'},
    {'1': 'index_path', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'indexPath', '17': true},
    {'1': 'stats_json', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'statsJson', '17': true},
    {'1': 'vector_store_size_bytes', '3': 7, '4': 1, '5': 3, '10': 'vectorStoreSizeBytes'},
  ],
  '8': [
    {'1': '_index_path'},
    {'1': '_stats_json'},
  ],
};

/// Descriptor for `RAGStatistics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGStatisticsDescriptor = $convert.base64Decode(
    'Cg1SQUdTdGF0aXN0aWNzEisKEWluZGV4ZWRfZG9jdW1lbnRzGAEgASgDUhBpbmRleGVkRG9jdW'
    '1lbnRzEiUKDmluZGV4ZWRfY2h1bmtzGAIgASgDUg1pbmRleGVkQ2h1bmtzEjAKFHRvdGFsX3Rv'
    'a2Vuc19pbmRleGVkGAMgASgDUhJ0b3RhbFRva2Vuc0luZGV4ZWQSJgoPbGFzdF91cGRhdGVkX2'
    '1zGAQgASgDUg1sYXN0VXBkYXRlZE1zEiIKCmluZGV4X3BhdGgYBSABKAlIAFIJaW5kZXhQYXRo'
    'iAEBEiIKCnN0YXRzX2pzb24YBiABKAlIAVIJc3RhdHNKc29uiAEBEjUKF3ZlY3Rvcl9zdG9yZV'
    '9zaXplX2J5dGVzGAcgASgDUhR2ZWN0b3JTdG9yZVNpemVCeXRlc0INCgtfaW5kZXhfcGF0aEIN'
    'Cgtfc3RhdHNfanNvbg==');

