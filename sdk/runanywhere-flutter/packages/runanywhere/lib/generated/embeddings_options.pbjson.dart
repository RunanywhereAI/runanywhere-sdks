//
//  Generated code. Do not modify.
//  source: embeddings_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use embeddingsNormalizeModeDescriptor instead')
const EmbeddingsNormalizeMode$json = {
  '1': 'EmbeddingsNormalizeMode',
  '2': [
    {'1': 'EMBEDDINGS_NORMALIZE_MODE_UNSPECIFIED', '2': 0},
    {'1': 'EMBEDDINGS_NORMALIZE_MODE_NONE', '2': 1},
    {'1': 'EMBEDDINGS_NORMALIZE_MODE_L2', '2': 2},
  ],
};

/// Descriptor for `EmbeddingsNormalizeMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List embeddingsNormalizeModeDescriptor = $convert.base64Decode(
    'ChdFbWJlZGRpbmdzTm9ybWFsaXplTW9kZRIpCiVFTUJFRERJTkdTX05PUk1BTElaRV9NT0RFX1'
    'VOU1BFQ0lGSUVEEAASIgoeRU1CRURESU5HU19OT1JNQUxJWkVfTU9ERV9OT05FEAESIAocRU1C'
    'RURESU5HU19OT1JNQUxJWkVfTU9ERV9MMhAC');

@$core.Deprecated('Use embeddingsPoolingStrategyDescriptor instead')
const EmbeddingsPoolingStrategy$json = {
  '1': 'EmbeddingsPoolingStrategy',
  '2': [
    {'1': 'EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED', '2': 0},
    {'1': 'EMBEDDINGS_POOLING_STRATEGY_MEAN', '2': 1},
    {'1': 'EMBEDDINGS_POOLING_STRATEGY_CLS', '2': 2},
    {'1': 'EMBEDDINGS_POOLING_STRATEGY_LAST', '2': 3},
  ],
};

/// Descriptor for `EmbeddingsPoolingStrategy`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List embeddingsPoolingStrategyDescriptor = $convert.base64Decode(
    'ChlFbWJlZGRpbmdzUG9vbGluZ1N0cmF0ZWd5EisKJ0VNQkVERElOR1NfUE9PTElOR19TVFJBVE'
    'VHWV9VTlNQRUNJRklFRBAAEiQKIEVNQkVERElOR1NfUE9PTElOR19TVFJBVEVHWV9NRUFOEAES'
    'IwofRU1CRURESU5HU19QT09MSU5HX1NUUkFURUdZX0NMUxACEiQKIEVNQkVERElOR1NfUE9PTE'
    'lOR19TVFJBVEVHWV9MQVNUEAM=');

@$core.Deprecated('Use embeddingsConfigurationDescriptor instead')
const EmbeddingsConfiguration$json = {
  '1': 'EmbeddingsConfiguration',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '8': {}, '10': 'modelId'},
    {'1': 'embedding_dimension', '3': 2, '4': 1, '5': 5, '8': {}, '10': 'embeddingDimension'},
    {'1': 'max_sequence_length', '3': 3, '4': 1, '5': 5, '8': {}, '10': 'maxSequenceLength'},
    {'1': 'normalize', '3': 4, '4': 1, '5': 8, '8': {}, '9': 0, '10': 'normalize', '17': true},
    {'1': 'preferred_framework', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'preferredFramework', '17': true},
    {'1': 'max_tokens', '3': 6, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'normalize_mode', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.EmbeddingsNormalizeMode', '10': 'normalizeMode'},
    {'1': 'pooling', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.EmbeddingsPoolingStrategy', '10': 'pooling'},
    {'1': 'config_json', '3': 9, '4': 1, '5': 9, '9': 2, '10': 'configJson', '17': true},
  ],
  '8': [
    {'1': '_normalize'},
    {'1': '_preferred_framework'},
    {'1': '_config_json'},
  ],
};

/// Descriptor for `EmbeddingsConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsConfigurationDescriptor = $convert.base64Decode(
    'ChdFbWJlZGRpbmdzQ29uZmlndXJhdGlvbhIfCghtb2RlbF9pZBgBIAEoCUIEkLUYAVIHbW9kZW'
    'xJZBI8ChNlbWJlZGRpbmdfZGltZW5zaW9uGAIgASgFQguKtRgDMzg0oLUYAVISZW1iZWRkaW5n'
    'RGltZW5zaW9uEjsKE21heF9zZXF1ZW5jZV9sZW5ndGgYAyABKAVCC4q1GAM1MTKgtRgBUhFtYX'
    'hTZXF1ZW5jZUxlbmd0aBIrCglub3JtYWxpemUYBCABKAhCCIq1GAR0cnVlSABSCW5vcm1hbGl6'
    'ZYgBARJYChNwcmVmZXJyZWRfZnJhbWV3b3JrGAUgASgOMiIucnVuYW55d2hlcmUudjEuSW5mZX'
    'JlbmNlRnJhbWV3b3JrSAFSEnByZWZlcnJlZEZyYW1ld29ya4gBARIdCgptYXhfdG9rZW5zGAYg'
    'ASgFUgltYXhUb2tlbnMSTgoObm9ybWFsaXplX21vZGUYByABKA4yJy5ydW5hbnl3aGVyZS52MS'
    '5FbWJlZGRpbmdzTm9ybWFsaXplTW9kZVINbm9ybWFsaXplTW9kZRJDCgdwb29saW5nGAggASgO'
    'MikucnVuYW55d2hlcmUudjEuRW1iZWRkaW5nc1Bvb2xpbmdTdHJhdGVneVIHcG9vbGluZxIkCg'
    'tjb25maWdfanNvbhgJIAEoCUgCUgpjb25maWdKc29uiAEBQgwKCl9ub3JtYWxpemVCFgoUX3By'
    'ZWZlcnJlZF9mcmFtZXdvcmtCDgoMX2NvbmZpZ19qc29u');

@$core.Deprecated('Use embeddingsOptionsDescriptor instead')
const EmbeddingsOptions$json = {
  '1': 'EmbeddingsOptions',
  '2': [
    {'1': 'normalize', '3': 1, '4': 1, '5': 8, '8': {}, '10': 'normalize'},
    {'1': 'truncate', '3': 2, '4': 1, '5': 8, '9': 0, '10': 'truncate', '17': true},
    {'1': 'batch_size', '3': 3, '4': 1, '5': 5, '9': 1, '10': 'batchSize', '17': true},
    {'1': 'normalize_mode', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.EmbeddingsNormalizeMode', '10': 'normalizeMode'},
    {'1': 'pooling', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.EmbeddingsPoolingStrategy', '10': 'pooling'},
    {'1': 'n_threads', '3': 6, '4': 1, '5': 5, '10': 'nThreads'},
  ],
  '8': [
    {'1': '_truncate'},
    {'1': '_batch_size'},
  ],
};

/// Descriptor for `EmbeddingsOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsOptionsDescriptor = $convert.base64Decode(
    'ChFFbWJlZGRpbmdzT3B0aW9ucxImCglub3JtYWxpemUYASABKAhCCIq1GAR0cnVlUglub3JtYW'
    'xpemUSHwoIdHJ1bmNhdGUYAiABKAhIAFIIdHJ1bmNhdGWIAQESIgoKYmF0Y2hfc2l6ZRgDIAEo'
    'BUgBUgliYXRjaFNpemWIAQESTgoObm9ybWFsaXplX21vZGUYBCABKA4yJy5ydW5hbnl3aGVyZS'
    '52MS5FbWJlZGRpbmdzTm9ybWFsaXplTW9kZVINbm9ybWFsaXplTW9kZRJDCgdwb29saW5nGAUg'
    'ASgOMikucnVuYW55d2hlcmUudjEuRW1iZWRkaW5nc1Bvb2xpbmdTdHJhdGVneVIHcG9vbGluZx'
    'IbCgluX3RocmVhZHMYBiABKAVSCG5UaHJlYWRzQgsKCV90cnVuY2F0ZUINCgtfYmF0Y2hfc2l6'
    'ZQ==');

@$core.Deprecated('Use embeddingVectorDescriptor instead')
const EmbeddingVector$json = {
  '1': 'EmbeddingVector',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
    {'1': 'norm', '3': 2, '4': 1, '5': 2, '9': 0, '10': 'norm', '17': true},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'text', '17': true},
    {'1': 'dimension', '3': 4, '4': 1, '5': 5, '10': 'dimension'},
    {'1': 'input_index', '3': 5, '4': 1, '5': 5, '10': 'inputIndex'},
    {'1': 'metadata', '3': 6, '4': 3, '5': 11, '6': '.runanywhere.v1.EmbeddingVector.MetadataEntry', '10': 'metadata'},
  ],
  '3': [EmbeddingVector_MetadataEntry$json],
  '8': [
    {'1': '_norm'},
    {'1': '_text'},
  ],
};

@$core.Deprecated('Use embeddingVectorDescriptor instead')
const EmbeddingVector_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `EmbeddingVector`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingVectorDescriptor = $convert.base64Decode(
    'Cg9FbWJlZGRpbmdWZWN0b3ISFgoGdmFsdWVzGAEgAygCUgZ2YWx1ZXMSFwoEbm9ybRgCIAEoAk'
    'gAUgRub3JtiAEBEhcKBHRleHQYAyABKAlIAVIEdGV4dIgBARIcCglkaW1lbnNpb24YBCABKAVS'
    'CWRpbWVuc2lvbhIfCgtpbnB1dF9pbmRleBgFIAEoBVIKaW5wdXRJbmRleBJJCghtZXRhZGF0YR'
    'gGIAMoCzItLnJ1bmFueXdoZXJlLnYxLkVtYmVkZGluZ1ZlY3Rvci5NZXRhZGF0YUVudHJ5Ught'
    'ZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgAS'
    'gJUgV2YWx1ZToCOAFCBwoFX25vcm1CBwoFX3RleHQ=');

@$core.Deprecated('Use embeddingsRequestDescriptor instead')
const EmbeddingsRequest$json = {
  '1': 'EmbeddingsRequest',
  '2': [
    {'1': 'texts', '3': 1, '4': 3, '5': 9, '10': 'texts'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.EmbeddingsOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'model_id', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'modelId', '17': true},
    {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.EmbeddingsRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [EmbeddingsRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
    {'1': '_model_id'},
  ],
};

@$core.Deprecated('Use embeddingsRequestDescriptor instead')
const EmbeddingsRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `EmbeddingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsRequestDescriptor = $convert.base64Decode(
    'ChFFbWJlZGRpbmdzUmVxdWVzdBIUCgV0ZXh0cxgBIAMoCVIFdGV4dHMSQAoHb3B0aW9ucxgCIA'
    'EoCzIhLnJ1bmFueXdoZXJlLnYxLkVtYmVkZGluZ3NPcHRpb25zSABSB29wdGlvbnOIAQESHQoK'
    'cmVxdWVzdF9pZBgDIAEoCVIJcmVxdWVzdElkEh4KCG1vZGVsX2lkGAQgASgJSAFSB21vZGVsSW'
    'SIAQESSwoIbWV0YWRhdGEYBSADKAsyLy5ydW5hbnl3aGVyZS52MS5FbWJlZGRpbmdzUmVxdWVz'
    'dC5NZXRhZGF0YUVudHJ5UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCV'
    'IDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAFCCgoIX29wdGlvbnNCCwoJX21vZGVsX2lk');

@$core.Deprecated('Use embeddingsResultDescriptor instead')
const EmbeddingsResult$json = {
  '1': 'EmbeddingsResult',
  '2': [
    {'1': 'vectors', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.EmbeddingVector', '10': 'vectors'},
    {'1': 'dimension', '3': 2, '4': 1, '5': 5, '10': 'dimension'},
    {'1': 'processing_time_ms', '3': 3, '4': 1, '5': 3, '10': 'processingTimeMs'},
    {'1': 'tokens_used', '3': 4, '4': 1, '5': 5, '10': 'tokensUsed'},
    {'1': 'model_id', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'modelId', '17': true},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 7, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'request_id', '3': 8, '4': 1, '5': 9, '10': 'requestId'},
  ],
  '8': [
    {'1': '_model_id'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `EmbeddingsResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsResultDescriptor = $convert.base64Decode(
    'ChBFbWJlZGRpbmdzUmVzdWx0EjkKB3ZlY3RvcnMYASADKAsyHy5ydW5hbnl3aGVyZS52MS5FbW'
    'JlZGRpbmdWZWN0b3JSB3ZlY3RvcnMSHAoJZGltZW5zaW9uGAIgASgFUglkaW1lbnNpb24SLAoS'
    'cHJvY2Vzc2luZ190aW1lX21zGAMgASgDUhBwcm9jZXNzaW5nVGltZU1zEh8KC3Rva2Vuc191c2'
    'VkGAQgASgFUgp0b2tlbnNVc2VkEh4KCG1vZGVsX2lkGAUgASgJSABSB21vZGVsSWSIAQESKAoN'
    'ZXJyb3JfbWVzc2FnZRgGIAEoCUgBUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3JfY29kZRgHIA'
    'EoBVIJZXJyb3JDb2RlEh0KCnJlcXVlc3RfaWQYCCABKAlSCXJlcXVlc3RJZEILCglfbW9kZWxf'
    'aWRCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use embeddingsServiceStateDescriptor instead')
const EmbeddingsServiceState$json = {
  '1': 'EmbeddingsServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'current_model', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'currentModel', '17': true},
    {'1': 'dimension', '3': 3, '4': 1, '5': 5, '10': 'dimension'},
    {'1': 'max_tokens', '3': 4, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 6, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_current_model'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `EmbeddingsServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsServiceStateDescriptor = $convert.base64Decode(
    'ChZFbWJlZGRpbmdzU2VydmljZVN0YXRlEhkKCGlzX3JlYWR5GAEgASgIUgdpc1JlYWR5EigKDW'
    'N1cnJlbnRfbW9kZWwYAiABKAlIAFIMY3VycmVudE1vZGVsiAEBEhwKCWRpbWVuc2lvbhgDIAEo'
    'BVIJZGltZW5zaW9uEh0KCm1heF90b2tlbnMYBCABKAVSCW1heFRva2VucxIoCg1lcnJvcl9tZX'
    'NzYWdlGAUgASgJSAFSDGVycm9yTWVzc2FnZYgBARIdCgplcnJvcl9jb2RlGAYgASgFUgllcnJv'
    'ckNvZGVCEAoOX2N1cnJlbnRfbW9kZWxCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use embeddingsCreateRequestDescriptor instead')
const EmbeddingsCreateRequest$json = {
  '1': 'EmbeddingsCreateRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'configuration', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.EmbeddingsConfiguration', '9': 0, '10': 'configuration', '17': true},
    {'1': 'config_json', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'configJson', '17': true},
  ],
  '8': [
    {'1': '_configuration'},
    {'1': '_config_json'},
  ],
};

/// Descriptor for `EmbeddingsCreateRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsCreateRequestDescriptor = $convert.base64Decode(
    'ChdFbWJlZGRpbmdzQ3JlYXRlUmVxdWVzdBIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBJSCg'
    '1jb25maWd1cmF0aW9uGAIgASgLMicucnVuYW55d2hlcmUudjEuRW1iZWRkaW5nc0NvbmZpZ3Vy'
    'YXRpb25IAFINY29uZmlndXJhdGlvbogBARIkCgtjb25maWdfanNvbhgDIAEoCUgBUgpjb25maW'
    'dKc29uiAEBQhAKDl9jb25maWd1cmF0aW9uQg4KDF9jb25maWdfanNvbg==');

@$core.Deprecated('Use embeddingsCreateResultDescriptor instead')
const EmbeddingsCreateResult$json = {
  '1': 'EmbeddingsCreateResult',
  '2': [
    {'1': 'handle', '3': 1, '4': 1, '5': 4, '10': 'handle'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'dimension', '3': 3, '4': 1, '5': 5, '10': 'dimension'},
    {'1': 'max_tokens', '3': 4, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `EmbeddingsCreateResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsCreateResultDescriptor = $convert.base64Decode(
    'ChZFbWJlZGRpbmdzQ3JlYXRlUmVzdWx0EhYKBmhhbmRsZRgBIAEoBFIGaGFuZGxlEhkKCG1vZG'
    'VsX2lkGAIgASgJUgdtb2RlbElkEhwKCWRpbWVuc2lvbhgDIAEoBVIJZGltZW5zaW9uEh0KCm1h'
    'eF90b2tlbnMYBCABKAVSCW1heFRva2VucxIdCgplcnJvcl9jb2RlGAUgASgFUgllcnJvckNvZG'
    'USIwoNZXJyb3JfbWVzc2FnZRgGIAEoCVIMZXJyb3JNZXNzYWdl');

const $core.Map<$core.String, $core.dynamic> EmbeddingsServiceBase$json = {
  '1': 'Embeddings',
  '2': [
    {'1': 'Embed', '2': '.runanywhere.v1.EmbeddingsRequest', '3': '.runanywhere.v1.EmbeddingsResult'},
    {'1': 'EmbedBatch', '2': '.runanywhere.v1.EmbeddingsRequest', '3': '.runanywhere.v1.EmbeddingsResult'},
  ],
};

@$core.Deprecated('Use embeddingsServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> EmbeddingsServiceBase$messageJson = {
  '.runanywhere.v1.EmbeddingsRequest': EmbeddingsRequest$json,
  '.runanywhere.v1.EmbeddingsOptions': EmbeddingsOptions$json,
  '.runanywhere.v1.EmbeddingsRequest.MetadataEntry': EmbeddingsRequest_MetadataEntry$json,
  '.runanywhere.v1.EmbeddingsResult': EmbeddingsResult$json,
  '.runanywhere.v1.EmbeddingVector': EmbeddingVector$json,
  '.runanywhere.v1.EmbeddingVector.MetadataEntry': EmbeddingVector_MetadataEntry$json,
};

/// Descriptor for `Embeddings`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List embeddingsServiceDescriptor = $convert.base64Decode(
    'CgpFbWJlZGRpbmdzEkwKBUVtYmVkEiEucnVuYW55d2hlcmUudjEuRW1iZWRkaW5nc1JlcXVlc3'
    'QaIC5ydW5hbnl3aGVyZS52MS5FbWJlZGRpbmdzUmVzdWx0ElEKCkVtYmVkQmF0Y2gSIS5ydW5h'
    'bnl3aGVyZS52MS5FbWJlZGRpbmdzUmVxdWVzdBogLnJ1bmFueXdoZXJlLnYxLkVtYmVkZGluZ3'
    'NSZXN1bHQ=');

