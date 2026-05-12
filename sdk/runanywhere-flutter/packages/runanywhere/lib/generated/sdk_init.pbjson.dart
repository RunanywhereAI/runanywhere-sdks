//
//  Generated code. Do not modify.
//  source: sdk_init.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use sdkInitPhaseDescriptor instead')
const SdkInitPhase$json = {
  '1': 'SdkInitPhase',
  '2': [
    {'1': 'SDK_INIT_PHASE_UNSPECIFIED', '2': 0},
    {'1': 'SDK_INIT_PHASE_ONE', '2': 1},
    {'1': 'SDK_INIT_PHASE_TWO', '2': 2},
    {'1': 'SDK_INIT_PHASE_RETRY_HTTP', '2': 3},
  ],
};

/// Descriptor for `SdkInitPhase`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sdkInitPhaseDescriptor = $convert.base64Decode(
    'CgxTZGtJbml0UGhhc2USHgoaU0RLX0lOSVRfUEhBU0VfVU5TUEVDSUZJRUQQABIWChJTREtfSU'
    '5JVF9QSEFTRV9PTkUQARIWChJTREtfSU5JVF9QSEFTRV9UV08QAhIdChlTREtfSU5JVF9QSEFT'
    'RV9SRVRSWV9IVFRQEAM=');

@$core.Deprecated('Use sdkInitEnvironmentDescriptor instead')
const SdkInitEnvironment$json = {
  '1': 'SdkInitEnvironment',
  '2': [
    {'1': 'SDK_INIT_ENVIRONMENT_DEVELOPMENT', '2': 0},
    {'1': 'SDK_INIT_ENVIRONMENT_STAGING', '2': 1},
    {'1': 'SDK_INIT_ENVIRONMENT_PRODUCTION', '2': 2},
  ],
};

/// Descriptor for `SdkInitEnvironment`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sdkInitEnvironmentDescriptor = $convert.base64Decode(
    'ChJTZGtJbml0RW52aXJvbm1lbnQSJAogU0RLX0lOSVRfRU5WSVJPTk1FTlRfREVWRUxPUE1FTl'
    'QQABIgChxTREtfSU5JVF9FTlZJUk9OTUVOVF9TVEFHSU5HEAESIwofU0RLX0lOSVRfRU5WSVJP'
    'Tk1FTlRfUFJPRFVDVElPThAC');

@$core.Deprecated('Use sdkInitPhase1RequestDescriptor instead')
const SdkInitPhase1Request$json = {
  '1': 'SdkInitPhase1Request',
  '2': [
    {'1': 'environment', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.SdkInitEnvironment', '10': 'environment'},
    {'1': 'api_key', '3': 2, '4': 1, '5': 9, '10': 'apiKey'},
    {'1': 'base_url', '3': 3, '4': 1, '5': 9, '10': 'baseUrl'},
    {'1': 'device_id', '3': 4, '4': 1, '5': 9, '10': 'deviceId'},
  ],
};

/// Descriptor for `SdkInitPhase1Request`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sdkInitPhase1RequestDescriptor = $convert.base64Decode(
    'ChRTZGtJbml0UGhhc2UxUmVxdWVzdBJECgtlbnZpcm9ubWVudBgBIAEoDjIiLnJ1bmFueXdoZX'
    'JlLnYxLlNka0luaXRFbnZpcm9ubWVudFILZW52aXJvbm1lbnQSFwoHYXBpX2tleRgCIAEoCVIG'
    'YXBpS2V5EhkKCGJhc2VfdXJsGAMgASgJUgdiYXNlVXJsEhsKCWRldmljZV9pZBgEIAEoCVIIZG'
    'V2aWNlSWQ=');

@$core.Deprecated('Use sdkInitPhase2RequestDescriptor instead')
const SdkInitPhase2Request$json = {
  '1': 'SdkInitPhase2Request',
};

/// Descriptor for `SdkInitPhase2Request`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sdkInitPhase2RequestDescriptor = $convert.base64Decode(
    'ChRTZGtJbml0UGhhc2UyUmVxdWVzdA==');

@$core.Deprecated('Use sdkInitResultDescriptor instead')
const SdkInitResult$json = {
  '1': 'SdkInitResult',
  '2': [
    {'1': 'phase', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.SdkInitPhase', '10': 'phase'},
    {'1': 'success', '3': 2, '4': 1, '5': 8, '10': 'success'},
    {'1': 'error', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.SDKError', '10': 'error'},
    {'1': 'http_configured', '3': 4, '4': 1, '5': 8, '10': 'httpConfigured'},
    {'1': 'device_registered', '3': 5, '4': 1, '5': 8, '10': 'deviceRegistered'},
    {'1': 'linked_models_count', '3': 6, '4': 1, '5': 13, '10': 'linkedModelsCount'},
    {'1': 'discovered_orphans', '3': 7, '4': 1, '5': 13, '10': 'discoveredOrphans'},
    {'1': 'warning', '3': 8, '4': 1, '5': 9, '10': 'warning'},
    {'1': 'duration_ms', '3': 9, '4': 1, '5': 3, '10': 'durationMs'},
  ],
};

/// Descriptor for `SdkInitResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sdkInitResultDescriptor = $convert.base64Decode(
    'Cg1TZGtJbml0UmVzdWx0EjIKBXBoYXNlGAEgASgOMhwucnVuYW55d2hlcmUudjEuU2RrSW5pdF'
    'BoYXNlUgVwaGFzZRIYCgdzdWNjZXNzGAIgASgIUgdzdWNjZXNzEi4KBWVycm9yGAMgASgLMhgu'
    'cnVuYW55d2hlcmUudjEuU0RLRXJyb3JSBWVycm9yEicKD2h0dHBfY29uZmlndXJlZBgEIAEoCF'
    'IOaHR0cENvbmZpZ3VyZWQSKwoRZGV2aWNlX3JlZ2lzdGVyZWQYBSABKAhSEGRldmljZVJlZ2lz'
    'dGVyZWQSLgoTbGlua2VkX21vZGVsc19jb3VudBgGIAEoDVIRbGlua2VkTW9kZWxzQ291bnQSLQ'
    'oSZGlzY292ZXJlZF9vcnBoYW5zGAcgASgNUhFkaXNjb3ZlcmVkT3JwaGFucxIYCgd3YXJuaW5n'
    'GAggASgJUgd3YXJuaW5nEh8KC2R1cmF0aW9uX21zGAkgASgDUgpkdXJhdGlvbk1z');

