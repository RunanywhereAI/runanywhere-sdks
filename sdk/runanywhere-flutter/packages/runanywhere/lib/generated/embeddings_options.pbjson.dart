///
//  Generated code. Do not modify.
//  source: embeddings_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use embeddingsConfigurationDescriptor instead')
const EmbeddingsConfiguration$json = const {
  '1': 'EmbeddingsConfiguration',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'embedding_dimension', '3': 2, '4': 1, '5': 5, '10': 'embeddingDimension'},
    const {'1': 'max_sequence_length', '3': 3, '4': 1, '5': 5, '10': 'maxSequenceLength'},
    const {'1': 'normalize', '3': 4, '4': 1, '5': 8, '9': 0, '10': 'normalize', '17': true},
  ],
  '8': const [
    const {'1': '_normalize'},
  ],
};

/// Descriptor for `EmbeddingsConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsConfigurationDescriptor = $convert.base64Decode('ChdFbWJlZGRpbmdzQ29uZmlndXJhdGlvbhIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBIvChNlbWJlZGRpbmdfZGltZW5zaW9uGAIgASgFUhJlbWJlZGRpbmdEaW1lbnNpb24SLgoTbWF4X3NlcXVlbmNlX2xlbmd0aBgDIAEoBVIRbWF4U2VxdWVuY2VMZW5ndGgSIQoJbm9ybWFsaXplGAQgASgISABSCW5vcm1hbGl6ZYgBAUIMCgpfbm9ybWFsaXpl');
@$core.Deprecated('Use embeddingsOptionsDescriptor instead')
const EmbeddingsOptions$json = const {
  '1': 'EmbeddingsOptions',
  '2': const [
    const {'1': 'normalize', '3': 1, '4': 1, '5': 8, '10': 'normalize'},
    const {'1': 'truncate', '3': 2, '4': 1, '5': 8, '9': 0, '10': 'truncate', '17': true},
    const {'1': 'batch_size', '3': 3, '4': 1, '5': 5, '9': 1, '10': 'batchSize', '17': true},
  ],
  '8': const [
    const {'1': '_truncate'},
    const {'1': '_batch_size'},
  ],
};

/// Descriptor for `EmbeddingsOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsOptionsDescriptor = $convert.base64Decode('ChFFbWJlZGRpbmdzT3B0aW9ucxIcCglub3JtYWxpemUYASABKAhSCW5vcm1hbGl6ZRIfCgh0cnVuY2F0ZRgCIAEoCEgAUgh0cnVuY2F0ZYgBARIiCgpiYXRjaF9zaXplGAMgASgFSAFSCWJhdGNoU2l6ZYgBAUILCglfdHJ1bmNhdGVCDQoLX2JhdGNoX3NpemU=');
@$core.Deprecated('Use embeddingVectorDescriptor instead')
const EmbeddingVector$json = const {
  '1': 'EmbeddingVector',
  '2': const [
    const {'1': 'values', '3': 1, '4': 3, '5': 2, '10': 'values'},
    const {'1': 'norm', '3': 2, '4': 1, '5': 2, '9': 0, '10': 'norm', '17': true},
    const {'1': 'text', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'text', '17': true},
  ],
  '8': const [
    const {'1': '_norm'},
    const {'1': '_text'},
  ],
};

/// Descriptor for `EmbeddingVector`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingVectorDescriptor = $convert.base64Decode('Cg9FbWJlZGRpbmdWZWN0b3ISFgoGdmFsdWVzGAEgAygCUgZ2YWx1ZXMSFwoEbm9ybRgCIAEoAkgAUgRub3JtiAEBEhcKBHRleHQYAyABKAlIAVIEdGV4dIgBAUIHCgVfbm9ybUIHCgVfdGV4dA==');
@$core.Deprecated('Use embeddingsResultDescriptor instead')
const EmbeddingsResult$json = const {
  '1': 'EmbeddingsResult',
  '2': const [
    const {'1': 'vectors', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.EmbeddingVector', '10': 'vectors'},
    const {'1': 'dimension', '3': 2, '4': 1, '5': 5, '10': 'dimension'},
    const {'1': 'processing_time_ms', '3': 3, '4': 1, '5': 3, '10': 'processingTimeMs'},
    const {'1': 'tokens_used', '3': 4, '4': 1, '5': 5, '10': 'tokensUsed'},
  ],
};

/// Descriptor for `EmbeddingsResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List embeddingsResultDescriptor = $convert.base64Decode('ChBFbWJlZGRpbmdzUmVzdWx0EjkKB3ZlY3RvcnMYASADKAsyHy5ydW5hbnl3aGVyZS52MS5FbWJlZGRpbmdWZWN0b3JSB3ZlY3RvcnMSHAoJZGltZW5zaW9uGAIgASgFUglkaW1lbnNpb24SLAoScHJvY2Vzc2luZ190aW1lX21zGAMgASgDUhBwcm9jZXNzaW5nVGltZU1zEh8KC3Rva2Vuc191c2VkGAQgASgFUgp0b2tlbnNVc2Vk');
