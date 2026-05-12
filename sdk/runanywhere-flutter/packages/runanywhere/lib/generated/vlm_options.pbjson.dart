//
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use vLMImageFormatDescriptor instead')
const VLMImageFormat$json = {
  '1': 'VLMImageFormat',
  '2': [
    {'1': 'VLM_IMAGE_FORMAT_UNSPECIFIED', '2': 0},
    {'1': 'VLM_IMAGE_FORMAT_JPEG', '2': 1},
    {'1': 'VLM_IMAGE_FORMAT_PNG', '2': 2},
    {'1': 'VLM_IMAGE_FORMAT_WEBP', '2': 3},
    {'1': 'VLM_IMAGE_FORMAT_RAW_RGB', '2': 4},
    {'1': 'VLM_IMAGE_FORMAT_RAW_RGBA', '2': 5},
    {'1': 'VLM_IMAGE_FORMAT_BASE64', '2': 6},
    {'1': 'VLM_IMAGE_FORMAT_FILE_PATH', '2': 7},
  ],
};

/// Descriptor for `VLMImageFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vLMImageFormatDescriptor = $convert.base64Decode(
    'Cg5WTE1JbWFnZUZvcm1hdBIgChxWTE1fSU1BR0VfRk9STUFUX1VOU1BFQ0lGSUVEEAASGQoVVk'
    'xNX0lNQUdFX0ZPUk1BVF9KUEVHEAESGAoUVkxNX0lNQUdFX0ZPUk1BVF9QTkcQAhIZChVWTE1f'
    'SU1BR0VfRk9STUFUX1dFQlAQAxIcChhWTE1fSU1BR0VfRk9STUFUX1JBV19SR0IQBBIdChlWTE'
    '1fSU1BR0VfRk9STUFUX1JBV19SR0JBEAUSGwoXVkxNX0lNQUdFX0ZPUk1BVF9CQVNFNjQQBhIe'
    'ChpWTE1fSU1BR0VfRk9STUFUX0ZJTEVfUEFUSBAH');

@$core.Deprecated('Use vLMModelFamilyDescriptor instead')
const VLMModelFamily$json = {
  '1': 'VLMModelFamily',
  '2': [
    {'1': 'VLM_MODEL_FAMILY_UNSPECIFIED', '2': 0},
    {'1': 'VLM_MODEL_FAMILY_AUTO', '2': 1},
    {'1': 'VLM_MODEL_FAMILY_QWEN2_VL', '2': 2},
    {'1': 'VLM_MODEL_FAMILY_SMOLVLM', '2': 3},
    {'1': 'VLM_MODEL_FAMILY_LLAVA', '2': 4},
    {'1': 'VLM_MODEL_FAMILY_CUSTOM', '2': 99},
  ],
};

/// Descriptor for `VLMModelFamily`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vLMModelFamilyDescriptor = $convert.base64Decode(
    'Cg5WTE1Nb2RlbEZhbWlseRIgChxWTE1fTU9ERUxfRkFNSUxZX1VOU1BFQ0lGSUVEEAASGQoVVk'
    'xNX01PREVMX0ZBTUlMWV9BVVRPEAESHQoZVkxNX01PREVMX0ZBTUlMWV9RV0VOMl9WTBACEhwK'
    'GFZMTV9NT0RFTF9GQU1JTFlfU01PTFZMTRADEhoKFlZMTV9NT0RFTF9GQU1JTFlfTExBVkEQBB'
    'IbChdWTE1fTU9ERUxfRkFNSUxZX0NVU1RPTRBj');

@$core.Deprecated('Use vLMStreamEventKindDescriptor instead')
const VLMStreamEventKind$json = {
  '1': 'VLMStreamEventKind',
  '2': [
    {'1': 'VLM_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'VLM_STREAM_EVENT_KIND_STARTED', '2': 1},
    {'1': 'VLM_STREAM_EVENT_KIND_IMAGE_ENCODED', '2': 2},
    {'1': 'VLM_STREAM_EVENT_KIND_TOKEN', '2': 3},
    {'1': 'VLM_STREAM_EVENT_KIND_COMPLETED', '2': 4},
    {'1': 'VLM_STREAM_EVENT_KIND_ERROR', '2': 5},
  ],
};

/// Descriptor for `VLMStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vLMStreamEventKindDescriptor = $convert.base64Decode(
    'ChJWTE1TdHJlYW1FdmVudEtpbmQSJQohVkxNX1NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSU'
    'VEEAASIQodVkxNX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVJURUQQARInCiNWTE1fU1RSRUFNX0VW'
    'RU5UX0tJTkRfSU1BR0VfRU5DT0RFRBACEh8KG1ZMTV9TVFJFQU1fRVZFTlRfS0lORF9UT0tFTh'
    'ADEiMKH1ZMTV9TVFJFQU1fRVZFTlRfS0lORF9DT01QTEVURUQQBBIfChtWTE1fU1RSRUFNX0VW'
    'RU5UX0tJTkRfRVJST1IQBQ==');

@$core.Deprecated('Use vLMChatTemplateDescriptor instead')
const VLMChatTemplate$json = {
  '1': 'VLMChatTemplate',
  '2': [
    {'1': 'template_text', '3': 1, '4': 1, '5': 9, '10': 'templateText'},
    {'1': 'image_marker', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'imageMarker', '17': true},
    {'1': 'default_system_prompt', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'defaultSystemPrompt', '17': true},
  ],
  '8': [
    {'1': '_image_marker'},
    {'1': '_default_system_prompt'},
  ],
};

/// Descriptor for `VLMChatTemplate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMChatTemplateDescriptor = $convert.base64Decode(
    'Cg9WTE1DaGF0VGVtcGxhdGUSIwoNdGVtcGxhdGVfdGV4dBgBIAEoCVIMdGVtcGxhdGVUZXh0Ei'
    'YKDGltYWdlX21hcmtlchgCIAEoCUgAUgtpbWFnZU1hcmtlcogBARI3ChVkZWZhdWx0X3N5c3Rl'
    'bV9wcm9tcHQYAyABKAlIAVITZGVmYXVsdFN5c3RlbVByb21wdIgBAUIPCg1faW1hZ2VfbWFya2'
    'VyQhgKFl9kZWZhdWx0X3N5c3RlbV9wcm9tcHQ=');

@$core.Deprecated('Use vLMImageDescriptor instead')
const VLMImage$json = {
  '1': 'VLMImage',
  '2': [
    {'1': 'file_path', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'filePath'},
    {'1': 'encoded', '3': 2, '4': 1, '5': 12, '9': 0, '10': 'encoded'},
    {'1': 'raw_rgb', '3': 3, '4': 1, '5': 12, '9': 0, '10': 'rawRgb'},
    {'1': 'base64', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'base64'},
    {'1': 'width', '3': 5, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 6, '4': 1, '5': 5, '10': 'height'},
    {'1': 'format', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.VLMImageFormat', '10': 'format'},
    {'1': 'media_type', '3': 8, '4': 1, '5': 9, '9': 1, '10': 'mediaType', '17': true},
    {'1': 'name', '3': 9, '4': 1, '5': 9, '9': 2, '10': 'name', '17': true},
    {'1': 'size_bytes', '3': 10, '4': 1, '5': 3, '10': 'sizeBytes'},
    {'1': 'metadata', '3': 11, '4': 3, '5': 11, '6': '.runanywhere.v1.VLMImage.MetadataEntry', '10': 'metadata'},
  ],
  '3': [VLMImage_MetadataEntry$json],
  '8': [
    {'1': 'source'},
    {'1': '_media_type'},
    {'1': '_name'},
  ],
};

@$core.Deprecated('Use vLMImageDescriptor instead')
const VLMImage_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `VLMImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMImageDescriptor = $convert.base64Decode(
    'CghWTE1JbWFnZRIdCglmaWxlX3BhdGgYASABKAlIAFIIZmlsZVBhdGgSGgoHZW5jb2RlZBgCIA'
    'EoDEgAUgdlbmNvZGVkEhkKB3Jhd19yZ2IYAyABKAxIAFIGcmF3UmdiEhgKBmJhc2U2NBgEIAEo'
    'CUgAUgZiYXNlNjQSFAoFd2lkdGgYBSABKAVSBXdpZHRoEhYKBmhlaWdodBgGIAEoBVIGaGVpZ2'
    'h0EjYKBmZvcm1hdBgHIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlZMTUltYWdlRm9ybWF0UgZmb3Jt'
    'YXQSIgoKbWVkaWFfdHlwZRgIIAEoCUgBUgltZWRpYVR5cGWIAQESFwoEbmFtZRgJIAEoCUgCUg'
    'RuYW1liAEBEh0KCnNpemVfYnl0ZXMYCiABKANSCXNpemVCeXRlcxJCCghtZXRhZGF0YRgLIAMo'
    'CzImLnJ1bmFueXdoZXJlLnYxLlZMTUltYWdlLk1ldGFkYXRhRW50cnlSCG1ldGFkYXRhGjsKDU'
    '1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4'
    'AUIICgZzb3VyY2VCDQoLX21lZGlhX3R5cGVCBwoFX25hbWU=');

@$core.Deprecated('Use vLMConfigurationDescriptor instead')
const VLMConfiguration$json = {
  '1': 'VLMConfiguration',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'max_image_size_px', '3': 2, '4': 1, '5': 5, '10': 'maxImageSizePx'},
    {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'context_length', '3': 4, '4': 1, '5': 5, '10': 'contextLength'},
    {'1': 'temperature', '3': 5, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'system_prompt', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'streaming_enabled', '3': 7, '4': 1, '5': 8, '10': 'streamingEnabled'},
    {'1': 'preferred_framework', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'preferredFramework', '17': true},
  ],
  '8': [
    {'1': '_system_prompt'},
    {'1': '_preferred_framework'},
  ],
};

/// Descriptor for `VLMConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMConfigurationDescriptor = $convert.base64Decode(
    'ChBWTE1Db25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEikKEW1heF9pbW'
    'FnZV9zaXplX3B4GAIgASgFUg5tYXhJbWFnZVNpemVQeBIdCgptYXhfdG9rZW5zGAMgASgFUglt'
    'YXhUb2tlbnMSJQoOY29udGV4dF9sZW5ndGgYBCABKAVSDWNvbnRleHRMZW5ndGgSIAoLdGVtcG'
    'VyYXR1cmUYBSABKAJSC3RlbXBlcmF0dXJlEigKDXN5c3RlbV9wcm9tcHQYBiABKAlIAFIMc3lz'
    'dGVtUHJvbXB0iAEBEisKEXN0cmVhbWluZ19lbmFibGVkGAcgASgIUhBzdHJlYW1pbmdFbmFibG'
    'VkElgKE3ByZWZlcnJlZF9mcmFtZXdvcmsYCCABKA4yIi5ydW5hbnl3aGVyZS52MS5JbmZlcmVu'
    'Y2VGcmFtZXdvcmtIAVIScHJlZmVycmVkRnJhbWV3b3JriAEBQhAKDl9zeXN0ZW1fcHJvbXB0Qh'
    'YKFF9wcmVmZXJyZWRfZnJhbWV3b3Jr');

@$core.Deprecated('Use vLMGenerationOptionsDescriptor instead')
const VLMGenerationOptions$json = {
  '1': 'VLMGenerationOptions',
  '2': [
    {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    {'1': 'max_tokens', '3': 2, '4': 1, '5': 5, '10': 'maxTokens'},
    {'1': 'temperature', '3': 3, '4': 1, '5': 2, '10': 'temperature'},
    {'1': 'top_p', '3': 4, '4': 1, '5': 2, '10': 'topP'},
    {'1': 'top_k', '3': 5, '4': 1, '5': 5, '10': 'topK'},
    {'1': 'stop_sequences', '3': 6, '4': 3, '5': 9, '10': 'stopSequences'},
    {'1': 'streaming_enabled', '3': 7, '4': 1, '5': 8, '10': 'streamingEnabled'},
    {'1': 'system_prompt', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'systemPrompt', '17': true},
    {'1': 'max_image_size', '3': 9, '4': 1, '5': 5, '10': 'maxImageSize'},
    {'1': 'n_threads', '3': 10, '4': 1, '5': 5, '10': 'nThreads'},
    {'1': 'use_gpu', '3': 11, '4': 1, '5': 8, '10': 'useGpu'},
    {'1': 'model_family', '3': 12, '4': 1, '5': 14, '6': '.runanywhere.v1.VLMModelFamily', '10': 'modelFamily'},
    {'1': 'custom_chat_template', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.VLMChatTemplate', '9': 1, '10': 'customChatTemplate', '17': true},
    {'1': 'image_marker_override', '3': 14, '4': 1, '5': 9, '9': 2, '10': 'imageMarkerOverride', '17': true},
    {'1': 'seed', '3': 15, '4': 1, '5': 3, '10': 'seed'},
    {'1': 'repetition_penalty', '3': 16, '4': 1, '5': 2, '10': 'repetitionPenalty'},
    {'1': 'min_p', '3': 17, '4': 1, '5': 2, '10': 'minP'},
    {'1': 'emit_image_embeddings', '3': 18, '4': 1, '5': 8, '10': 'emitImageEmbeddings'},
  ],
  '8': [
    {'1': '_system_prompt'},
    {'1': '_custom_chat_template'},
    {'1': '_image_marker_override'},
  ],
};

/// Descriptor for `VLMGenerationOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMGenerationOptionsDescriptor = $convert.base64Decode(
    'ChRWTE1HZW5lcmF0aW9uT3B0aW9ucxIWCgZwcm9tcHQYASABKAlSBnByb21wdBIdCgptYXhfdG'
    '9rZW5zGAIgASgFUgltYXhUb2tlbnMSIAoLdGVtcGVyYXR1cmUYAyABKAJSC3RlbXBlcmF0dXJl'
    'EhMKBXRvcF9wGAQgASgCUgR0b3BQEhMKBXRvcF9rGAUgASgFUgR0b3BLEiUKDnN0b3Bfc2VxdW'
    'VuY2VzGAYgAygJUg1zdG9wU2VxdWVuY2VzEisKEXN0cmVhbWluZ19lbmFibGVkGAcgASgIUhBz'
    'dHJlYW1pbmdFbmFibGVkEigKDXN5c3RlbV9wcm9tcHQYCCABKAlIAFIMc3lzdGVtUHJvbXB0iA'
    'EBEiQKDm1heF9pbWFnZV9zaXplGAkgASgFUgxtYXhJbWFnZVNpemUSGwoJbl90aHJlYWRzGAog'
    'ASgFUghuVGhyZWFkcxIXCgd1c2VfZ3B1GAsgASgIUgZ1c2VHcHUSQQoMbW9kZWxfZmFtaWx5GA'
    'wgASgOMh4ucnVuYW55d2hlcmUudjEuVkxNTW9kZWxGYW1pbHlSC21vZGVsRmFtaWx5ElYKFGN1'
    'c3RvbV9jaGF0X3RlbXBsYXRlGA0gASgLMh8ucnVuYW55d2hlcmUudjEuVkxNQ2hhdFRlbXBsYX'
    'RlSAFSEmN1c3RvbUNoYXRUZW1wbGF0ZYgBARI3ChVpbWFnZV9tYXJrZXJfb3ZlcnJpZGUYDiAB'
    'KAlIAlITaW1hZ2VNYXJrZXJPdmVycmlkZYgBARISCgRzZWVkGA8gASgDUgRzZWVkEi0KEnJlcG'
    'V0aXRpb25fcGVuYWx0eRgQIAEoAlIRcmVwZXRpdGlvblBlbmFsdHkSEwoFbWluX3AYESABKAJS'
    'BG1pblASMgoVZW1pdF9pbWFnZV9lbWJlZGRpbmdzGBIgASgIUhNlbWl0SW1hZ2VFbWJlZGRpbm'
    'dzQhAKDl9zeXN0ZW1fcHJvbXB0QhcKFV9jdXN0b21fY2hhdF90ZW1wbGF0ZUIYChZfaW1hZ2Vf'
    'bWFya2VyX292ZXJyaWRl');

@$core.Deprecated('Use vLMGenerationRequestDescriptor instead')
const VLMGenerationRequest$json = {
  '1': 'VLMGenerationRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'images', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.VLMImage', '10': 'images'},
    {'1': 'options', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.VLMGenerationOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'model_id', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'modelId', '17': true},
    {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.VLMGenerationRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [VLMGenerationRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
    {'1': '_model_id'},
  ],
};

@$core.Deprecated('Use vLMGenerationRequestDescriptor instead')
const VLMGenerationRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `VLMGenerationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMGenerationRequestDescriptor = $convert.base64Decode(
    'ChRWTE1HZW5lcmF0aW9uUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSMA'
    'oGaW1hZ2VzGAIgAygLMhgucnVuYW55d2hlcmUudjEuVkxNSW1hZ2VSBmltYWdlcxJDCgdvcHRp'
    'b25zGAMgASgLMiQucnVuYW55d2hlcmUudjEuVkxNR2VuZXJhdGlvbk9wdGlvbnNIAFIHb3B0aW'
    '9uc4gBARIeCghtb2RlbF9pZBgEIAEoCUgBUgdtb2RlbElkiAEBEk4KCG1ldGFkYXRhGAUgAygL'
    'MjIucnVuYW55d2hlcmUudjEuVkxNR2VuZXJhdGlvblJlcXVlc3QuTWV0YWRhdGFFbnRyeVIIbW'
    'V0YWRhdGEaOwoNTWV0YWRhdGFFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEo'
    'CVIFdmFsdWU6AjgBQgoKCF9vcHRpb25zQgsKCV9tb2RlbF9pZA==');

@$core.Deprecated('Use vLMResultDescriptor instead')
const VLMResult$json = {
  '1': 'VLMResult',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'prompt_tokens', '3': 2, '4': 1, '5': 5, '10': 'promptTokens'},
    {'1': 'completion_tokens', '3': 3, '4': 1, '5': 5, '10': 'completionTokens'},
    {'1': 'total_tokens', '3': 4, '4': 1, '5': 3, '10': 'totalTokens'},
    {'1': 'processing_time_ms', '3': 5, '4': 1, '5': 3, '10': 'processingTimeMs'},
    {'1': 'tokens_per_second', '3': 6, '4': 1, '5': 2, '10': 'tokensPerSecond'},
    {'1': 'image_tokens', '3': 7, '4': 1, '5': 5, '10': 'imageTokens'},
    {'1': 'time_to_first_token_ms', '3': 8, '4': 1, '5': 3, '10': 'timeToFirstTokenMs'},
    {'1': 'image_encode_time_ms', '3': 9, '4': 1, '5': 3, '10': 'imageEncodeTimeMs'},
    {'1': 'hardware_used', '3': 10, '4': 1, '5': 9, '9': 0, '10': 'hardwareUsed', '17': true},
    {'1': 'error_message', '3': 11, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 12, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'finish_reason', '3': 13, '4': 1, '5': 9, '10': 'finishReason'},
    {'1': 'images_processed', '3': 14, '4': 1, '5': 5, '10': 'imagesProcessed'},
  ],
  '8': [
    {'1': '_hardware_used'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VLMResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMResultDescriptor = $convert.base64Decode(
    'CglWTE1SZXN1bHQSEgoEdGV4dBgBIAEoCVIEdGV4dBIjCg1wcm9tcHRfdG9rZW5zGAIgASgFUg'
    'xwcm9tcHRUb2tlbnMSKwoRY29tcGxldGlvbl90b2tlbnMYAyABKAVSEGNvbXBsZXRpb25Ub2tl'
    'bnMSIQoMdG90YWxfdG9rZW5zGAQgASgDUgt0b3RhbFRva2VucxIsChJwcm9jZXNzaW5nX3RpbW'
    'VfbXMYBSABKANSEHByb2Nlc3NpbmdUaW1lTXMSKgoRdG9rZW5zX3Blcl9zZWNvbmQYBiABKAJS'
    'D3Rva2Vuc1BlclNlY29uZBIhCgxpbWFnZV90b2tlbnMYByABKAVSC2ltYWdlVG9rZW5zEjIKFn'
    'RpbWVfdG9fZmlyc3RfdG9rZW5fbXMYCCABKANSEnRpbWVUb0ZpcnN0VG9rZW5NcxIvChRpbWFn'
    'ZV9lbmNvZGVfdGltZV9tcxgJIAEoA1IRaW1hZ2VFbmNvZGVUaW1lTXMSKAoNaGFyZHdhcmVfdX'
    'NlZBgKIAEoCUgAUgxoYXJkd2FyZVVzZWSIAQESKAoNZXJyb3JfbWVzc2FnZRgLIAEoCUgBUgxl'
    'cnJvck1lc3NhZ2WIAQESHQoKZXJyb3JfY29kZRgMIAEoBVIJZXJyb3JDb2RlEiMKDWZpbmlzaF'
    '9yZWFzb24YDSABKAlSDGZpbmlzaFJlYXNvbhIpChBpbWFnZXNfcHJvY2Vzc2VkGA4gASgFUg9p'
    'bWFnZXNQcm9jZXNzZWRCEAoOX2hhcmR3YXJlX3VzZWRCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use vLMStreamEventDescriptor instead')
const VLMStreamEvent$json = {
  '1': 'VLMStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.VLMStreamEventKind', '10': 'kind'},
    {'1': 'token', '3': 5, '4': 1, '5': 9, '10': 'token'},
    {'1': 'token_index', '3': 6, '4': 1, '5': 5, '10': 'tokenIndex'},
    {'1': 'is_final', '3': 7, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'tokens_per_second', '3': 8, '4': 1, '5': 2, '10': 'tokensPerSecond'},
    {'1': 'result', '3': 9, '4': 1, '5': 11, '6': '.runanywhere.v1.VLMResult', '9': 0, '10': 'result', '17': true},
    {'1': 'error_message', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 11, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VLMStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMStreamEventDescriptor = $convert.base64Decode(
    'Cg5WTE1TdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKA'
    'NSC3RpbWVzdGFtcFVzEh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJZBI2CgRraW5kGAQg'
    'ASgOMiIucnVuYW55d2hlcmUudjEuVkxNU3RyZWFtRXZlbnRLaW5kUgRraW5kEhQKBXRva2VuGA'
    'UgASgJUgV0b2tlbhIfCgt0b2tlbl9pbmRleBgGIAEoBVIKdG9rZW5JbmRleBIZCghpc19maW5h'
    'bBgHIAEoCFIHaXNGaW5hbBIqChF0b2tlbnNfcGVyX3NlY29uZBgIIAEoAlIPdG9rZW5zUGVyU2'
    'Vjb25kEjYKBnJlc3VsdBgJIAEoCzIZLnJ1bmFueXdoZXJlLnYxLlZMTVJlc3VsdEgAUgZyZXN1'
    'bHSIAQESKAoNZXJyb3JfbWVzc2FnZRgKIAEoCUgBUgxlcnJvck1lc3NhZ2WIAQESHQoKZXJyb3'
    'JfY29kZRgLIAEoBVIJZXJyb3JDb2RlQgkKB19yZXN1bHRCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use vLMServiceStateDescriptor instead')
const VLMServiceState$json = {
  '1': 'VLMServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'current_model', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'currentModel', '17': true},
    {'1': 'context_length', '3': 3, '4': 1, '5': 5, '10': 'contextLength'},
    {'1': 'supports_streaming', '3': 4, '4': 1, '5': 8, '10': 'supportsStreaming'},
    {'1': 'supports_multiple_images', '3': 5, '4': 1, '5': 8, '10': 'supportsMultipleImages'},
    {'1': 'vision_encoder_type', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'visionEncoderType', '17': true},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 8, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_current_model'},
    {'1': '_vision_encoder_type'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VLMServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMServiceStateDescriptor = $convert.base64Decode(
    'Cg9WTE1TZXJ2aWNlU3RhdGUSGQoIaXNfcmVhZHkYASABKAhSB2lzUmVhZHkSKAoNY3VycmVudF'
    '9tb2RlbBgCIAEoCUgAUgxjdXJyZW50TW9kZWyIAQESJQoOY29udGV4dF9sZW5ndGgYAyABKAVS'
    'DWNvbnRleHRMZW5ndGgSLQoSc3VwcG9ydHNfc3RyZWFtaW5nGAQgASgIUhFzdXBwb3J0c1N0cm'
    'VhbWluZxI4ChhzdXBwb3J0c19tdWx0aXBsZV9pbWFnZXMYBSABKAhSFnN1cHBvcnRzTXVsdGlw'
    'bGVJbWFnZXMSMwoTdmlzaW9uX2VuY29kZXJfdHlwZRgGIAEoCUgBUhF2aXNpb25FbmNvZGVyVH'
    'lwZYgBARIoCg1lcnJvcl9tZXNzYWdlGAcgASgJSAJSDGVycm9yTWVzc2FnZYgBARIdCgplcnJv'
    'cl9jb2RlGAggASgFUgllcnJvckNvZGVCEAoOX2N1cnJlbnRfbW9kZWxCFgoUX3Zpc2lvbl9lbm'
    'NvZGVyX3R5cGVCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use vLMLoadResolvedArtifactsRequestDescriptor instead')
const VLMLoadResolvedArtifactsRequest$json = {
  '1': 'VLMLoadResolvedArtifactsRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'primary_model_path', '3': 2, '4': 1, '5': 9, '10': 'primaryModelPath'},
    {'1': 'mmproj_path', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'mmprojPath', '17': true},
  ],
  '8': [
    {'1': '_mmproj_path'},
  ],
};

/// Descriptor for `VLMLoadResolvedArtifactsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMLoadResolvedArtifactsRequestDescriptor = $convert.base64Decode(
    'Ch9WTE1Mb2FkUmVzb2x2ZWRBcnRpZmFjdHNSZXF1ZXN0EhkKCG1vZGVsX2lkGAEgASgJUgdtb2'
    'RlbElkEiwKEnByaW1hcnlfbW9kZWxfcGF0aBgCIAEoCVIQcHJpbWFyeU1vZGVsUGF0aBIkCgtt'
    'bXByb2pfcGF0aBgDIAEoCUgAUgptbXByb2pQYXRoiAEBQg4KDF9tbXByb2pfcGF0aA==');

@$core.Deprecated('Use vLMLoadResolvedArtifactsResponseDescriptor instead')
const VLMLoadResolvedArtifactsResponse$json = {
  '1': 'VLMLoadResolvedArtifactsResponse',
  '2': [
    {'1': 'handle', '3': 1, '4': 1, '5': 4, '10': 'handle'},
    {'1': 'result_code', '3': 2, '4': 1, '5': 5, '10': 'resultCode'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VLMLoadResolvedArtifactsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMLoadResolvedArtifactsResponseDescriptor = $convert.base64Decode(
    'CiBWTE1Mb2FkUmVzb2x2ZWRBcnRpZmFjdHNSZXNwb25zZRIWCgZoYW5kbGUYASABKARSBmhhbm'
    'RsZRIfCgtyZXN1bHRfY29kZRgCIAEoBVIKcmVzdWx0Q29kZRIoCg1lcnJvcl9tZXNzYWdlGAMg'
    'ASgJSABSDGVycm9yTWVzc2FnZYgBAUIQCg5fZXJyb3JfbWVzc2FnZQ==');

const $core.Map<$core.String, $core.dynamic> VLMServiceBase$json = {
  '1': 'VLM',
  '2': [
    {'1': 'Generate', '2': '.runanywhere.v1.VLMGenerationRequest', '3': '.runanywhere.v1.VLMResult'},
    {'1': 'Stream', '2': '.runanywhere.v1.VLMGenerationRequest', '3': '.runanywhere.v1.VLMStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use vLMServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> VLMServiceBase$messageJson = {
  '.runanywhere.v1.VLMGenerationRequest': VLMGenerationRequest$json,
  '.runanywhere.v1.VLMImage': VLMImage$json,
  '.runanywhere.v1.VLMImage.MetadataEntry': VLMImage_MetadataEntry$json,
  '.runanywhere.v1.VLMGenerationOptions': VLMGenerationOptions$json,
  '.runanywhere.v1.VLMChatTemplate': VLMChatTemplate$json,
  '.runanywhere.v1.VLMGenerationRequest.MetadataEntry': VLMGenerationRequest_MetadataEntry$json,
  '.runanywhere.v1.VLMResult': VLMResult$json,
  '.runanywhere.v1.VLMStreamEvent': VLMStreamEvent$json,
};

/// Descriptor for `VLM`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List vLMServiceDescriptor = $convert.base64Decode(
    'CgNWTE0SSwoIR2VuZXJhdGUSJC5ydW5hbnl3aGVyZS52MS5WTE1HZW5lcmF0aW9uUmVxdWVzdB'
    'oZLnJ1bmFueXdoZXJlLnYxLlZMTVJlc3VsdBJQCgZTdHJlYW0SJC5ydW5hbnl3aGVyZS52MS5W'
    'TE1HZW5lcmF0aW9uUmVxdWVzdBoeLnJ1bmFueXdoZXJlLnYxLlZMTVN0cmVhbUV2ZW50MAE=');

