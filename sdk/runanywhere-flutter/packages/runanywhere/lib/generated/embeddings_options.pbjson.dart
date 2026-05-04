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
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'embedding_dimension', '3': 2, '4': 1, '5': 5, '10': 'embeddingDimension'},
    {'1': 'max_sequence_length', '3': 3, '4': 1, '5': 5, '10': 'maxSequenceLength'},
    {'1': 'normalize', '3': 4, '4': 1, '5': 8, '9': 0, '10': 'normalize', '17': true},
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
    'ChdFbWJlZGRpbmdzQ29uZmlndXJhdGlvbhIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBIvCh'
    'NlbWJlZGRpbmdfZGltZW5zaW9uGAIgASgFUhJlbWJlZGRpbmdEaW1lbnNpb24SLgoTbWF4X3Nl'
    'cXVlbmNlX2xlbmd0aBgDIAEoBVIRbWF4U2VxdWVuY2VMZW5ndGgSIQoJbm9ybWFsaXplGAQgAS'
    'gISABSCW5vcm1hbGl6ZYgBARJYChNwcmVmZXJyZWRfZnJhbWV3b3JrGAUgASgOMiIucnVuYW55'
    'd2hlcmUudjEuSW5mZXJlbmNlRnJhbWV3b3JrSAFSEnByZWZlcnJlZEZyYW1ld29ya4gBARIdCg'
    'ptYXhfdG9rZW5zGAYgASgFUgltYXhUb2tlbnMSTgoObm9ybWFsaXplX21vZGUYByABKA4yJy5y'
    'dW5hbnl3aGVyZS52MS5FbWJlZGRpbmdzTm9ybWFsaXplTW9kZVINbm9ybWFsaXplTW9kZRJDCg'
    'dwb29saW5nGAggASgOMikucnVuYW55d2hlcmUudjEuRW1iZWRkaW5nc1Bvb2xpbmdTdHJhdGVn'
    'eVIHcG9vbGluZxIkCgtjb25maWdfanNvbhgJIAEoCUgCUgpjb25maWdKc29uiAEBQgwKCl9ub3'
    'JtYWxpemVCFgoUX3ByZWZlcnJlZF9mcmFtZXdvcmtCDgoMX2NvbmZpZ19qc29u');

@$core.Deprecated('Use embeddingsOptionsDescriptor instead')
const EmbeddingsOptions$json = {
  '1': 'EmbeddingsOptions',
  '2': [
    {'1': 'normalize', '3': 1, '4': 1, '5': 8, '10': 'normalize'},
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
    'ChFFbWJlZGRpbmdzT3B0aW9ucxIcCglub3JtYWxpemUYASABKAhSCW5vcm1hbGl6ZRIfCgh0cn'
    'VuY2F0ZRgCIAEoCEgAUgh0cnVuY2F0ZYgBARIiCgpiYXRjaF9zaXplGAMgASgFSAFSCWJhdGNo'
    'U2l6ZYgBARJOCg5ub3JtYWxpemVfbW9kZRgEIAEoDjInLnJ1bmFueXdoZXJlLnYxLkVtYmVkZG'
    'luZ3NOb3JtYWxpemVNb2RlUg1ub3JtYWxpemVNb2RlEkMKB3Bvb2xpbmcYBSABKA4yKS5ydW5h'
    'bnl3aGVyZS52MS5FbWJlZGRpbmdzUG9vbGluZ1N0cmF0ZWd5Ugdwb29saW5nEhsKCW5fdGhyZW'
    'FkcxgGIAEoBVIIblRocmVhZHNCCwoJX3RydW5jYXRlQg0KC19iYXRjaF9zaXpl');

@$core.Deprecated('Use embeddingVectorDescriptor instead')
const EmbeddingVector$json = {
  '1': 'EmbeddingVector',
  '2': [
    {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
    {'1': 'norm', '3': 2, '4': 1, '5': 2, '9': 0, '10': 'norm', '17': true},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'text', '17': true},
    {'1': 'dimension', '3': 4, '4': 1, '5': 5, '10': 'dimension'},
  ],
  '8': [
    {'1': '_norm'},
    {'1': '_text'},
  ],
};

/// Descriptor for `EmbeddingVector`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingVectorDescriptor = $convert.base64Decode(
    'Cg9FbWJlZGRpbmdWZWN0b3ISFgoGdmFsdWVzGAEgAygCUgZ2YWx1ZXMSFwoEbm9ybRgCIAEoAk'
    'gAUgRub3JtiAEBEhcKBHRleHQYAyABKAlIAVIEdGV4dIgBARIcCglkaW1lbnNpb24YBCABKAVS'
    'CWRpbWVuc2lvbkIHCgVfbm9ybUIHCgVfdGV4dA==');

@$core.Deprecated('Use embeddingsRequestDescriptor instead')
const EmbeddingsRequest$json = {
  '1': 'EmbeddingsRequest',
  '2': [
    {'1': 'texts', '3': 1, '4': 3, '5': 9, '10': 'texts'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.EmbeddingsOptions', '9': 0, '10': 'options', '17': true},
  ],
  '8': [
    {'1': '_options'},
  ],
};

/// Descriptor for `EmbeddingsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsRequestDescriptor = $convert.base64Decode(
    'ChFFbWJlZGRpbmdzUmVxdWVzdBIUCgV0ZXh0cxgBIAMoCVIFdGV4dHMSQAoHb3B0aW9ucxgCIA'
    'EoCzIhLnJ1bmFueXdoZXJlLnYxLkVtYmVkZGluZ3NPcHRpb25zSABSB29wdGlvbnOIAQFCCgoI'
    'X29wdGlvbnM=');

@$core.Deprecated('Use embeddingsResultDescriptor instead')
const EmbeddingsResult$json = {
  '1': 'EmbeddingsResult',
  '2': [
    {'1': 'vectors', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.EmbeddingVector', '10': 'vectors'},
    {'1': 'dimension', '3': 2, '4': 1, '5': 5, '10': 'dimension'},
    {'1': 'processing_time_ms', '3': 3, '4': 1, '5': 3, '10': 'processingTimeMs'},
    {'1': 'tokens_used', '3': 4, '4': 1, '5': 5, '10': 'tokensUsed'},
  ],
};

/// Descriptor for `EmbeddingsResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsResultDescriptor = $convert.base64Decode(
    'ChBFbWJlZGRpbmdzUmVzdWx0EjkKB3ZlY3RvcnMYASADKAsyHy5ydW5hbnl3aGVyZS52MS5FbW'
    'JlZGRpbmdWZWN0b3JSB3ZlY3RvcnMSHAoJZGltZW5zaW9uGAIgASgFUglkaW1lbnNpb24SLAoS'
    'cHJvY2Vzc2luZ190aW1lX21zGAMgASgDUhBwcm9jZXNzaW5nVGltZU1zEh8KC3Rva2Vuc191c2'
    'VkGAQgASgFUgp0b2tlbnNVc2Vk');

