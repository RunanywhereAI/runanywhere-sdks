///
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use vLMImageFormatDescriptor instead')
const VLMImageFormat$json = const {
  '1': 'VLMImageFormat',
  '2': const [
    const {'1': 'VLM_IMAGE_FORMAT_UNSPECIFIED', '2': 0},
    const {'1': 'VLM_IMAGE_FORMAT_JPEG', '2': 1},
    const {'1': 'VLM_IMAGE_FORMAT_PNG', '2': 2},
    const {'1': 'VLM_IMAGE_FORMAT_WEBP', '2': 3},
    const {'1': 'VLM_IMAGE_FORMAT_RAW_RGB', '2': 4},
    const {'1': 'VLM_IMAGE_FORMAT_RAW_RGBA', '2': 5},
    const {'1': 'VLM_IMAGE_FORMAT_BASE64', '2': 6},
    const {'1': 'VLM_IMAGE_FORMAT_FILE_PATH', '2': 7},
  ],
};

/// Descriptor for `VLMImageFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vLMImageFormatDescriptor = $convert.base64Decode('Cg5WTE1JbWFnZUZvcm1hdBIgChxWTE1fSU1BR0VfRk9STUFUX1VOU1BFQ0lGSUVEEAASGQoVVkxNX0lNQUdFX0ZPUk1BVF9KUEVHEAESGAoUVkxNX0lNQUdFX0ZPUk1BVF9QTkcQAhIZChVWTE1fSU1BR0VfRk9STUFUX1dFQlAQAxIcChhWTE1fSU1BR0VfRk9STUFUX1JBV19SR0IQBBIdChlWTE1fSU1BR0VfRk9STUFUX1JBV19SR0JBEAUSGwoXVkxNX0lNQUdFX0ZPUk1BVF9CQVNFNjQQBhIeChpWTE1fSU1BR0VfRk9STUFUX0ZJTEVfUEFUSBAH');
@$core.Deprecated('Use vLMErrorCodeDescriptor instead')
const VLMErrorCode$json = const {
  '1': 'VLMErrorCode',
  '2': const [
    const {'1': 'VLM_ERROR_CODE_UNSPECIFIED', '2': 0},
    const {'1': 'VLM_ERROR_CODE_INVALID_IMAGE', '2': 1},
    const {'1': 'VLM_ERROR_CODE_MODEL_NOT_LOADED', '2': 2},
    const {'1': 'VLM_ERROR_CODE_UNSUPPORTED_FORMAT', '2': 3},
    const {'1': 'VLM_ERROR_CODE_IMAGE_TOO_LARGE', '2': 4},
  ],
};

/// Descriptor for `VLMErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vLMErrorCodeDescriptor = $convert.base64Decode('CgxWTE1FcnJvckNvZGUSHgoaVkxNX0VSUk9SX0NPREVfVU5TUEVDSUZJRUQQABIgChxWTE1fRVJST1JfQ09ERV9JTlZBTElEX0lNQUdFEAESIwofVkxNX0VSUk9SX0NPREVfTU9ERUxfTk9UX0xPQURFRBACEiUKIVZMTV9FUlJPUl9DT0RFX1VOU1VQUE9SVEVEX0ZPUk1BVBADEiIKHlZMTV9FUlJPUl9DT0RFX0lNQUdFX1RPT19MQVJHRRAE');
@$core.Deprecated('Use vLMImageDescriptor instead')
const VLMImage$json = const {
  '1': 'VLMImage',
  '2': const [
    const {'1': 'file_path', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'filePath'},
    const {'1': 'encoded', '3': 2, '4': 1, '5': 12, '9': 0, '10': 'encoded'},
    const {'1': 'raw_rgb', '3': 3, '4': 1, '5': 12, '9': 0, '10': 'rawRgb'},
    const {'1': 'base64', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'base64'},
    const {'1': 'width', '3': 5, '4': 1, '5': 5, '10': 'width'},
    const {'1': 'height', '3': 6, '4': 1, '5': 5, '10': 'height'},
    const {'1': 'format', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.VLMImageFormat', '10': 'format'},
  ],
  '8': const [
    const {'1': 'source'},
  ],
};

/// Descriptor for `VLMImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMImageDescriptor = $convert.base64Decode('CghWTE1JbWFnZRIdCglmaWxlX3BhdGgYASABKAlIAFIIZmlsZVBhdGgSGgoHZW5jb2RlZBgCIAEoDEgAUgdlbmNvZGVkEhkKB3Jhd19yZ2IYAyABKAxIAFIGcmF3UmdiEhgKBmJhc2U2NBgEIAEoCUgAUgZiYXNlNjQSFAoFd2lkdGgYBSABKAVSBXdpZHRoEhYKBmhlaWdodBgGIAEoBVIGaGVpZ2h0EjYKBmZvcm1hdBgHIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlZMTUltYWdlRm9ybWF0UgZmb3JtYXRCCAoGc291cmNl');
@$core.Deprecated('Use vLMConfigurationDescriptor instead')
const VLMConfiguration$json = const {
  '1': 'VLMConfiguration',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'max_image_size_px', '3': 2, '4': 1, '5': 5, '10': 'maxImageSizePx'},
    const {'1': 'max_tokens', '3': 3, '4': 1, '5': 5, '10': 'maxTokens'},
  ],
};

/// Descriptor for `VLMConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMConfigurationDescriptor = $convert.base64Decode('ChBWTE1Db25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEikKEW1heF9pbWFnZV9zaXplX3B4GAIgASgFUg5tYXhJbWFnZVNpemVQeBIdCgptYXhfdG9rZW5zGAMgASgFUgltYXhUb2tlbnM=');
@$core.Deprecated('Use vLMGenerationOptionsDescriptor instead')
const VLMGenerationOptions$json = const {
  '1': 'VLMGenerationOptions',
  '2': const [
    const {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    const {'1': 'max_tokens', '3': 2, '4': 1, '5': 5, '10': 'maxTokens'},
    const {'1': 'temperature', '3': 3, '4': 1, '5': 2, '10': 'temperature'},
    const {'1': 'top_p', '3': 4, '4': 1, '5': 2, '10': 'topP'},
    const {'1': 'top_k', '3': 5, '4': 1, '5': 5, '10': 'topK'},
  ],
};

/// Descriptor for `VLMGenerationOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMGenerationOptionsDescriptor = $convert.base64Decode('ChRWTE1HZW5lcmF0aW9uT3B0aW9ucxIWCgZwcm9tcHQYASABKAlSBnByb21wdBIdCgptYXhfdG9rZW5zGAIgASgFUgltYXhUb2tlbnMSIAoLdGVtcGVyYXR1cmUYAyABKAJSC3RlbXBlcmF0dXJlEhMKBXRvcF9wGAQgASgCUgR0b3BQEhMKBXRvcF9rGAUgASgFUgR0b3BL');
@$core.Deprecated('Use vLMResultDescriptor instead')
const VLMResult$json = const {
  '1': 'VLMResult',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'prompt_tokens', '3': 2, '4': 1, '5': 5, '10': 'promptTokens'},
    const {'1': 'completion_tokens', '3': 3, '4': 1, '5': 5, '10': 'completionTokens'},
    const {'1': 'total_tokens', '3': 4, '4': 1, '5': 3, '10': 'totalTokens'},
    const {'1': 'processing_time_ms', '3': 5, '4': 1, '5': 3, '10': 'processingTimeMs'},
    const {'1': 'tokens_per_second', '3': 6, '4': 1, '5': 2, '10': 'tokensPerSecond'},
  ],
};

/// Descriptor for `VLMResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vLMResultDescriptor = $convert.base64Decode('CglWTE1SZXN1bHQSEgoEdGV4dBgBIAEoCVIEdGV4dBIjCg1wcm9tcHRfdG9rZW5zGAIgASgFUgxwcm9tcHRUb2tlbnMSKwoRY29tcGxldGlvbl90b2tlbnMYAyABKAVSEGNvbXBsZXRpb25Ub2tlbnMSIQoMdG90YWxfdG9rZW5zGAQgASgDUgt0b3RhbFRva2VucxIsChJwcm9jZXNzaW5nX3RpbWVfbXMYBSABKANSEHByb2Nlc3NpbmdUaW1lTXMSKgoRdG9rZW5zX3Blcl9zZWNvbmQYBiABKAJSD3Rva2Vuc1BlclNlY29uZA==');
