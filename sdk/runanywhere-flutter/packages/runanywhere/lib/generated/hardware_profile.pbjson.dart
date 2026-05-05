//
//  Generated code. Do not modify.
//  source: hardware_profile.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use accelerationPreferenceDescriptor instead')
const AccelerationPreference$json = {
  '1': 'AccelerationPreference',
  '2': [
    {'1': 'ACCELERATION_PREFERENCE_UNSPECIFIED', '2': 0},
    {'1': 'ACCELERATION_PREFERENCE_AUTO', '2': 1},
    {'1': 'ACCELERATION_PREFERENCE_CPU', '2': 2},
    {'1': 'ACCELERATION_PREFERENCE_GPU', '2': 3},
    {'1': 'ACCELERATION_PREFERENCE_NPU', '2': 4},
    {'1': 'ACCELERATION_PREFERENCE_WEBGPU', '2': 5},
    {'1': 'ACCELERATION_PREFERENCE_METAL', '2': 6},
    {'1': 'ACCELERATION_PREFERENCE_VULKAN', '2': 7},
  ],
};

/// Descriptor for `AccelerationPreference`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List accelerationPreferenceDescriptor = $convert.base64Decode(
    'ChZBY2NlbGVyYXRpb25QcmVmZXJlbmNlEicKI0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX1VOU1'
    'BFQ0lGSUVEEAASIAocQUNDRUxFUkFUSU9OX1BSRUZFUkVOQ0VfQVVUTxABEh8KG0FDQ0VMRVJB'
    'VElPTl9QUkVGRVJFTkNFX0NQVRACEh8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX0dQVRADEh'
    '8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX05QVRAEEiIKHkFDQ0VMRVJBVElPTl9QUkVGRVJF'
    'TkNFX1dFQkdQVRAFEiEKHUFDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX01FVEFMEAYSIgoeQUNDRU'
    'xFUkFUSU9OX1BSRUZFUkVOQ0VfVlVMS0FOEAc=');

@$core.Deprecated('Use hardwareProfileDescriptor instead')
const HardwareProfile$json = {
  '1': 'HardwareProfile',
  '2': [
    {'1': 'chip', '3': 1, '4': 1, '5': 9, '10': 'chip'},
    {'1': 'has_neural_engine', '3': 2, '4': 1, '5': 8, '10': 'hasNeuralEngine'},
    {'1': 'acceleration_mode', '3': 3, '4': 1, '5': 9, '10': 'accelerationMode'},
    {'1': 'total_memory_bytes', '3': 4, '4': 1, '5': 4, '10': 'totalMemoryBytes'},
    {'1': 'core_count', '3': 5, '4': 1, '5': 13, '10': 'coreCount'},
    {'1': 'performance_cores', '3': 6, '4': 1, '5': 13, '10': 'performanceCores'},
    {'1': 'efficiency_cores', '3': 7, '4': 1, '5': 13, '10': 'efficiencyCores'},
    {'1': 'architecture', '3': 8, '4': 1, '5': 9, '10': 'architecture'},
    {'1': 'platform', '3': 9, '4': 1, '5': 9, '10': 'platform'},
  ],
};

/// Descriptor for `HardwareProfile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareProfileDescriptor = $convert.base64Decode(
    'Cg9IYXJkd2FyZVByb2ZpbGUSEgoEY2hpcBgBIAEoCVIEY2hpcBIqChFoYXNfbmV1cmFsX2VuZ2'
    'luZRgCIAEoCFIPaGFzTmV1cmFsRW5naW5lEisKEWFjY2VsZXJhdGlvbl9tb2RlGAMgASgJUhBh'
    'Y2NlbGVyYXRpb25Nb2RlEiwKEnRvdGFsX21lbW9yeV9ieXRlcxgEIAEoBFIQdG90YWxNZW1vcn'
    'lCeXRlcxIdCgpjb3JlX2NvdW50GAUgASgNUgljb3JlQ291bnQSKwoRcGVyZm9ybWFuY2VfY29y'
    'ZXMYBiABKA1SEHBlcmZvcm1hbmNlQ29yZXMSKQoQZWZmaWNpZW5jeV9jb3JlcxgHIAEoDVIPZW'
    'ZmaWNpZW5jeUNvcmVzEiIKDGFyY2hpdGVjdHVyZRgIIAEoCVIMYXJjaGl0ZWN0dXJlEhoKCHBs'
    'YXRmb3JtGAkgASgJUghwbGF0Zm9ybQ==');

@$core.Deprecated('Use acceleratorInfoDescriptor instead')
const AcceleratorInfo$json = {
  '1': 'AcceleratorInfo',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'type', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.AccelerationPreference', '10': 'type'},
    {'1': 'available', '3': 3, '4': 1, '5': 8, '10': 'available'},
  ],
};

/// Descriptor for `AcceleratorInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acceleratorInfoDescriptor = $convert.base64Decode(
    'Cg9BY2NlbGVyYXRvckluZm8SEgoEbmFtZRgBIAEoCVIEbmFtZRI6CgR0eXBlGAIgASgOMiYucn'
    'VuYW55d2hlcmUudjEuQWNjZWxlcmF0aW9uUHJlZmVyZW5jZVIEdHlwZRIcCglhdmFpbGFibGUY'
    'AyABKAhSCWF2YWlsYWJsZQ==');

@$core.Deprecated('Use hardwareProfileResultDescriptor instead')
const HardwareProfileResult$json = {
  '1': 'HardwareProfileResult',
  '2': [
    {'1': 'profile', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.HardwareProfile', '10': 'profile'},
    {'1': 'accelerators', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.AcceleratorInfo', '10': 'accelerators'},
  ],
};

/// Descriptor for `HardwareProfileResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareProfileResultDescriptor = $convert.base64Decode(
    'ChVIYXJkd2FyZVByb2ZpbGVSZXN1bHQSOQoHcHJvZmlsZRgBIAEoCzIfLnJ1bmFueXdoZXJlLn'
    'YxLkhhcmR3YXJlUHJvZmlsZVIHcHJvZmlsZRJDCgxhY2NlbGVyYXRvcnMYAiADKAsyHy5ydW5h'
    'bnl3aGVyZS52MS5BY2NlbGVyYXRvckluZm9SDGFjY2VsZXJhdG9ycw==');

@$core.Deprecated('Use hardwareProfileRequestDescriptor instead')
const HardwareProfileRequest$json = {
  '1': 'HardwareProfileRequest',
};

/// Descriptor for `HardwareProfileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareProfileRequestDescriptor = $convert.base64Decode(
    'ChZIYXJkd2FyZVByb2ZpbGVSZXF1ZXN0');

@$core.Deprecated('Use hardwareAcceleratorsRequestDescriptor instead')
const HardwareAcceleratorsRequest$json = {
  '1': 'HardwareAcceleratorsRequest',
};

/// Descriptor for `HardwareAcceleratorsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareAcceleratorsRequestDescriptor = $convert.base64Decode(
    'ChtIYXJkd2FyZUFjY2VsZXJhdG9yc1JlcXVlc3Q=');

@$core.Deprecated('Use hardwareAcceleratorPreferenceRequestDescriptor instead')
const HardwareAcceleratorPreferenceRequest$json = {
  '1': 'HardwareAcceleratorPreferenceRequest',
  '2': [
    {'1': 'preference', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.AccelerationPreference', '10': 'preference'},
  ],
};

/// Descriptor for `HardwareAcceleratorPreferenceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareAcceleratorPreferenceRequestDescriptor = $convert.base64Decode(
    'CiRIYXJkd2FyZUFjY2VsZXJhdG9yUHJlZmVyZW5jZVJlcXVlc3QSRgoKcHJlZmVyZW5jZRgBIA'
    'EoDjImLnJ1bmFueXdoZXJlLnYxLkFjY2VsZXJhdGlvblByZWZlcmVuY2VSCnByZWZlcmVuY2U=');

@$core.Deprecated('Use hardwareAcceleratorPreferenceResultDescriptor instead')
const HardwareAcceleratorPreferenceResult$json = {
  '1': 'HardwareAcceleratorPreferenceResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'error_message', '3': 2, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `HardwareAcceleratorPreferenceResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareAcceleratorPreferenceResultDescriptor = $convert.base64Decode(
    'CiNIYXJkd2FyZUFjY2VsZXJhdG9yUHJlZmVyZW5jZVJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUg'
    'dzdWNjZXNzEiMKDWVycm9yX21lc3NhZ2UYAiABKAlSDGVycm9yTWVzc2FnZQ==');

const $core.Map<$core.String, $core.dynamic> HardwareServiceBase$json = {
  '1': 'Hardware',
  '2': [
    {'1': 'GetProfile', '2': '.runanywhere.v1.HardwareProfileRequest', '3': '.runanywhere.v1.HardwareProfileResult'},
    {'1': 'GetAccelerators', '2': '.runanywhere.v1.HardwareAcceleratorsRequest', '3': '.runanywhere.v1.HardwareProfileResult'},
    {'1': 'SetAcceleratorPreference', '2': '.runanywhere.v1.HardwareAcceleratorPreferenceRequest', '3': '.runanywhere.v1.HardwareAcceleratorPreferenceResult'},
  ],
};

@$core.Deprecated('Use hardwareServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> HardwareServiceBase$messageJson = {
  '.runanywhere.v1.HardwareProfileRequest': HardwareProfileRequest$json,
  '.runanywhere.v1.HardwareProfileResult': HardwareProfileResult$json,
  '.runanywhere.v1.HardwareProfile': HardwareProfile$json,
  '.runanywhere.v1.AcceleratorInfo': AcceleratorInfo$json,
  '.runanywhere.v1.HardwareAcceleratorsRequest': HardwareAcceleratorsRequest$json,
  '.runanywhere.v1.HardwareAcceleratorPreferenceRequest': HardwareAcceleratorPreferenceRequest$json,
  '.runanywhere.v1.HardwareAcceleratorPreferenceResult': HardwareAcceleratorPreferenceResult$json,
};

/// Descriptor for `Hardware`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List hardwareServiceDescriptor = $convert.base64Decode(
    'CghIYXJkd2FyZRJbCgpHZXRQcm9maWxlEiYucnVuYW55d2hlcmUudjEuSGFyZHdhcmVQcm9maW'
    'xlUmVxdWVzdBolLnJ1bmFueXdoZXJlLnYxLkhhcmR3YXJlUHJvZmlsZVJlc3VsdBJlCg9HZXRB'
    'Y2NlbGVyYXRvcnMSKy5ydW5hbnl3aGVyZS52MS5IYXJkd2FyZUFjY2VsZXJhdG9yc1JlcXVlc3'
    'QaJS5ydW5hbnl3aGVyZS52MS5IYXJkd2FyZVByb2ZpbGVSZXN1bHQShQEKGFNldEFjY2VsZXJh'
    'dG9yUHJlZmVyZW5jZRI0LnJ1bmFueXdoZXJlLnYxLkhhcmR3YXJlQWNjZWxlcmF0b3JQcmVmZX'
    'JlbmNlUmVxdWVzdBozLnJ1bmFueXdoZXJlLnYxLkhhcmR3YXJlQWNjZWxlcmF0b3JQcmVmZXJl'
    'bmNlUmVzdWx0');

