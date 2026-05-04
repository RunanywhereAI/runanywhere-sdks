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

@$core.Deprecated('Use vLMErrorCodeDescriptor instead')
const VLMErrorCode$json = {
  '1': 'VLMErrorCode',
  '2': [
    {'1': 'VLM_ERROR_CODE_UNSPECIFIED', '2': 0},
    {'1': 'VLM_ERROR_CODE_INVALID_IMAGE', '2': 1},
    {'1': 'VLM_ERROR_CODE_MODEL_NOT_LOADED', '2': 2},
    {'1': 'VLM_ERROR_CODE_UNSUPPORTED_FORMAT', '2': 3},
    {'1': 'VLM_ERROR_CODE_IMAGE_TOO_LARGE', '2': 4},
    {'1': 'VLM_ERROR_CODE_NOT_INITIALIZED', '2': 5},
    {'1': 'VLM_ERROR_CODE_MODEL_LOAD_FAILED', '2': 6},
    {'1': 'VLM_ERROR_CODE_PROCESSING_FAILED', '2': 7},
    {'1': 'VLM_ERROR_CODE_CANCELLED', '2': 8},
  ],
};

/// Descriptor for `VLMErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vLMErrorCodeDescriptor = $convert.base64Decode(
    'CgxWTE1FcnJvckNvZGUSHgoaVkxNX0VSUk9SX0NPREVfVU5TUEVDSUZJRUQQABIgChxWTE1fRV'
    'JST1JfQ09ERV9JTlZBTElEX0lNQUdFEAESIwofVkxNX0VSUk9SX0NPREVfTU9ERUxfTk9UX0xP'
    'QURFRBACEiUKIVZMTV9FUlJPUl9DT0RFX1VOU1VQUE9SVEVEX0ZPUk1BVBADEiIKHlZMTV9FUl'
    'JPUl9DT0RFX0lNQUdFX1RPT19MQVJHRRAEEiIKHlZMTV9FUlJPUl9DT0RFX05PVF9JTklUSUFM'
    'SVpFRBAFEiQKIFZMTV9FUlJPUl9DT0RFX01PREVMX0xPQURfRkFJTEVEEAYSJAogVkxNX0VSUk'
    '9SX0NPREVfUFJPQ0VTU0lOR19GQUlMRUQQBxIcChhWTE1fRVJST1JfQ09ERV9DQU5DRUxMRUQQ'
    'CA==');

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
  ],
  '8': [
    {'1': 'source'},
  ],
};

/// Descriptor for `VLMImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMImageDescriptor = $convert.base64Decode(
    'CghWTE1JbWFnZRIdCglmaWxlX3BhdGgYASABKAlIAFIIZmlsZVBhdGgSGgoHZW5jb2RlZBgCIA'
    'EoDEgAUgdlbmNvZGVkEhkKB3Jhd19yZ2IYAyABKAxIAFIGcmF3UmdiEhgKBmJhc2U2NBgEIAEo'
    'CUgAUgZiYXNlNjQSFAoFd2lkdGgYBSABKAVSBXdpZHRoEhYKBmhlaWdodBgGIAEoBVIGaGVpZ2'
    'h0EjYKBmZvcm1hdBgHIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlZMTUltYWdlRm9ybWF0UgZmb3Jt'
    'YXRCCAoGc291cmNl');

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
    'KAlIAlITaW1hZ2VNYXJrZXJPdmVycmlkZYgBAUIQCg5fc3lzdGVtX3Byb21wdEIXChVfY3VzdG'
    '9tX2NoYXRfdGVtcGxhdGVCGAoWX2ltYWdlX21hcmtlcl9vdmVycmlkZQ==');

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
  ],
  '8': [
    {'1': '_hardware_used'},
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
    'NlZBgKIAEoCUgAUgxoYXJkd2FyZVVzZWSIAQFCEAoOX2hhcmR3YXJlX3VzZWQ=');

