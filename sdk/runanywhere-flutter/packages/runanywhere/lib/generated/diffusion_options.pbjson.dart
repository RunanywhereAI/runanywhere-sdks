//
//  Generated code. Do not modify.
//  source: diffusion_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use diffusionModeDescriptor instead')
const DiffusionMode$json = {
  '1': 'DiffusionMode',
  '2': [
    {'1': 'DIFFUSION_MODE_UNSPECIFIED', '2': 0},
    {'1': 'DIFFUSION_MODE_TEXT_TO_IMAGE', '2': 1},
    {'1': 'DIFFUSION_MODE_IMAGE_TO_IMAGE', '2': 2},
    {'1': 'DIFFUSION_MODE_INPAINTING', '2': 3},
  ],
};

/// Descriptor for `DiffusionMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionModeDescriptor = $convert.base64Decode(
    'Cg1EaWZmdXNpb25Nb2RlEh4KGkRJRkZVU0lPTl9NT0RFX1VOU1BFQ0lGSUVEEAASIAocRElGRl'
    'VTSU9OX01PREVfVEVYVF9UT19JTUFHRRABEiEKHURJRkZVU0lPTl9NT0RFX0lNQUdFX1RPX0lN'
    'QUdFEAISHQoZRElGRlVTSU9OX01PREVfSU5QQUlOVElORxAD');

@$core.Deprecated('Use diffusionSchedulerDescriptor instead')
const DiffusionScheduler$json = {
  '1': 'DiffusionScheduler',
  '2': [
    {'1': 'DIFFUSION_SCHEDULER_UNSPECIFIED', '2': 0},
    {'1': 'DIFFUSION_SCHEDULER_DPMPP_2M', '2': 1},
    {'1': 'DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS', '2': 2},
    {'1': 'DIFFUSION_SCHEDULER_DDIM', '2': 3},
    {'1': 'DIFFUSION_SCHEDULER_DDPM', '2': 4},
    {'1': 'DIFFUSION_SCHEDULER_EULER', '2': 5},
    {'1': 'DIFFUSION_SCHEDULER_EULER_A', '2': 6},
    {'1': 'DIFFUSION_SCHEDULER_PNDM', '2': 7},
    {'1': 'DIFFUSION_SCHEDULER_LMS', '2': 8},
    {'1': 'DIFFUSION_SCHEDULER_LCM', '2': 9},
    {'1': 'DIFFUSION_SCHEDULER_DPMPP_2M_SDE', '2': 10},
  ],
};

/// Descriptor for `DiffusionScheduler`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionSchedulerDescriptor = $convert.base64Decode(
    'ChJEaWZmdXNpb25TY2hlZHVsZXISIwofRElGRlVTSU9OX1NDSEVEVUxFUl9VTlNQRUNJRklFRB'
    'AAEiAKHERJRkZVU0lPTl9TQ0hFRFVMRVJfRFBNUFBfMk0QARInCiNESUZGVVNJT05fU0NIRURV'
    'TEVSX0RQTVBQXzJNX0tBUlJBUxACEhwKGERJRkZVU0lPTl9TQ0hFRFVMRVJfRERJTRADEhwKGE'
    'RJRkZVU0lPTl9TQ0hFRFVMRVJfRERQTRAEEh0KGURJRkZVU0lPTl9TQ0hFRFVMRVJfRVVMRVIQ'
    'BRIfChtESUZGVVNJT05fU0NIRURVTEVSX0VVTEVSX0EQBhIcChhESUZGVVNJT05fU0NIRURVTE'
    'VSX1BORE0QBxIbChdESUZGVVNJT05fU0NIRURVTEVSX0xNUxAIEhsKF0RJRkZVU0lPTl9TQ0hF'
    'RFVMRVJfTENNEAkSJAogRElGRlVTSU9OX1NDSEVEVUxFUl9EUE1QUF8yTV9TREUQCg==');

@$core.Deprecated('Use diffusionModelVariantDescriptor instead')
const DiffusionModelVariant$json = {
  '1': 'DiffusionModelVariant',
  '2': [
    {'1': 'DIFFUSION_MODEL_VARIANT_UNSPECIFIED', '2': 0},
    {'1': 'DIFFUSION_MODEL_VARIANT_SD_1_5', '2': 1},
    {'1': 'DIFFUSION_MODEL_VARIANT_SD_2_1', '2': 2},
    {'1': 'DIFFUSION_MODEL_VARIANT_SDXL', '2': 3},
    {'1': 'DIFFUSION_MODEL_VARIANT_SDXL_TURBO', '2': 4},
    {'1': 'DIFFUSION_MODEL_VARIANT_SDXS', '2': 5},
    {'1': 'DIFFUSION_MODEL_VARIANT_LCM', '2': 6},
  ],
};

/// Descriptor for `DiffusionModelVariant`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionModelVariantDescriptor = $convert.base64Decode(
    'ChVEaWZmdXNpb25Nb2RlbFZhcmlhbnQSJwojRElGRlVTSU9OX01PREVMX1ZBUklBTlRfVU5TUE'
    'VDSUZJRUQQABIiCh5ESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9TRF8xXzUQARIiCh5ESUZGVVNJ'
    'T05fTU9ERUxfVkFSSUFOVF9TRF8yXzEQAhIgChxESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9TRF'
    'hMEAMSJgoiRElGRlVTSU9OX01PREVMX1ZBUklBTlRfU0RYTF9UVVJCTxAEEiAKHERJRkZVU0lP'
    'Tl9NT0RFTF9WQVJJQU5UX1NEWFMQBRIfChtESUZGVVNJT05fTU9ERUxfVkFSSUFOVF9MQ00QBg'
    '==');

@$core.Deprecated('Use diffusionTokenizerSourceKindDescriptor instead')
const DiffusionTokenizerSourceKind$json = {
  '1': 'DiffusionTokenizerSourceKind',
  '2': [
    {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED', '2': 0},
    {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15', '2': 1},
    {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2', '2': 2},
    {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL', '2': 3},
    {'1': 'DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM', '2': 4},
  ],
};

/// Descriptor for `DiffusionTokenizerSourceKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionTokenizerSourceKindDescriptor = $convert.base64Decode(
    'ChxEaWZmdXNpb25Ub2tlbml6ZXJTb3VyY2VLaW5kEi8KK0RJRkZVU0lPTl9UT0tFTklaRVJfU0'
    '9VUkNFX0tJTkRfVU5TUEVDSUZJRUQQABIwCixESUZGVVNJT05fVE9LRU5JWkVSX1NPVVJDRV9L'
    'SU5EX0JVTkRMRURfU0QxNRABEi8KK0RJRkZVU0lPTl9UT0tFTklaRVJfU09VUkNFX0tJTkRfQl'
    'VORExFRF9TRDIQAhIwCixESUZGVVNJT05fVE9LRU5JWkVSX1NPVVJDRV9LSU5EX0JVTkRMRURf'
    'U0RYTBADEioKJkRJRkZVU0lPTl9UT0tFTklaRVJfU09VUkNFX0tJTkRfQ1VTVE9NEAQ=');

@$core.Deprecated('Use diffusionStreamEventKindDescriptor instead')
const DiffusionStreamEventKind$json = {
  '1': 'DiffusionStreamEventKind',
  '2': [
    {'1': 'DIFFUSION_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'DIFFUSION_STREAM_EVENT_KIND_STARTED', '2': 1},
    {'1': 'DIFFUSION_STREAM_EVENT_KIND_PROGRESS', '2': 2},
    {'1': 'DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE', '2': 3},
    {'1': 'DIFFUSION_STREAM_EVENT_KIND_COMPLETED', '2': 4},
    {'1': 'DIFFUSION_STREAM_EVENT_KIND_ERROR', '2': 5},
  ],
};

/// Descriptor for `DiffusionStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List diffusionStreamEventKindDescriptor = $convert.base64Decode(
    'ChhEaWZmdXNpb25TdHJlYW1FdmVudEtpbmQSKwonRElGRlVTSU9OX1NUUkVBTV9FVkVOVF9LSU'
    '5EX1VOU1BFQ0lGSUVEEAASJwojRElGRlVTSU9OX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVJURUQQ'
    'ARIoCiRESUZGVVNJT05fU1RSRUFNX0VWRU5UX0tJTkRfUFJPR1JFU1MQAhIyCi5ESUZGVVNJT0'
    '5fU1RSRUFNX0VWRU5UX0tJTkRfSU5URVJNRURJQVRFX0lNQUdFEAMSKQolRElGRlVTSU9OX1NU'
    'UkVBTV9FVkVOVF9LSU5EX0NPTVBMRVRFRBAEEiUKIURJRkZVU0lPTl9TVFJFQU1fRVZFTlRfS0'
    'lORF9FUlJPUhAF');

@$core.Deprecated('Use diffusionTokenizerSourceDescriptor instead')
const DiffusionTokenizerSource$json = {
  '1': 'DiffusionTokenizerSource',
  '2': [
    {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionTokenizerSourceKind', '10': 'kind'},
    {'1': 'custom_path', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'customPath', '17': true},
    {'1': 'auto_download', '3': 3, '4': 1, '5': 8, '10': 'autoDownload'},
  ],
  '8': [
    {'1': '_custom_path'},
  ],
};

/// Descriptor for `DiffusionTokenizerSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionTokenizerSourceDescriptor = $convert.base64Decode(
    'ChhEaWZmdXNpb25Ub2tlbml6ZXJTb3VyY2USQAoEa2luZBgBIAEoDjIsLnJ1bmFueXdoZXJlLn'
    'YxLkRpZmZ1c2lvblRva2VuaXplclNvdXJjZUtpbmRSBGtpbmQSJAoLY3VzdG9tX3BhdGgYAiAB'
    'KAlIAFIKY3VzdG9tUGF0aIgBARIjCg1hdXRvX2Rvd25sb2FkGAMgASgIUgxhdXRvRG93bmxvYW'
    'RCDgoMX2N1c3RvbV9wYXRo');

@$core.Deprecated('Use diffusionConfigurationDescriptor instead')
const DiffusionConfiguration$json = {
  '1': 'DiffusionConfiguration',
  '2': [
    {'1': 'model_variant', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionModelVariant', '10': 'modelVariant'},
    {'1': 'tokenizer_source', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionTokenizerSource', '10': 'tokenizerSource'},
    {'1': 'enable_safety_checker', '3': 3, '4': 1, '5': 8, '10': 'enableSafetyChecker'},
    {'1': 'max_memory_mb', '3': 4, '4': 1, '5': 5, '10': 'maxMemoryMb'},
    {'1': 'model_id', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'modelId', '17': true},
    {'1': 'preferred_framework', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'preferredFramework', '17': true},
    {'1': 'reduce_memory', '3': 7, '4': 1, '5': 8, '10': 'reduceMemory'},
  ],
  '8': [
    {'1': '_model_id'},
    {'1': '_preferred_framework'},
  ],
};

/// Descriptor for `DiffusionConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionConfigurationDescriptor = $convert.base64Decode(
    'ChZEaWZmdXNpb25Db25maWd1cmF0aW9uEkoKDW1vZGVsX3ZhcmlhbnQYASABKA4yJS5ydW5hbn'
    'l3aGVyZS52MS5EaWZmdXNpb25Nb2RlbFZhcmlhbnRSDG1vZGVsVmFyaWFudBJTChB0b2tlbml6'
    'ZXJfc291cmNlGAIgASgLMigucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uVG9rZW5pemVyU291cm'
    'NlUg90b2tlbml6ZXJTb3VyY2USMgoVZW5hYmxlX3NhZmV0eV9jaGVja2VyGAMgASgIUhNlbmFi'
    'bGVTYWZldHlDaGVja2VyEiIKDW1heF9tZW1vcnlfbWIYBCABKAVSC21heE1lbW9yeU1iEh4KCG'
    '1vZGVsX2lkGAUgASgJSABSB21vZGVsSWSIAQESWAoTcHJlZmVycmVkX2ZyYW1ld29yaxgGIAEo'
    'DjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya0gBUhJwcmVmZXJyZWRGcmFtZX'
    'dvcmuIAQESIwoNcmVkdWNlX21lbW9yeRgHIAEoCFIMcmVkdWNlTWVtb3J5QgsKCV9tb2RlbF9p'
    'ZEIWChRfcHJlZmVycmVkX2ZyYW1ld29yaw==');

@$core.Deprecated('Use diffusionConfigDescriptor instead')
const DiffusionConfig$json = {
  '1': 'DiffusionConfig',
  '2': [
    {'1': 'model_path', '3': 1, '4': 1, '5': 9, '10': 'modelPath'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'model_name', '3': 3, '4': 1, '5': 9, '10': 'modelName'},
    {'1': 'configuration', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionConfiguration', '9': 0, '10': 'configuration', '17': true},
  ],
  '8': [
    {'1': '_configuration'},
  ],
};

/// Descriptor for `DiffusionConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionConfigDescriptor = $convert.base64Decode(
    'Cg9EaWZmdXNpb25Db25maWcSHQoKbW9kZWxfcGF0aBgBIAEoCVIJbW9kZWxQYXRoEhkKCG1vZG'
    'VsX2lkGAIgASgJUgdtb2RlbElkEh0KCm1vZGVsX25hbWUYAyABKAlSCW1vZGVsTmFtZRJRCg1j'
    'b25maWd1cmF0aW9uGAQgASgLMiYucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uQ29uZmlndXJhdG'
    'lvbkgAUg1jb25maWd1cmF0aW9uiAEBQhAKDl9jb25maWd1cmF0aW9u');

@$core.Deprecated('Use diffusionGenerationOptionsDescriptor instead')
const DiffusionGenerationOptions$json = {
  '1': 'DiffusionGenerationOptions',
  '2': [
    {'1': 'prompt', '3': 1, '4': 1, '5': 9, '10': 'prompt'},
    {'1': 'negative_prompt', '3': 2, '4': 1, '5': 9, '10': 'negativePrompt'},
    {'1': 'width', '3': 3, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 5, '10': 'height'},
    {'1': 'num_inference_steps', '3': 5, '4': 1, '5': 5, '10': 'numInferenceSteps'},
    {'1': 'guidance_scale', '3': 6, '4': 1, '5': 2, '10': 'guidanceScale'},
    {'1': 'seed', '3': 7, '4': 1, '5': 3, '10': 'seed'},
    {'1': 'scheduler', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionScheduler', '10': 'scheduler'},
    {'1': 'mode', '3': 9, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionMode', '10': 'mode'},
    {'1': 'input_image', '3': 10, '4': 1, '5': 12, '9': 0, '10': 'inputImage', '17': true},
    {'1': 'mask_image', '3': 11, '4': 1, '5': 12, '9': 1, '10': 'maskImage', '17': true},
    {'1': 'denoise_strength', '3': 12, '4': 1, '5': 2, '10': 'denoiseStrength'},
    {'1': 'report_intermediate_images', '3': 13, '4': 1, '5': 8, '10': 'reportIntermediateImages'},
    {'1': 'progress_stride', '3': 14, '4': 1, '5': 5, '10': 'progressStride'},
    {'1': 'input_image_width', '3': 15, '4': 1, '5': 5, '10': 'inputImageWidth'},
    {'1': 'input_image_height', '3': 16, '4': 1, '5': 5, '10': 'inputImageHeight'},
    {'1': 'input_image_media_type', '3': 17, '4': 1, '5': 9, '9': 2, '10': 'inputImageMediaType', '17': true},
    {'1': 'mask_image_media_type', '3': 18, '4': 1, '5': 9, '9': 3, '10': 'maskImageMediaType', '17': true},
    {'1': 'batch_size', '3': 19, '4': 1, '5': 5, '10': 'batchSize'},
    {'1': 'return_latents', '3': 20, '4': 1, '5': 8, '10': 'returnLatents'},
  ],
  '8': [
    {'1': '_input_image'},
    {'1': '_mask_image'},
    {'1': '_input_image_media_type'},
    {'1': '_mask_image_media_type'},
  ],
};

/// Descriptor for `DiffusionGenerationOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionGenerationOptionsDescriptor = $convert.base64Decode(
    'ChpEaWZmdXNpb25HZW5lcmF0aW9uT3B0aW9ucxIWCgZwcm9tcHQYASABKAlSBnByb21wdBInCg'
    '9uZWdhdGl2ZV9wcm9tcHQYAiABKAlSDm5lZ2F0aXZlUHJvbXB0EhQKBXdpZHRoGAMgASgFUgV3'
    'aWR0aBIWCgZoZWlnaHQYBCABKAVSBmhlaWdodBIuChNudW1faW5mZXJlbmNlX3N0ZXBzGAUgAS'
    'gFUhFudW1JbmZlcmVuY2VTdGVwcxIlCg5ndWlkYW5jZV9zY2FsZRgGIAEoAlINZ3VpZGFuY2VT'
    'Y2FsZRISCgRzZWVkGAcgASgDUgRzZWVkEkAKCXNjaGVkdWxlchgIIAEoDjIiLnJ1bmFueXdoZX'
    'JlLnYxLkRpZmZ1c2lvblNjaGVkdWxlclIJc2NoZWR1bGVyEjEKBG1vZGUYCSABKA4yHS5ydW5h'
    'bnl3aGVyZS52MS5EaWZmdXNpb25Nb2RlUgRtb2RlEiQKC2lucHV0X2ltYWdlGAogASgMSABSCm'
    'lucHV0SW1hZ2WIAQESIgoKbWFza19pbWFnZRgLIAEoDEgBUgltYXNrSW1hZ2WIAQESKQoQZGVu'
    'b2lzZV9zdHJlbmd0aBgMIAEoAlIPZGVub2lzZVN0cmVuZ3RoEjwKGnJlcG9ydF9pbnRlcm1lZG'
    'lhdGVfaW1hZ2VzGA0gASgIUhhyZXBvcnRJbnRlcm1lZGlhdGVJbWFnZXMSJwoPcHJvZ3Jlc3Nf'
    'c3RyaWRlGA4gASgFUg5wcm9ncmVzc1N0cmlkZRIqChFpbnB1dF9pbWFnZV93aWR0aBgPIAEoBV'
    'IPaW5wdXRJbWFnZVdpZHRoEiwKEmlucHV0X2ltYWdlX2hlaWdodBgQIAEoBVIQaW5wdXRJbWFn'
    'ZUhlaWdodBI4ChZpbnB1dF9pbWFnZV9tZWRpYV90eXBlGBEgASgJSAJSE2lucHV0SW1hZ2VNZW'
    'RpYVR5cGWIAQESNgoVbWFza19pbWFnZV9tZWRpYV90eXBlGBIgASgJSANSEm1hc2tJbWFnZU1l'
    'ZGlhVHlwZYgBARIdCgpiYXRjaF9zaXplGBMgASgFUgliYXRjaFNpemUSJQoOcmV0dXJuX2xhdG'
    'VudHMYFCABKAhSDXJldHVybkxhdGVudHNCDgoMX2lucHV0X2ltYWdlQg0KC19tYXNrX2ltYWdl'
    'QhkKF19pbnB1dF9pbWFnZV9tZWRpYV90eXBlQhgKFl9tYXNrX2ltYWdlX21lZGlhX3R5cGU=');

@$core.Deprecated('Use diffusionGenerationRequestDescriptor instead')
const DiffusionGenerationRequest$json = {
  '1': 'DiffusionGenerationRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'options', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionGenerationOptions', '9': 0, '10': 'options', '17': true},
    {'1': 'model_id', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'modelId', '17': true},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.DiffusionGenerationRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [DiffusionGenerationRequest_MetadataEntry$json],
  '8': [
    {'1': '_options'},
    {'1': '_model_id'},
  ],
};

@$core.Deprecated('Use diffusionGenerationRequestDescriptor instead')
const DiffusionGenerationRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `DiffusionGenerationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionGenerationRequestDescriptor = $convert.base64Decode(
    'ChpEaWZmdXNpb25HZW5lcmF0aW9uUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZX'
    'N0SWQSSQoHb3B0aW9ucxgCIAEoCzIqLnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvbkdlbmVyYXRp'
    'b25PcHRpb25zSABSB29wdGlvbnOIAQESHgoIbW9kZWxfaWQYAyABKAlIAVIHbW9kZWxJZIgBAR'
    'JUCghtZXRhZGF0YRgEIAMoCzI4LnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvbkdlbmVyYXRpb25S'
    'ZXF1ZXN0Lk1ldGFkYXRhRW50cnlSCG1ldGFkYXRhGjsKDU1ldGFkYXRhRW50cnkSEAoDa2V5GA'
    'EgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AUIKCghfb3B0aW9uc0ILCglfbW9k'
    'ZWxfaWQ=');

@$core.Deprecated('Use diffusionProgressDescriptor instead')
const DiffusionProgress$json = {
  '1': 'DiffusionProgress',
  '2': [
    {'1': 'progress_percent', '3': 1, '4': 1, '5': 2, '10': 'progressPercent'},
    {'1': 'current_step', '3': 2, '4': 1, '5': 5, '10': 'currentStep'},
    {'1': 'total_steps', '3': 3, '4': 1, '5': 5, '10': 'totalSteps'},
    {'1': 'stage', '3': 4, '4': 1, '5': 9, '10': 'stage'},
    {'1': 'intermediate_image_data', '3': 5, '4': 1, '5': 12, '9': 0, '10': 'intermediateImageData', '17': true},
    {'1': 'intermediate_image_width', '3': 6, '4': 1, '5': 5, '10': 'intermediateImageWidth'},
    {'1': 'intermediate_image_height', '3': 7, '4': 1, '5': 5, '10': 'intermediateImageHeight'},
    {'1': 'timestamp_ms', '3': 8, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'eta_ms', '3': 9, '4': 1, '5': 3, '10': 'etaMs'},
    {'1': 'intermediate_image_media_type', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'intermediateImageMediaType', '17': true},
  ],
  '8': [
    {'1': '_intermediate_image_data'},
    {'1': '_intermediate_image_media_type'},
  ],
};

/// Descriptor for `DiffusionProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionProgressDescriptor = $convert.base64Decode(
    'ChFEaWZmdXNpb25Qcm9ncmVzcxIpChBwcm9ncmVzc19wZXJjZW50GAEgASgCUg9wcm9ncmVzc1'
    'BlcmNlbnQSIQoMY3VycmVudF9zdGVwGAIgASgFUgtjdXJyZW50U3RlcBIfCgt0b3RhbF9zdGVw'
    'cxgDIAEoBVIKdG90YWxTdGVwcxIUCgVzdGFnZRgEIAEoCVIFc3RhZ2USOwoXaW50ZXJtZWRpYX'
    'RlX2ltYWdlX2RhdGEYBSABKAxIAFIVaW50ZXJtZWRpYXRlSW1hZ2VEYXRhiAEBEjgKGGludGVy'
    'bWVkaWF0ZV9pbWFnZV93aWR0aBgGIAEoBVIWaW50ZXJtZWRpYXRlSW1hZ2VXaWR0aBI6Chlpbn'
    'Rlcm1lZGlhdGVfaW1hZ2VfaGVpZ2h0GAcgASgFUhdpbnRlcm1lZGlhdGVJbWFnZUhlaWdodBIh'
    'Cgx0aW1lc3RhbXBfbXMYCCABKANSC3RpbWVzdGFtcE1zEhUKBmV0YV9tcxgJIAEoA1IFZXRhTX'
    'MSRgodaW50ZXJtZWRpYXRlX2ltYWdlX21lZGlhX3R5cGUYCiABKAlIAVIaaW50ZXJtZWRpYXRl'
    'SW1hZ2VNZWRpYVR5cGWIAQFCGgoYX2ludGVybWVkaWF0ZV9pbWFnZV9kYXRhQiAKHl9pbnRlcm'
    '1lZGlhdGVfaW1hZ2VfbWVkaWFfdHlwZQ==');

@$core.Deprecated('Use diffusionResultDescriptor instead')
const DiffusionResult$json = {
  '1': 'DiffusionResult',
  '2': [
    {'1': 'image_data', '3': 1, '4': 1, '5': 12, '10': 'imageData'},
    {'1': 'width', '3': 2, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 5, '10': 'height'},
    {'1': 'seed_used', '3': 4, '4': 1, '5': 3, '10': 'seedUsed'},
    {'1': 'total_time_ms', '3': 5, '4': 1, '5': 3, '10': 'totalTimeMs'},
    {'1': 'safety_flag', '3': 6, '4': 1, '5': 8, '10': 'safetyFlag'},
    {'1': 'used_scheduler', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionScheduler', '10': 'usedScheduler'},
    {'1': 'error_message', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 9, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'image_media_type', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'imageMediaType', '17': true},
    {'1': 'batch_images', '3': 11, '4': 3, '5': 12, '10': 'batchImages'},
    {'1': 'images_generated', '3': 12, '4': 1, '5': 5, '10': 'imagesGenerated'},
  ],
  '8': [
    {'1': '_error_message'},
    {'1': '_image_media_type'},
  ],
};

/// Descriptor for `DiffusionResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionResultDescriptor = $convert.base64Decode(
    'Cg9EaWZmdXNpb25SZXN1bHQSHQoKaW1hZ2VfZGF0YRgBIAEoDFIJaW1hZ2VEYXRhEhQKBXdpZH'
    'RoGAIgASgFUgV3aWR0aBIWCgZoZWlnaHQYAyABKAVSBmhlaWdodBIbCglzZWVkX3VzZWQYBCAB'
    'KANSCHNlZWRVc2VkEiIKDXRvdGFsX3RpbWVfbXMYBSABKANSC3RvdGFsVGltZU1zEh8KC3NhZm'
    'V0eV9mbGFnGAYgASgIUgpzYWZldHlGbGFnEkkKDnVzZWRfc2NoZWR1bGVyGAcgASgOMiIucnVu'
    'YW55d2hlcmUudjEuRGlmZnVzaW9uU2NoZWR1bGVyUg11c2VkU2NoZWR1bGVyEigKDWVycm9yX2'
    '1lc3NhZ2UYCCABKAlIAFIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYCSABKAVSCWVy'
    'cm9yQ29kZRItChBpbWFnZV9tZWRpYV90eXBlGAogASgJSAFSDmltYWdlTWVkaWFUeXBliAEBEi'
    'EKDGJhdGNoX2ltYWdlcxgLIAMoDFILYmF0Y2hJbWFnZXMSKQoQaW1hZ2VzX2dlbmVyYXRlZBgM'
    'IAEoBVIPaW1hZ2VzR2VuZXJhdGVkQhAKDl9lcnJvcl9tZXNzYWdlQhMKEV9pbWFnZV9tZWRpYV'
    '90eXBl');

@$core.Deprecated('Use diffusionCapabilitiesDescriptor instead')
const DiffusionCapabilities$json = {
  '1': 'DiffusionCapabilities',
  '2': [
    {'1': 'supported_variants', '3': 1, '4': 3, '5': 14, '6': '.runanywhere.v1.DiffusionModelVariant', '10': 'supportedVariants'},
    {'1': 'supported_schedulers', '3': 2, '4': 3, '5': 14, '6': '.runanywhere.v1.DiffusionScheduler', '10': 'supportedSchedulers'},
    {'1': 'max_resolution_px', '3': 3, '4': 1, '5': 5, '10': 'maxResolutionPx'},
    {'1': 'supported_modes', '3': 4, '4': 3, '5': 14, '6': '.runanywhere.v1.DiffusionMode', '10': 'supportedModes'},
    {'1': 'max_width_px', '3': 5, '4': 1, '5': 5, '10': 'maxWidthPx'},
    {'1': 'max_height_px', '3': 6, '4': 1, '5': 5, '10': 'maxHeightPx'},
    {'1': 'supports_intermediate_images', '3': 7, '4': 1, '5': 8, '10': 'supportsIntermediateImages'},
    {'1': 'supports_safety_checker', '3': 8, '4': 1, '5': 8, '10': 'supportsSafetyChecker'},
    {'1': 'is_ready', '3': 9, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'current_model', '3': 10, '4': 1, '5': 9, '9': 0, '10': 'currentModel', '17': true},
    {'1': 'safety_checker_enabled', '3': 11, '4': 1, '5': 8, '10': 'safetyCheckerEnabled'},
    {'1': 'supports_batch_generation', '3': 12, '4': 1, '5': 8, '10': 'supportsBatchGeneration'},
    {'1': 'supported_output_media_types', '3': 13, '4': 3, '5': 9, '10': 'supportedOutputMediaTypes'},
  ],
  '8': [
    {'1': '_current_model'},
  ],
};

/// Descriptor for `DiffusionCapabilities`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionCapabilitiesDescriptor = $convert.base64Decode(
    'ChVEaWZmdXNpb25DYXBhYmlsaXRpZXMSVAoSc3VwcG9ydGVkX3ZhcmlhbnRzGAEgAygOMiUucn'
    'VuYW55d2hlcmUudjEuRGlmZnVzaW9uTW9kZWxWYXJpYW50UhFzdXBwb3J0ZWRWYXJpYW50cxJV'
    'ChRzdXBwb3J0ZWRfc2NoZWR1bGVycxgCIAMoDjIiLnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvbl'
    'NjaGVkdWxlclITc3VwcG9ydGVkU2NoZWR1bGVycxIqChFtYXhfcmVzb2x1dGlvbl9weBgDIAEo'
    'BVIPbWF4UmVzb2x1dGlvblB4EkYKD3N1cHBvcnRlZF9tb2RlcxgEIAMoDjIdLnJ1bmFueXdoZX'
    'JlLnYxLkRpZmZ1c2lvbk1vZGVSDnN1cHBvcnRlZE1vZGVzEiAKDG1heF93aWR0aF9weBgFIAEo'
    'BVIKbWF4V2lkdGhQeBIiCg1tYXhfaGVpZ2h0X3B4GAYgASgFUgttYXhIZWlnaHRQeBJAChxzdX'
    'Bwb3J0c19pbnRlcm1lZGlhdGVfaW1hZ2VzGAcgASgIUhpzdXBwb3J0c0ludGVybWVkaWF0ZUlt'
    'YWdlcxI2ChdzdXBwb3J0c19zYWZldHlfY2hlY2tlchgIIAEoCFIVc3VwcG9ydHNTYWZldHlDaG'
    'Vja2VyEhkKCGlzX3JlYWR5GAkgASgIUgdpc1JlYWR5EigKDWN1cnJlbnRfbW9kZWwYCiABKAlI'
    'AFIMY3VycmVudE1vZGVsiAEBEjQKFnNhZmV0eV9jaGVja2VyX2VuYWJsZWQYCyABKAhSFHNhZm'
    'V0eUNoZWNrZXJFbmFibGVkEjoKGXN1cHBvcnRzX2JhdGNoX2dlbmVyYXRpb24YDCABKAhSF3N1'
    'cHBvcnRzQmF0Y2hHZW5lcmF0aW9uEj8KHHN1cHBvcnRlZF9vdXRwdXRfbWVkaWFfdHlwZXMYDS'
    'ADKAlSGXN1cHBvcnRlZE91dHB1dE1lZGlhVHlwZXNCEAoOX2N1cnJlbnRfbW9kZWw=');

@$core.Deprecated('Use diffusionStreamEventDescriptor instead')
const DiffusionStreamEvent$json = {
  '1': 'DiffusionStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.DiffusionStreamEventKind', '10': 'kind'},
    {'1': 'progress', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionProgress', '9': 0, '10': 'progress', '17': true},
    {'1': 'result', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionResult', '9': 1, '10': 'result', '17': true},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 8, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_progress'},
    {'1': '_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `DiffusionStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionStreamEventDescriptor = $convert.base64Decode(
    'ChREaWZmdXNpb25TdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdX'
    'MYAiABKANSC3RpbWVzdGFtcFVzEh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJZBI8CgRr'
    'aW5kGAQgASgOMigucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uU3RyZWFtRXZlbnRLaW5kUgRraW'
    '5kEkIKCHByb2dyZXNzGAUgASgLMiEucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uUHJvZ3Jlc3NI'
    'AFIIcHJvZ3Jlc3OIAQESPAoGcmVzdWx0GAYgASgLMh8ucnVuYW55d2hlcmUudjEuRGlmZnVzaW'
    '9uUmVzdWx0SAFSBnJlc3VsdIgBARIoCg1lcnJvcl9tZXNzYWdlGAcgASgJSAJSDGVycm9yTWVz'
    'c2FnZYgBARIdCgplcnJvcl9jb2RlGAggASgFUgllcnJvckNvZGVCCwoJX3Byb2dyZXNzQgkKB1'
    '9yZXN1bHRCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use diffusionServiceStateDescriptor instead')
const DiffusionServiceState$json = {
  '1': 'DiffusionServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'current_model', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'currentModel', '17': true},
    {'1': 'capabilities', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.DiffusionCapabilities', '9': 1, '10': 'capabilities', '17': true},
    {'1': 'is_generating', '3': 4, '4': 1, '5': 8, '10': 'isGenerating'},
    {'1': 'active_request_id', '3': 5, '4': 1, '5': 9, '9': 2, '10': 'activeRequestId', '17': true},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '9': 3, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 7, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_current_model'},
    {'1': '_capabilities'},
    {'1': '_active_request_id'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `DiffusionServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List diffusionServiceStateDescriptor = $convert.base64Decode(
    'ChVEaWZmdXNpb25TZXJ2aWNlU3RhdGUSGQoIaXNfcmVhZHkYASABKAhSB2lzUmVhZHkSKAoNY3'
    'VycmVudF9tb2RlbBgCIAEoCUgAUgxjdXJyZW50TW9kZWyIAQESTgoMY2FwYWJpbGl0aWVzGAMg'
    'ASgLMiUucnVuYW55d2hlcmUudjEuRGlmZnVzaW9uQ2FwYWJpbGl0aWVzSAFSDGNhcGFiaWxpdG'
    'llc4gBARIjCg1pc19nZW5lcmF0aW5nGAQgASgIUgxpc0dlbmVyYXRpbmcSLwoRYWN0aXZlX3Jl'
    'cXVlc3RfaWQYBSABKAlIAlIPYWN0aXZlUmVxdWVzdElkiAEBEigKDWVycm9yX21lc3NhZ2UYBi'
    'ABKAlIA1IMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYByABKAVSCWVycm9yQ29kZUIQ'
    'Cg5fY3VycmVudF9tb2RlbEIPCg1fY2FwYWJpbGl0aWVzQhQKEl9hY3RpdmVfcmVxdWVzdF9pZE'
    'IQCg5fZXJyb3JfbWVzc2FnZQ==');

const $core.Map<$core.String, $core.dynamic> DiffusionServiceBase$json = {
  '1': 'Diffusion',
  '2': [
    {'1': 'Generate', '2': '.runanywhere.v1.DiffusionGenerationRequest', '3': '.runanywhere.v1.DiffusionResult'},
    {'1': 'Stream', '2': '.runanywhere.v1.DiffusionGenerationRequest', '3': '.runanywhere.v1.DiffusionStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use diffusionServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> DiffusionServiceBase$messageJson = {
  '.runanywhere.v1.DiffusionGenerationRequest': DiffusionGenerationRequest$json,
  '.runanywhere.v1.DiffusionGenerationOptions': DiffusionGenerationOptions$json,
  '.runanywhere.v1.DiffusionGenerationRequest.MetadataEntry': DiffusionGenerationRequest_MetadataEntry$json,
  '.runanywhere.v1.DiffusionResult': DiffusionResult$json,
  '.runanywhere.v1.DiffusionStreamEvent': DiffusionStreamEvent$json,
  '.runanywhere.v1.DiffusionProgress': DiffusionProgress$json,
};

/// Descriptor for `Diffusion`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List diffusionServiceDescriptor = $convert.base64Decode(
    'CglEaWZmdXNpb24SVwoIR2VuZXJhdGUSKi5ydW5hbnl3aGVyZS52MS5EaWZmdXNpb25HZW5lcm'
    'F0aW9uUmVxdWVzdBofLnJ1bmFueXdoZXJlLnYxLkRpZmZ1c2lvblJlc3VsdBJcCgZTdHJlYW0S'
    'Ki5ydW5hbnl3aGVyZS52MS5EaWZmdXNpb25HZW5lcmF0aW9uUmVxdWVzdBokLnJ1bmFueXdoZX'
    'JlLnYxLkRpZmZ1c2lvblN0cmVhbUV2ZW50MAE=');

