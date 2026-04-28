///
//  Generated code. Do not modify.
//  source: diffusion_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use diffusionModeDescriptor instead')
const DiffusionMode$json = const {
  '1': 'DiffusionMode',
  '2': const [
    const {'1': 'DIFFUSION_MODE_UNSPECIFIED', '2': 0},
    const {'1': 'DIFFUSION_MODE_TEXT_TO_IMAGE', '2': 1},
    const {'1': 'DIFFUSION_MODE_IMAGE_TO_IMAGE', '2': 2},
    const {'1': 'DIFFUSION_MODE_INPAINTING', '2': 3},
  ],
};

/// Descriptor for `DiffusionMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionModeDescriptor = $convert.base64Decode('Cg1EaWZmdXNpb25Nb2RlEh4KGkRJRkZVU0lPTl9NT0RFX1VOU1BFQ0lGSUVEEAASIAocRElGRlVTSU9OX01PREVfVEVYVF9UT19JTUFHRRABEiEKHURJRkZVU0lPTl9NT0RFX0lNQUdFX1RPX0lNQUdFEAISHQoZRElGRlVTSU9OX01PREVfSU5QQUlOVElORxAD');
@$core.Deprecated('Use diffusionSchedulerDescriptor instead')
const DiffusionScheduler$json = const {
  '1': 'DiffusionScheduler',
  '2': const [
    const {'1': 'DIFFUSION_SCHEDULER_UNSPECIFIED', '2': 0},
    const {'1': 'DIFFUSION_SCHEDULER_DPMPP_2M', '2': 1},
    const {'1': 'DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS', '2': 2},
    const {'1': 'DIFFUSION_SCHEDULER_DDIM', '2': 3},
    const {'1': 'DIFFUSION_SCHEDULER_DDPM', '2': 4},
    const {'1': 'DIFFUSION_SCHEDULER_EULER', '2': 5},
    const {'1': 'DIFFUSION_SCHEDULER_EULER_A', '2': 6},
    const {'1': 'DIFFUSION_SCHEDULER_PNDM', '2': 7},
    const {'1': 'DIFFUSION_SCHEDULER_LMS', '2': 8},
    const {'1': 'DIFFUSION_SCHEDULER_LCM', '2': 9},
  ],
};

/// Descriptor for `DiffusionScheduler`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionSchedulerDescriptor = $convert.base64Decode('ChJEaWZmdXNpb25TY2hlZHVsZXISIwofRElGRlVTSU9OX1NDSEVEVUxFUl9VTlNQRUNJRklFRBAAEiAKHERJRkZVU0lPTl9TQ0hFRFVMRVJfRFBNUFBfMk0QARInCiNESUZGVVNJT05fU0NIRURVTEVSX0RQTVBQXzJNX0tBUlJBUxACEhwKGERJRkZVU0lPTl9TQ0hFRFVMRVJfRERJTRADEhwKGERJRkZVU0lPTl9TQ0hFRFVMRVJfRERQTRAEEh0KGURJRkZVU0lPTl9TQ0hFRFVMRVJfRVVMRVIQBRIfChtESUZGVVNJT05fU0NIRURVTEVSX0VVTEVSX0EQBhIcChhESUZGVVNJT05fU0NIRURVTEVSX1BORE0QBxIbChdESUZGVVNJT05fU0NIRURVTEVSX0xNUxAIEhsKF0RJRkZVU0lPTl9TQ0hFRFVMRVJfTENNEAk=');
@$core.Deprecated('Use diffusionModelVariantDescriptor instead')
const DiffusionModelVariant$json = const {
  '1': 'DiffusionModelVariant',
  '2': const [
    const {'1': 'DIFFUSION_MODEL_VARIANT_UNSPECIFIED', '2': 0},
    const {'1': 'DIFFUSION_MODEL_VARIANT_SD_1_5', '2': 1},
    const {'1': 'DIFFUSION_MODEL_VARIANT_SD_2_1', '2': 2},
    const {'1': 'DIFFUSION_MODEL_VARIANT_SDXL', '2': 3},
    const {'1': 'DIFFUSION_MODEL_VARIANT_SDXL_TURBO', '2': 4},
    const {'1': 'DIFFUSION_MODEL_VARIANT_SDXS', '2': 5},
    const {'1': 'DIFFUSION_MODEL_VARIANT_LCM', '2': 6},
  ],
};

/// Descriptor for `DiffusionModelVariant`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionModelVariantDescriptor = $convert.base64Decode('ChVEaWZmdXNpb25Nb2RlbFZhcmlhbnQSJwojRElGRlVTSU9OX01PREVMX1ZBUklBTlRfVU5TUEVDSUZJRUQQABIiCh5ESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9TRF8xXzUQARIiCh5ESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9TRF8yXzEQAhIgChxESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9TRFhMEAMSJgoiRElGRlVTSU9OX01PREVMX1ZBUklBTlRfU0RYTF9UVVJCTxAEEiAKHERJRkZVU0lPTl9NT0RFTF9WQVJJQU5UX1NEWFMQBRIfChtESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9MQ00QBg==');
@$core.Deprecated('Use diffusionTokenizerSourceKindDescriptor instead')
const DiffusionTokenizerSourceKind$json = const {
  '1': 'DiffusionTokenizerSourceKind',
  '2': const [
    const {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15', '2': 1},
    const {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2', '2': 2},
    const {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL', '2': 3},
    const {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM', '2': 4},
  ],
};

/// Descriptor for `DiffusionTokenizerSourceKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionTokenizerSourceKindDescriptor = $convert.base64Decode('ChxEaWZmdXNpb25Ub2tlbml6ZXJTb3VyY2VLaW5kEi8KK0RJRkZVU0lPTl9UT0tFTklaRVJfU09VUkNFX0tJTkRfVU5TUEVDSUZJRUQQABIwCixESUZGVVNJT05fVE9LRU5JWkVSX1NPVVJDRV9LSU5EX0JVTkRMRURfU0QxNRABEi8KK0RJRkZVU0lPTl9UT0tFTklaRVJfU09VUkNFX0tJTkRfQlVORExFRF9TRDIQAhIwCixESUZGVVNJT05fVE9LRU5JWkVSX1NPVVJDRV9LSU5EX0JVTkRMRURfU0RYTBADEioKJkRJRkZVU0lPTl9UT0tFTklaRVJfU09VUkNFX0tJTkRfQ1VTVE9NEAQ=');
@$core.Deprecated('Use diffusionTokenizerSourceDescriptor instead')
const DiffusionTokenizerSource$json = const {
  '1': 'DiffusionTokenizerSource',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionTokenizerSourceKind', '10': 'kind'},
    const {'1': 'custom_path', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'customPath', '17': true},
  ],
  '8': const [
    const {'1': '_custom_path'},
  ],
};

/// Descriptor for `DiffusionTokenizerSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionTokenizerSourceDescriptor = $convert.base64Decode('ChhEaWZmdXNpb25Ub2tlbml6ZXJTb3VyY2USQAoEa2luZBgBIAEoDjIsLnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvblRva2VuaXplclNvdXJjZUtpbmRSBGtpbmQSJAoLY3VzdG9tX3BhdGgYAiABKAlIAFIKY3VzdG9tUGF0aIgBAUIOCgxfY3VzdG9tX3BhdGg=');
@$core.Deprecated('Use diffusionConfigurationDescriptor instead')
const DiffusionConfiguration$json = const {
  '1': 'DiffusionConfiguration',
  '2': const [
    const {'1': 'model_variant', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionModelVariant', '10': 'modelVariant'},
    const {'1': 'tokenizer_source', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionTokenizerSource', '10': 'tokenizerSource'},
    const {'1': 'enable_safety_checker', '3': 3, '4': 1, '5': 8, '10': 'enableSafetyChecker'},
    const {'1': 'max_memory_mb', '3': 4, '4': 1, '5': 5, '10': 'maxMemoryMb'},
  ],
};

/// Descriptor for `DiffusionConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionConfigurationDescriptor = $convert.base64Decode('ChZEaWZmdXNpb25Db25maWd1cmF0aW9uEkoKDW1vZGVsX3ZhcmlhbnQYASABKA4yJS5ydW5hbnl3aGVyZS52MS5EaWZmdXNpb25Nb2RlbFZhcmlhbnRSDG1vZGVsVmFyaWFudBJTChB0b2tlbml6ZXJfc291cmNlGAIgASgLMigucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uVG9rZW5pemVyU291cmNlUg90b2tlbml6ZXJTb3VyY2USMgoVZW5hYmxlX3NhZmV0eV9jaGVja2VyGAMgASgIUhNlbmFibGVTYWZldHlDaGVja2VyEiIKDW1heF9tZW1vcnlfbWIYBCABKAVSC21heE1lbW9yeU1i');
@$core.Deprecated('Use diffusionGenerationOptionsDescriptor instead')
const DiffusionGenerationOptions$json = const {
  '1': 'DiffusionGenerationOptions',
  '2': const [
    const {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    const {'1': 'negative_prompt', '3': 2, '4': 1, '5': 9, '10': 'negativePrompt'},
    const {'1': 'width', '3': 3, '4': 1, '5': 5, '10': 'width'},
    const {'1': 'height', '3': 4, '4': 1, '5': 5, '10': 'height'},
    const {'1': 'num_inference_steps', '3': 5, '4': 1, '5': 5, '10': 'numInferenceSteps'},
    const {'1': 'guidance_scale', '3': 6, '4': 1, '5': 2, '10': 'guidanceScale'},
    const {'1': 'seed', '3': 7, '4': 1, '5': 3, '10': 'seed'},
    const {'1': 'scheduler', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionScheduler', '10': 'scheduler'},
    const {'1': 'mode', '3': 9, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionMode', '10': 'mode'},
  ],
};

/// Descriptor for `DiffusionGenerationOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionGenerationOptionsDescriptor = $convert.base64Decode('ChpEaWZmdXNpb25HZW5lcmF0aW9uT3B0aW9ucxIWCgZwcm9tcHQYASABKAlSBnByb21wdBInCg9uZWdhdGl2ZV9wcm9tcHQYAiABKAlSDm5lZ2F0aXZlUHJvbXB0EhQKBXdpZHRoGAMgASgFUgV3aWR0aBIWCgZoZWlnaHQYBCABKAVSBmhlaWdodBIuChNudW1faW5mZXJlbmNlX3N0ZXBzGAUgASgFUhFudW1JbmZlcmVuY2VTdGVwcxIlCg5ndWlkYW5jZV9zY2FsZRgGIAEoAlINZ3VpZGFuY2VTY2FsZRISCgRzZWVkGAcgASgDUgRzZWVkEkAKCXNjaGVkdWxlchgIIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvblNjaGVkdWxlclIJc2NoZWR1bGVyEjEKBG1vZGUYCSABKA4yHS5ydW5hbnl3aGVyZS52MS5EaWZmdXNpb25Nb2RlUgRtb2Rl');
@$core.Deprecated('Use diffusionProgressDescriptor instead')
const DiffusionProgress$json = const {
  '1': 'DiffusionProgress',
  '2': const [
    const {'1': 'progress_percent', '3': 1, '4': 1, '5': 2, '10': 'progressPercent'},
    const {'1': 'current_step', '3': 2, '4': 1, '5': 5, '10': 'currentStep'},
    const {'1': 'total_steps', '3': 3, '4': 1, '5': 5, '10': 'totalSteps'},
    const {'1': 'stage', '3': 4, '4': 1, '5': 9, '10': 'stage'},
    const {'1': 'intermediate_image_data', '3': 5, '4': 1, '5': 12, '9': 0, '10': 'intermediateImageData', '17': true},
  ],
  '8': const [
    const {'1': '_intermediate_image_data'},
  ],
};

/// Descriptor for `DiffusionProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionProgressDescriptor = $convert.base64Decode('ChFEaWZmdXNpb25Qcm9ncmVzcxIpChBwcm9ncmVzc19wZXJjZW50GAEgASgCUg9wcm9ncmVzc1BlcmNlbnQSIQoMY3VycmVudF9zdGVwGAIgASgFUgtjdXJyZW50U3RlcBIfCgt0b3RhbF9zdGVwcxgDIAEoBVIKdG90YWxTdGVwcxIUCgVzdGFnZRgEIAEoCVIFc3RhZ2USOwoXaW50ZXJtZWRpYXRlX2ltYWdlX2RhdGEYBSABKAxIAFIVaW50ZXJtZWRpYXRlSW1hZ2VEYXRhiAEBQhoKGF9pbnRlcm1lZGlhdGVfaW1hZ2VfZGF0YQ==');
@$core.Deprecated('Use diffusionResultDescriptor instead')
const DiffusionResult$json = const {
  '1': 'DiffusionResult',
  '2': const [
    const {'1': 'image_data', '3': 1, '4': 1, '5': 12, '10': 'imageData'},
    const {'1': 'width', '3': 2, '4': 1, '5': 5, '10': 'width'},
    const {'1': 'height', '3': 3, '4': 1, '5': 5, '10': 'height'},
    const {'1': 'seed_used', '3': 4, '4': 1, '5': 3, '10': 'seedUsed'},
    const {'1': 'total_time_ms', '3': 5, '4': 1, '5': 3, '10': 'totalTimeMs'},
    const {'1': 'safety_flag', '3': 6, '4': 1, '5': 8, '10': 'safetyFlag'},
    const {'1': 'used_scheduler', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionScheduler', '10': 'usedScheduler'},
  ],
};

/// Descriptor for `DiffusionResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionResultDescriptor = $convert.base64Decode('Cg9EaWZmdXNpb25SZXN1bHQSHQoKaW1hZ2VfZGF0YRgBIAEoDFIJaW1hZ2VEYXRhEhQKBXdpZHRoGAIgASgFUgV3aWR0aBIWCgZoZWlnaHQYAyABKAVSBmhlaWdodBIbCglzZWVkX3VzZWQYBCABKANSCHNlZWRVc2VkEiIKDXRvdGFsX3RpbWVfbXMYBSABKANSC3RvdGFsVGltZU1zEh8KC3NhZmV0eV9mbGFnGAYgASgIUgpzYWZldHlGbGFnEkkKDnVzZWRfc2NoZWR1bGVyGAcgASgOMiIucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uU2NoZWR1bGVyUg11c2VkU2NoZWR1bGVy');
@$core.Deprecated('Use diffusionCapabilitiesDescriptor instead')
const DiffusionCapabilities$json = const {
  '1': 'DiffusionCapabilities',
  '2': const [
    const {'1': 'supported_variants', '3': 1, '4': 3, '5': 14, '6': '.runanywhere.v1.DiffusionModelVariant', '10': 'supportedVariants'},
    const {'1': 'supported_schedulers', '3': 2, '4': 3, '5': 14, '6': '.runanywhere.v1.DiffusionScheduler', '10': 'supportedSchedulers'},
    const {'1': 'max_resolution_px', '3': 3, '4': 1, '5': 5, '10': 'maxResolutionPx'},
  ],
};

/// Descriptor for `DiffusionCapabilities`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionCapabilitiesDescriptor = $convert.base64Decode('ChVEaWZmdXNpb25DYXBhYmlsaXRpZXMSVAoSc3VwcG9ydGVkX3ZhcmlhbnRzGAEgAygOMiUucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uTW9kZWxWYXJpYW50UhFzdXBwb3J0ZWRWYXJpYW50cxJVChRzdXBwb3J0ZWRfc2NoZWR1bGVycxgCIAMoDjIiLnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvblNjaGVkdWxlclITc3VwcG9ydGVkU2NoZWR1bGVycxIqChFtYXhfcmVzb2x1dGlvbl9weBgDIAEoBVIPbWF4UmVzb2x1dGlvblB4');
