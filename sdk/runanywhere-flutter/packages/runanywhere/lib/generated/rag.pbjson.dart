///
//  Generated code. Do not modify.
//  source: rag.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use rAGConfigurationDescriptor instead')
const RAGConfiguration$json = const {
  '1': 'RAGConfiguration',
  '2': const [
    const {'1': 'embedding_model_path', '3': 1, '4': 1, '5': 9, '10': 'embeddingModelPath'},
    const {'1': 'llm_model_path', '3': 2, '4': 1, '5': 9, '10': 'llmModelPath'},
    const {'1': 'embedding_dimension', '3': 3, '4': 1, '5': 5, '10': 'embeddingDimension'},
    const {'1': 'top_k', '3': 4, '4': 1, '5': 5, '10': 'topK'},
    const {'1': 'similarity_threshold', '3': 5, '4': 1, '5': 2, '10': 'similarityThreshold'},
    const {'1': 'chunk_size', '3': 6, '4': 1, '5': 5, '10': 'chunkSize'},
    const {'1': 'chunk_overlap', '3': 7, '4': 1, '5': 5, '10': 'chunkOverlap'},
  ],
};

/// Descriptor for `RAGConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGConfigurationDescriptor = $convert.base64Decode('ChBSQUdDb25maWd1cmF0aW9uEjAKFGVtYmVkZGluZ19tb2RlbF9wYXRoGAEgASgJUhJlbWJlZGRpbmdNb2RlbFBhdGgSJAoObGxtX21vZGVsX3BhdGgYAiABKAlSDGxsbU1vZGVsUGF0aBIvChNlbWJlZGRpbmdfZGltZW5zaW9uGAMgASgFUhJlbWJlZGRpbmdEaW1lbnNpb24SEwoFdG9wX2sYBCABKAVSBHRvcEsSMQoUc2ltaWxhcml0eV90aHJlc2hvbGQYBSABKAJSE3NpbWlsYXJpdHlUaHJlc2hvbGQSHQoKY2h1bmtfc2l6ZRgGIAEoBVIJY2h1bmtTaXplEiMKDWNodW5rX292ZXJsYXAYByABKAVSDGNodW5rT3ZlcmxhcA==');
@$core.Deprecated('Use rAGQueryOptionsDescriptor instead')
const RAGQueryOptions$json = const {
  '1': 'RAGQueryOptions',
  '2': const [
    const {'1': 'question', '3': 1, '4': 1, '5': 9, '10': 'question'},
    const {'1': 'system_prompt', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    const {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
    const {'1': 'temperature', '3': 4, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'top_p', '3': 5, '4': 1, '5': 2, '10': 'topP'},
    const {'1': 'top_k', '3': 6, '4': 1, '5': 5, '10': 'topK'},
  ],
  '8': const [
    const {'1': '_system_prompt'},
  ],
};

/// Descriptor for `RAGQueryOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGQueryOptionsDescriptor = $convert.base64Decode('Cg9SQUdRdWVyeU9wdGlvbnMSGgoIcXVlc3Rpb24YASABKAlSCHF1ZXN0aW9uEigKDXN5c3RlbV9wcm9tcHQYAiABKAlIAFIMc3lzdGVtUHJvbXB0iAEBEh0KCm1heF90b2tlbnMYAyABKAVSCW1heFRva2VucxIgCgt0ZW1wZXJhdHVyZRgEIAEoAlILdGVtcGVyYXR1cmUSEwoFdG9wX3AYBSABKAJSBHRvcFASEwoFdG9wX2sYBiABKAVSBHRvcEtCEAoOX3N5c3RlbV9wcm9tcHQ=');
@$core.Deprecated('Use rAGSearchResultDescriptor instead')
const RAGSearchResult$json = const {
  '1': 'RAGSearchResult',
  '2': const [
    const {'1': 'chunk_id', '3': 1, '4': 1, '5': 9, '10': 'chunkId'},
    const {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'similarity_score', '3': 3, '4': 1, '5': 2, '10': 'similarityScore'},
    const {'1': 'source_document', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'sourceDocument', '17': true},
    const {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGSearchResult.MetadataEntry', '10': 'metadata'},
  ],
  '3': const [RAGSearchResult_MetadataEntry$json],
  '8': const [
    const {'1': '_source_document'},
  ],
};

@$core.Deprecated('Use rAGSearchResultDescriptor instead')
const RAGSearchResult_MetadataEntry$json = const {
  '1': 'MetadataEntry',
  '2': const [
    const {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    const {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': const {'7': true},
};

/// Descriptor for `RAGSearchResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGSearchResultDescriptor = $convert.base64Decode('Cg9SQUdTZWFyY2hSZXN1bHQSGQoIY2h1bmtfaWQYASABKAlSB2NodW5rSWQSEgoEdGV4dBgCIAEoCVIEdGV4dBIpChBzaW1pbGFyaXR5X3Njb3JlGAMgASgCUg9zaW1pbGFyaXR5U2NvcmUSLAoPc291cmNlX2RvY3VtZW50GAQgASgJSABSDnNvdXJjZURvY3VtZW50iAEBEkkKCG1ldGFkYXRhGAUgAygLMi0ucnVuYW55d2hlcmUudjEuUkFHU2VhcmNoUmVzdWx0Lk1ldGFkYXRhRW50cnlSCG1ldGFkYXRhGjsKDU1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AUISChBfc291cmNlX2RvY3VtZW50');
@$core.Deprecated('Use rAGResultDescriptor instead')
const RAGResult$json = const {
  '1': 'RAGResult',
  '2': const [
    const {'1': 'answer', '3': 1, '4': 1, '5': 9, '10': 'answer'},
    const {'1': 'retrieved_chunks', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGSearchResult', '10': 'retrievedChunks'},
    const {'1': 'context_used', '3': 3, '4': 1, '5': 9, '10': 'contextUsed'},
    const {'1': 'retrieval_time_ms', '3': 4, '4': 1, '5': 3, '10': 'retrievalTimeMs'},
    const {'1': 'generation_time_ms', '3': 5, '4': 1, '5': 3, '10': 'generationTimeMs'},
    const {'1': 'total_time_ms', '3': 6, '4': 1, '5': 3, '10': 'totalTimeMs'},
  ],
};

/// Descriptor for `RAGResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGResultDescriptor = $convert.base64Decode('CglSQUdSZXN1bHQSFgoGYW5zd2VyGAEgASgJUgZhbnN3ZXISSgoQcmV0cmlldmVkX2NodW5rcxgCIAMoCzIfLnJ1bmFueXdoZXJlLnYxLlJBR1NlYXJjaFJlc3VsdFIPcmV0cmlldmVkQ2h1bmtzEiEKDGNvbnRleHRfdXNlZBgDIAEoCVILY29udGV4dFVzZWQSKgoRcmV0cmlldmFsX3RpbWVfbXMYBCABKANSD3JldHJpZXZhbFRpbWVNcxIsChJnZW5lcmF0aW9uX3RpbWVfbXMYBSABKANSEGdlbmVyYXRpb25UaW1lTXMSIgoNdG90YWxfdGltZV9tcxgGIAEoA1ILdG90YWxUaW1lTXM=');
@$core.Deprecated('Use rAGStatisticsDescriptor instead')
const RAGStatistics$json = const {
  '1': 'RAGStatistics',
  '2': const [
    const {'1': 'indexed_documents', '3': 1, '4': 1, '5': 3, '10': 'indexedDocuments'},
    const {'1': 'indexed_chunks', '3': 2, '4': 1, '5': 3, '10': 'indexedChunks'},
    const {'1': 'total_tokens_indexed', '3': 3, '4': 1, '5': 3, '10': 'totalTokensIndexed'},
    const {'1': 'last_updated_ms', '3': 4, '4': 1, '5': 3, '10': 'lastUpdatedMs'},
    const {'1': 'index_path', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'indexPath', '17': true},
  ],
  '8': const [
    const {'1': '_index_path'},
  ],
};

/// Descriptor for `RAGStatistics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGStatisticsDescriptor = $convert.base64Decode('Cg1SQUdTdGF0aXN0aWNzEisKEWluZGV4ZWRfZG9jdW1lbnRzGAEgASgDUhBpbmRleGVkRG9jdW1lbnRzEiUKDmluZGV4ZWRfY2h1bmtzGAIgASgDUg1pbmRleGVkQ2h1bmtzEjAKFHRvdGFsX3Rva2Vuc19pbmRleGVkGAMgASgDUhJ0b3RhbFRva2Vuc0luZGV4ZWQSJgoPbGFzdF91cGRhdGVkX21zGAQgASgDUg1sYXN0VXBkYXRlZE1zEiIKCmluZGV4X3BhdGgYBSABKAlIAFIJaW5kZXhQYXRoiAEBQg0KC19pbmRleF9wYXRo');
