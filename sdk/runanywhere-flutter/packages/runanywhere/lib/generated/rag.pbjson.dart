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

@$core.Deprecated('Use rAGStreamEventKindDescriptor instead')
const RAGStreamEventKind$json = {
  '1': 'RAGStreamEventKind',
  '2': [
    {'1': 'RAG_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED', '2': 1},
    {'1': 'RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED', '2': 2},
    {'1': 'RAG_STREAM_EVENT_KIND_CONTEXT_READY', '2': 3},
    {'1': 'RAG_STREAM_EVENT_KIND_TOKEN', '2': 4},
    {'1': 'RAG_STREAM_EVENT_KIND_COMPLETED', '2': 5},
    {'1': 'RAG_STREAM_EVENT_KIND_ERROR', '2': 6},
  ],
};

/// Descriptor for `RAGStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List rAGStreamEventKindDescriptor = $convert.base64Decode(
    'ChJSQUdTdHJlYW1FdmVudEtpbmQSJQohUkFHX1NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSU'
    'VEEAASKwonUkFHX1NUUkVBTV9FVkVOVF9LSU5EX1JFVFJJRVZBTF9TVEFSVEVEEAESKQolUkFH'
    'X1NUUkVBTV9FVkVOVF9LSU5EX0NIVU5LX1JFVFJJRVZFRBACEicKI1JBR19TVFJFQU1fRVZFTl'
    'RfS0lORF9DT05URVhUX1JFQURZEAMSHwobUkFHX1NUUkVBTV9FVkVOVF9LSU5EX1RPS0VOEAQS'
    'IwofUkFHX1NUUkVBTV9FVkVOVF9LSU5EX0NPTVBMRVRFRBAFEh8KG1JBR19TVFJFQU1fRVZFTl'
    'RfS0lORF9FUlJPUhAG');

@$core.Deprecated('Use rAGConfigurationDescriptor instead')
const RAGConfiguration$json = {
  '1': 'RAGConfiguration',
  '2': [
    {'1': 'embedding_model_id', '3': 1, '4': 1, '5': 9, '10': 'embeddingModelId'},
    {'1': 'llm_model_id', '3': 2, '4': 1, '5': 9, '10': 'llmModelId'},
    {'1': 'embedding_dimension', '3': 3, '4': 1, '5': 5, '8': {}, '10': 'embeddingDimension'},
    {'1': 'top_k', '3': 4, '4': 1, '5': 5, '8': {}, '10': 'topK'},
    {'1': 'similarity_threshold', '3': 5, '4': 1, '5': 2, '8': {}, '10': 'similarityThreshold'},
    {'1': 'chunk_size', '3': 6, '4': 1, '5': 5, '8': {}, '10': 'chunkSize'},
    {'1': 'chunk_overlap', '3': 7, '4': 1, '5': 5, '8': {}, '10': 'chunkOverlap'},
    {'1': 'max_context_tokens', '3': 8, '4': 1, '5': 5, '10': 'maxContextTokens'},
    {'1': 'prompt_template', '3': 9, '4': 1, '5': 9, '9': 0, '10': 'promptTemplate', '17': true},
    {'1': 'embedding_config_json', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'embeddingConfigJson', '17': true},
    {'1': 'llm_config_json', '3': 11, '4': 1, '5': 9, '9': 2, '10': 'llmConfigJson', '17': true},
    {'1': 'index_path', '3': 12, '4': 1, '5': 9, '9': 3, '10': 'indexPath', '17': true},
    {'1': 'persist_index', '3': 13, '4': 1, '5': 8, '10': 'persistIndex'},
    {'1': 'rerank_results', '3': 14, '4': 1, '5': 8, '10': 'rerankResults'},
    {'1': 'reranker_model_id', '3': 15, '4': 1, '5': 9, '9': 4, '10': 'rerankerModelId', '17': true},
  ],
  '8': [
    {'1': '_prompt_template'},
    {'1': '_embedding_config_json'},
    {'1': '_llm_config_json'},
    {'1': '_index_path'},
    {'1': '_reranker_model_id'},
  ],
};

/// Descriptor for `RAGConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGConfigurationDescriptor = $convert.base64Decode(
    'ChBSQUdDb25maWd1cmF0aW9uEiwKEmVtYmVkZGluZ19tb2RlbF9pZBgBIAEoCVIQZW1iZWRkaW'
    '5nTW9kZWxJZBIgCgxsbG1fbW9kZWxfaWQYAiABKAlSCmxsbU1vZGVsSWQSOAoTZW1iZWRkaW5n'
    'X2RpbWVuc2lvbhgDIAEoBUIHirUYAzM4NFISZW1iZWRkaW5nRGltZW5zaW9uEhoKBXRvcF9rGA'
    'QgASgFQgWKtRgBNVIEdG9wSxJQChRzaW1pbGFyaXR5X3RocmVzaG9sZBgFIAEoAkIdirUYAzAu'
    'N7G1GAAAAAAAAAAAubUYAAAAAAAA8D9SE3NpbWlsYXJpdHlUaHJlc2hvbGQSJgoKY2h1bmtfc2'
    'l6ZRgGIAEoBUIHirUYAzUxMlIJY2h1bmtTaXplEisKDWNodW5rX292ZXJsYXAYByABKAVCBoq1'
    'GAI2NFIMY2h1bmtPdmVybGFwEiwKEm1heF9jb250ZXh0X3Rva2VucxgIIAEoBVIQbWF4Q29udG'
    'V4dFRva2VucxIsCg9wcm9tcHRfdGVtcGxhdGUYCSABKAlIAFIOcHJvbXB0VGVtcGxhdGWIAQES'
    'NwoVZW1iZWRkaW5nX2NvbmZpZ19qc29uGAogASgJSAFSE2VtYmVkZGluZ0NvbmZpZ0pzb26IAQ'
    'ESKwoPbGxtX2NvbmZpZ19qc29uGAsgASgJSAJSDWxsbUNvbmZpZ0pzb26IAQESIgoKaW5kZXhf'
    'cGF0aBgMIAEoCUgDUglpbmRleFBhdGiIAQESIwoNcGVyc2lzdF9pbmRleBgNIAEoCFIMcGVyc2'
    'lzdEluZGV4EiUKDnJlcmFua19yZXN1bHRzGA4gASgIUg1yZXJhbmtSZXN1bHRzEi8KEXJlcmFu'
    'a2VyX21vZGVsX2lkGA8gASgJSARSD3JlcmFua2VyTW9kZWxJZIgBAUISChBfcHJvbXB0X3RlbX'
    'BsYXRlQhgKFl9lbWJlZGRpbmdfY29uZmlnX2pzb25CEgoQX2xsbV9jb25maWdfanNvbkINCgtf'
    'aW5kZXhfcGF0aEIUChJfcmVyYW5rZXJfbW9kZWxfaWQ=');

@$core.Deprecated('Use rAGDocumentDescriptor instead')
const RAGDocument$json = {
  '1': 'RAGDocument',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGDocument.MetadataEntry', '10': 'metadata'},
    {'1': 'source_uri', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'sourceUri', '17': true},
    {'1': 'adapter_handle', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'adapterHandle', '17': true},
    {'1': 'media_type', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'mediaType', '17': true},
    {'1': 'size_bytes', '3': 8, '4': 1, '5': 3, '10': 'sizeBytes'},
  ],
  '3': [RAGDocument_MetadataEntry$json],
  '8': [
    {'1': '_source_uri'},
    {'1': '_adapter_handle'},
    {'1': '_media_type'},
  ],
  '9': [
    {'1': 3, '2': 4},
  ],
  '10': ['metadata_json'],
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
    'CgtSQUdEb2N1bWVudBIOCgJpZBgBIAEoCVICaWQSEgoEdGV4dBgCIAEoCVIEdGV4dBJFCghtZX'
    'RhZGF0YRgEIAMoCzIpLnJ1bmFueXdoZXJlLnYxLlJBR0RvY3VtZW50Lk1ldGFkYXRhRW50cnlS'
    'CG1ldGFkYXRhEiIKCnNvdXJjZV91cmkYBSABKAlIAFIJc291cmNlVXJpiAEBEioKDmFkYXB0ZX'
    'JfaGFuZGxlGAYgASgJSAFSDWFkYXB0ZXJIYW5kbGWIAQESIgoKbWVkaWFfdHlwZRgHIAEoCUgC'
    'UgltZWRpYVR5cGWIAQESHQoKc2l6ZV9ieXRlcxgIIAEoA1IJc2l6ZUJ5dGVzGjsKDU1ldGFkYX'
    'RhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AUINCgtf'
    'c291cmNlX3VyaUIRCg9fYWRhcHRlcl9oYW5kbGVCDQoLX21lZGlhX3R5cGVKBAgDEARSDW1ldG'
    'FkYXRhX2pzb24=');

@$core.Deprecated('Use rAGIngestRequestDescriptor instead')
const RAGIngestRequest$json = {
  '1': 'RAGIngestRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'documents', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGDocument', '10': 'documents'},
    {'1': 'replace_existing', '3': 3, '4': 1, '5': 8, '10': 'replaceExisting'},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGIngestRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [RAGIngestRequest_MetadataEntry$json],
};

@$core.Deprecated('Use rAGIngestRequestDescriptor instead')
const RAGIngestRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `RAGIngestRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGIngestRequestDescriptor = $convert.base64Decode(
    'ChBSQUdJbmdlc3RSZXF1ZXN0Eh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcXVlc3RJZBI5Cglkb2'
    'N1bWVudHMYAiADKAsyGy5ydW5hbnl3aGVyZS52MS5SQUdEb2N1bWVudFIJZG9jdW1lbnRzEikK'
    'EHJlcGxhY2VfZXhpc3RpbmcYAyABKAhSD3JlcGxhY2VFeGlzdGluZxJKCghtZXRhZGF0YRgEIA'
    'MoCzIuLnJ1bmFueXdoZXJlLnYxLlJBR0luZ2VzdFJlcXVlc3QuTWV0YWRhdGFFbnRyeVIIbWV0'
    'YWRhdGEaOwoNTWV0YWRhdGFFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCV'
    'IFdmFsdWU6AjgB');

@$core.Deprecated('Use rAGQueryOptionsDescriptor instead')
const RAGQueryOptions$json = {
  '1': 'RAGQueryOptions',
  '2': [
    {'1': 'question', '3': 1, '4': 1, '5': 9, '10': 'question'},
    {'1': 'system_prompt', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '8': {}, '10': 'maxTokens'},
    {'1': 'temperature', '3': 4, '4': 1, '5': 2, '8': {}, '10': 'temperature'},
    {'1': 'top_p', '3': 5, '4': 1, '5': 2, '8': {}, '10': 'topP'},
    {'1': 'top_k', '3': 6, '4': 1, '5': 5, '10': 'topK'},
    {'1': 'retrieval_top_k', '3': 7, '4': 1, '5': 5, '10': 'retrievalTopK'},
    {'1': 'similarity_threshold', '3': 8, '4': 1, '5': 2, '10': 'similarityThreshold'},
    {'1': 'stream', '3': 9, '4': 1, '5': 8, '10': 'stream'},
  ],
  '8': [
    {'1': '_system_prompt'},
  ],
};

/// Descriptor for `RAGQueryOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGQueryOptionsDescriptor = $convert.base64Decode(
    'Cg9SQUdRdWVyeU9wdGlvbnMSGgoIcXVlc3Rpb24YASABKAlSCHF1ZXN0aW9uEigKDXN5c3RlbV'
    '9wcm9tcHQYAiABKAlIAFIMc3lzdGVtUHJvbXB0iAEBEiYKCm1heF90b2tlbnMYAyABKAVCB4q1'
    'GAM1MTJSCW1heFRva2VucxIpCgt0ZW1wZXJhdHVyZRgEIAEoAkIHirUYAzAuN1ILdGVtcGVyYX'
    'R1cmUSHAoFdG9wX3AYBSABKAJCB4q1GAMxLjBSBHRvcFASEwoFdG9wX2sYBiABKAVSBHRvcEsS'
    'JgoPcmV0cmlldmFsX3RvcF9rGAcgASgFUg1yZXRyaWV2YWxUb3BLEjEKFHNpbWlsYXJpdHlfdG'
    'hyZXNob2xkGAggASgCUhNzaW1pbGFyaXR5VGhyZXNob2xkEhYKBnN0cmVhbRgJIAEoCFIGc3Ry'
    'ZWFtQhAKDl9zeXN0ZW1fcHJvbXB0');

@$core.Deprecated('Use rAGQueryRequestDescriptor instead')
const RAGQueryRequest$json = {
  '1': 'RAGQueryRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGQueryOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'metadata', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGQueryRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [RAGQueryRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
  ],
};

@$core.Deprecated('Use rAGQueryRequestDescriptor instead')
const RAGQueryRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `RAGQueryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGQueryRequestDescriptor = $convert.base64Decode(
    'Cg9SQUdRdWVyeVJlcXVlc3QSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEj4KB29wdG'
    'lvbnMYAiABKAsyHy5ydW5hbnl3aGVyZS52MS5SQUdRdWVyeU9wdGlvbnNIAFIHb3B0aW9uc4gB'
    'ARJJCghtZXRhZGF0YRgDIAMoCzItLnJ1bmFueXdoZXJlLnYxLlJBR1F1ZXJ5UmVxdWVzdC5NZX'
    'RhZGF0YUVudHJ5UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5'
    'EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAFCCgoIX29wdGlvbnM=');

@$core.Deprecated('Use rAGSearchResultDescriptor instead')
const RAGSearchResult$json = {
  '1': 'RAGSearchResult',
  '2': [
    {'1': 'chunk_id', '3': 1, '4': 1, '5': 9, '10': 'chunkId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'similarity_score', '3': 3, '4': 1, '5': 2, '10': 'similarityScore'},
    {'1': 'source_document', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'sourceDocument', '17': true},
    {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.RAGSearchResult.MetadataEntry', '10': 'metadata'},
    {'1': 'rank', '3': 7, '4': 1, '5': 5, '10': 'rank'},
    {'1': 'start_offset', '3': 8, '4': 1, '5': 5, '10': 'startOffset'},
    {'1': 'end_offset', '3': 9, '4': 1, '5': 5, '10': 'endOffset'},
    {'1': 'token_count', '3': 10, '4': 1, '5': 5, '10': 'tokenCount'},
  ],
  '3': [RAGSearchResult_MetadataEntry$json],
  '8': [
    {'1': '_source_document'},
  ],
  '9': [
    {'1': 6, '2': 7},
  ],
  '10': ['metadata_json'],
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
    'dGFkYXRhEhIKBHJhbmsYByABKAVSBHJhbmsSIQoMc3RhcnRfb2Zmc2V0GAggASgFUgtzdGFydE'
    '9mZnNldBIdCgplbmRfb2Zmc2V0GAkgASgFUgllbmRPZmZzZXQSHwoLdG9rZW5fY291bnQYCiAB'
    'KAVSCnRva2VuQ291bnQaOwoNTWV0YWRhdGFFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YW'
    'x1ZRgCIAEoCVIFdmFsdWU6AjgBQhIKEF9zb3VyY2VfZG9jdW1lbnRKBAgGEAdSDW1ldGFkYXRh'
    'X2pzb24=');

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
    {'1': 'prompt_tokens', '3': 7, '4': 1, '5': 5, '10': 'promptTokens'},
    {'1': 'completion_tokens', '3': 8, '4': 1, '5': 5, '10': 'completionTokens'},
    {'1': 'total_tokens', '3': 9, '4': 1, '5': 5, '10': 'totalTokens'},
    {'1': 'error_message', '3': 10, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 11, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'request_id', '3': 12, '4': 1, '5': 9, '10': 'requestId'},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `RAGResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGResultDescriptor = $convert.base64Decode(
    'CglSQUdSZXN1bHQSFgoGYW5zd2VyGAEgASgJUgZhbnN3ZXISSgoQcmV0cmlldmVkX2NodW5rcx'
    'gCIAMoCzIfLnJ1bmFueXdoZXJlLnYxLlJBR1NlYXJjaFJlc3VsdFIPcmV0cmlldmVkQ2h1bmtz'
    'EiEKDGNvbnRleHRfdXNlZBgDIAEoCVILY29udGV4dFVzZWQSKgoRcmV0cmlldmFsX3RpbWVfbX'
    'MYBCABKANSD3JldHJpZXZhbFRpbWVNcxIsChJnZW5lcmF0aW9uX3RpbWVfbXMYBSABKANSEGdl'
    'bmVyYXRpb25UaW1lTXMSIgoNdG90YWxfdGltZV9tcxgGIAEoA1ILdG90YWxUaW1lTXMSIwoNcH'
    'JvbXB0X3Rva2VucxgHIAEoBVIMcHJvbXB0VG9rZW5zEisKEWNvbXBsZXRpb25fdG9rZW5zGAgg'
    'ASgFUhBjb21wbGV0aW9uVG9rZW5zEiEKDHRvdGFsX3Rva2VucxgJIAEoBVILdG90YWxUb2tlbn'
    'MSKAoNZXJyb3JfbWVzc2FnZRgKIAEoCUgAUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3JfY29k'
    'ZRgLIAEoBVIJZXJyb3JDb2RlEh0KCnJlcXVlc3RfaWQYDCABKAlSCXJlcXVlc3RJZEIQCg5fZX'
    'Jyb3JfbWVzc2FnZQ==');

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
    {'1': 'is_persistent', '3': 8, '4': 1, '5': 8, '10': 'isPersistent'},
    {'1': 'last_query_ms', '3': 9, '4': 1, '5': 3, '10': 'lastQueryMs'},
    {'1': 'error_message', '3': 10, '4': 1, '5': 9, '9': 2, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 11, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_index_path'},
    {'1': '_stats_json'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `RAGStatistics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGStatisticsDescriptor = $convert.base64Decode(
    'Cg1SQUdTdGF0aXN0aWNzEisKEWluZGV4ZWRfZG9jdW1lbnRzGAEgASgDUhBpbmRleGVkRG9jdW'
    '1lbnRzEiUKDmluZGV4ZWRfY2h1bmtzGAIgASgDUg1pbmRleGVkQ2h1bmtzEjAKFHRvdGFsX3Rv'
    'a2Vuc19pbmRleGVkGAMgASgDUhJ0b3RhbFRva2Vuc0luZGV4ZWQSJgoPbGFzdF91cGRhdGVkX2'
    '1zGAQgASgDUg1sYXN0VXBkYXRlZE1zEiIKCmluZGV4X3BhdGgYBSABKAlIAFIJaW5kZXhQYXRo'
    'iAEBEiIKCnN0YXRzX2pzb24YBiABKAlIAVIJc3RhdHNKc29uiAEBEjUKF3ZlY3Rvcl9zdG9yZV'
    '9zaXplX2J5dGVzGAcgASgDUhR2ZWN0b3JTdG9yZVNpemVCeXRlcxIjCg1pc19wZXJzaXN0ZW50'
    'GAggASgIUgxpc1BlcnNpc3RlbnQSIgoNbGFzdF9xdWVyeV9tcxgJIAEoA1ILbGFzdFF1ZXJ5TX'
    'MSKAoNZXJyb3JfbWVzc2FnZRgKIAEoCUgCUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3JfY29k'
    'ZRgLIAEoBVIJZXJyb3JDb2RlQg0KC19pbmRleF9wYXRoQg0KC19zdGF0c19qc29uQhAKDl9lcn'
    'Jvcl9tZXNzYWdl');

@$core.Deprecated('Use rAGIngestResultDescriptor instead')
const RAGIngestResult$json = {
  '1': 'RAGIngestResult',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'documents_ingested', '3': 2, '4': 1, '5': 3, '10': 'documentsIngested'},
    {'1': 'chunks_ingested', '3': 3, '4': 1, '5': 3, '10': 'chunksIngested'},
    {'1': 'statistics', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGStatistics', '9': 0, '10': 'statistics', '17': true},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 6, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_statistics'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `RAGIngestResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGIngestResultDescriptor = $convert.base64Decode(
    'Cg9SQUdJbmdlc3RSZXN1bHQSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEi0KEmRvY3'
    'VtZW50c19pbmdlc3RlZBgCIAEoA1IRZG9jdW1lbnRzSW5nZXN0ZWQSJwoPY2h1bmtzX2luZ2Vz'
    'dGVkGAMgASgDUg5jaHVua3NJbmdlc3RlZBJCCgpzdGF0aXN0aWNzGAQgASgLMh0ucnVuYW55d2'
    'hlcmUudjEuUkFHU3RhdGlzdGljc0gAUgpzdGF0aXN0aWNziAEBEigKDWVycm9yX21lc3NhZ2UY'
    'BSABKAlIAVIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYBiABKAVSCWVycm9yQ29kZU'
    'INCgtfc3RhdGlzdGljc0IQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use rAGStreamEventDescriptor instead')
const RAGStreamEvent$json = {
  '1': 'RAGStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.RAGStreamEventKind', '10': 'kind'},
    {'1': 'chunk', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGSearchResult', '9': 0, '10': 'chunk', '17': true},
    {'1': 'token', '3': 6, '4': 1, '5': 9, '10': 'token'},
    {'1': 'result', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGResult', '9': 1, '10': 'result', '17': true},
    {'1': 'error_message', '3': 8, '4': 1, '5': 9, '9': 2, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 9, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_chunk'},
    {'1': '_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `RAGStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGStreamEventDescriptor = $convert.base64Decode(
    'Cg5SQUdTdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKA'
    'NSC3RpbWVzdGFtcFVzEh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJZBI2CgRraW5kGAQg'
    'ASgOMiIucnVuYW55d2hlcmUudjEuUkFHU3RyZWFtRXZlbnRLaW5kUgRraW5kEjoKBWNodW5rGA'
    'UgASgLMh8ucnVuYW55d2hlcmUudjEuUkFHU2VhcmNoUmVzdWx0SABSBWNodW5riAEBEhQKBXRv'
    'a2VuGAYgASgJUgV0b2tlbhI2CgZyZXN1bHQYByABKAsyGS5ydW5hbnl3aGVyZS52MS5SQUdSZX'
    'N1bHRIAVIGcmVzdWx0iAEBEigKDWVycm9yX21lc3NhZ2UYCCABKAlIAlIMZXJyb3JNZXNzYWdl'
    'iAEBEh0KCmVycm9yX2NvZGUYCSABKAVSCWVycm9yQ29kZUIICgZfY2h1bmtCCQoHX3Jlc3VsdE'
    'IQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use rAGServiceStateDescriptor instead')
const RAGServiceState$json = {
  '1': 'RAGServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'statistics', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.RAGStatistics', '9': 0, '10': 'statistics', '17': true},
    {'1': 'is_indexing', '3': 3, '4': 1, '5': 8, '10': 'isIndexing'},
    {'1': 'is_querying', '3': 4, '4': 1, '5': 8, '10': 'isQuerying'},
    {'1': 'active_request_id', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'activeRequestId', '17': true},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '9': 2, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 7, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_statistics'},
    {'1': '_active_request_id'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `RAGServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rAGServiceStateDescriptor = $convert.base64Decode(
    'Cg9SQUdTZXJ2aWNlU3RhdGUSGQoIaXNfcmVhZHkYASABKAhSB2lzUmVhZHkSQgoKc3RhdGlzdG'
    'ljcxgCIAEoCzIdLnJ1bmFueXdoZXJlLnYxLlJBR1N0YXRpc3RpY3NIAFIKc3RhdGlzdGljc4gB'
    'ARIfCgtpc19pbmRleGluZxgDIAEoCFIKaXNJbmRleGluZxIfCgtpc19xdWVyeWluZxgEIAEoCF'
    'IKaXNRdWVyeWluZxIvChFhY3RpdmVfcmVxdWVzdF9pZBgFIAEoCUgBUg9hY3RpdmVSZXF1ZXN0'
    'SWSIAQESKAoNZXJyb3JfbWVzc2FnZRgGIAEoCUgCUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3'
    'JfY29kZRgHIAEoBVIJZXJyb3JDb2RlQg0KC19zdGF0aXN0aWNzQhQKEl9hY3RpdmVfcmVxdWVz'
    'dF9pZEIQCg5fZXJyb3JfbWVzc2FnZQ==');

const $core.Map<$core.String, $core.dynamic> RAGServiceBase$json = {
  '1': 'RAG',
  '2': [
    {'1': 'Create', '2': '.runanywhere.v1.RAGConfiguration', '3': '.runanywhere.v1.RAGServiceState'},
    {'1': 'Ingest', '2': '.runanywhere.v1.RAGIngestRequest', '3': '.runanywhere.v1.RAGIngestResult'},
    {'1': 'Query', '2': '.runanywhere.v1.RAGQueryRequest', '3': '.runanywhere.v1.RAGResult'},
    {'1': 'Search', '2': '.runanywhere.v1.RAGQueryRequest', '3': '.runanywhere.v1.RAGResult'},
    {'1': 'Stats', '2': '.runanywhere.v1.RAGServiceState', '3': '.runanywhere.v1.RAGStatistics'},
    {'1': 'Clear', '2': '.runanywhere.v1.RAGServiceState', '3': '.runanywhere.v1.RAGServiceState'},
    {'1': 'Stream', '2': '.runanywhere.v1.RAGQueryRequest', '3': '.runanywhere.v1.RAGStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use rAGServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> RAGServiceBase$messageJson = {
  '.runanywhere.v1.RAGConfiguration': RAGConfiguration$json,
  '.runanywhere.v1.RAGServiceState': RAGServiceState$json,
  '.runanywhere.v1.RAGStatistics': RAGStatistics$json,
  '.runanywhere.v1.RAGIngestRequest': RAGIngestRequest$json,
  '.runanywhere.v1.RAGDocument': RAGDocument$json,
  '.runanywhere.v1.RAGDocument.MetadataEntry': RAGDocument_MetadataEntry$json,
  '.runanywhere.v1.RAGIngestRequest.MetadataEntry': RAGIngestRequest_MetadataEntry$json,
  '.runanywhere.v1.RAGIngestResult': RAGIngestResult$json,
  '.runanywhere.v1.RAGQueryRequest': RAGQueryRequest$json,
  '.runanywhere.v1.RAGQueryOptions': RAGQueryOptions$json,
  '.runanywhere.v1.RAGQueryRequest.MetadataEntry': RAGQueryRequest_MetadataEntry$json,
  '.runanywhere.v1.RAGResult': RAGResult$json,
  '.runanywhere.v1.RAGSearchResult': RAGSearchResult$json,
  '.runanywhere.v1.RAGSearchResult.MetadataEntry': RAGSearchResult_MetadataEntry$json,
  '.runanywhere.v1.RAGStreamEvent': RAGStreamEvent$json,
};

/// Descriptor for `RAG`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List rAGServiceDescriptor = $convert.base64Decode(
    'CgNSQUcSSwoGQ3JlYXRlEiAucnVuYW55d2hlcmUudjEuUkFHQ29uZmlndXJhdGlvbhofLnJ1bm'
    'FueXdoZXJlLnYxLlJBR1NlcnZpY2VTdGF0ZRJLCgZJbmdlc3QSIC5ydW5hbnl3aGVyZS52MS5S'
    'QUdJbmdlc3RSZXF1ZXN0Gh8ucnVuYW55d2hlcmUudjEuUkFHSW5nZXN0UmVzdWx0EkMKBVF1ZX'
    'J5Eh8ucnVuYW55d2hlcmUudjEuUkFHUXVlcnlSZXF1ZXN0GhkucnVuYW55d2hlcmUudjEuUkFH'
    'UmVzdWx0EkQKBlNlYXJjaBIfLnJ1bmFueXdoZXJlLnYxLlJBR1F1ZXJ5UmVxdWVzdBoZLnJ1bm'
    'FueXdoZXJlLnYxLlJBR1Jlc3VsdBJHCgVTdGF0cxIfLnJ1bmFueXdoZXJlLnYxLlJBR1NlcnZp'
    'Y2VTdGF0ZRodLnJ1bmFueXdoZXJlLnYxLlJBR1N0YXRpc3RpY3MSSQoFQ2xlYXISHy5ydW5hbn'
    'l3aGVyZS52MS5SQUdTZXJ2aWNlU3RhdGUaHy5ydW5hbnl3aGVyZS52MS5SQUdTZXJ2aWNlU3Rh'
    'dGUSSwoGU3RyZWFtEh8ucnVuYW55d2hlcmUudjEuUkFHUXVlcnlSZXF1ZXN0Gh4ucnVuYW55d2'
    'hlcmUudjEuUkFHU3RyZWFtRXZlbnQwAQ==');

