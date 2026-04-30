///
//  Generated code. Do not modify.
//  source: hardware_profile.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use acceleratorPreferenceDescriptor instead')
const AcceleratorPreference$json = const {
  '1': 'AcceleratorPreference',
  '2': const [
    const {'1': 'ACCELERATOR_PREFERENCE_AUTO', '2': 0},
    const {'1': 'ACCELERATOR_PREFERENCE_ANE', '2': 1},
    const {'1': 'ACCELERATOR_PREFERENCE_GPU', '2': 2},
    const {'1': 'ACCELERATOR_PREFERENCE_CPU', '2': 3},
  ],
};

/// Descriptor for `AcceleratorPreference`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List acceleratorPreferenceDescriptor = $convert.base64Decode('ChVBY2NlbGVyYXRvclByZWZlcmVuY2USHwobQUNDRUxFUkFUT1JfUFJFRkVSRU5DRV9BVVRPEAASHgoaQUNDRUxFUkFUT1JfUFJFRkVSRU5DRV9BTkUQARIeChpBQ0NFTEVSQVRPUl9QUkVGRVJFTkNFX0dQVRACEh4KGkFDQ0VMRVJBVE9SX1BSRUZFUkVOQ0VfQ1BVEAM=');
@$core.Deprecated('Use hardwareProfileDescriptor instead')
const HardwareProfile$json = const {
  '1': 'HardwareProfile',
  '2': const [
    const {'1': 'chip', '3': 1, '4': 1, '5': 9, '10': 'chip'},
    const {'1': 'has_neural_engine', '3': 2, '4': 1, '5': 8, '10': 'hasNeuralEngine'},
    const {'1': 'acceleration_mode', '3': 3, '4': 1, '5': 9, '10': 'accelerationMode'},
    const {'1': 'total_memory_bytes', '3': 4, '4': 1, '5': 4, '10': 'totalMemoryBytes'},
    const {'1': 'core_count', '3': 5, '4': 1, '5': 13, '10': 'coreCount'},
    const {'1': 'performance_cores', '3': 6, '4': 1, '5': 13, '10': 'performanceCores'},
    const {'1': 'efficiency_cores', '3': 7, '4': 1, '5': 13, '10': 'efficiencyCores'},
    const {'1': 'architecture', '3': 8, '4': 1, '5': 9, '10': 'architecture'},
    const {'1': 'platform', '3': 9, '4': 1, '5': 9, '10': 'platform'},
  ],
};

/// Descriptor for `HardwareProfile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareProfileDescriptor = $convert.base64Decode('Cg9IYXJkd2FyZVByb2ZpbGUSEgoEY2hpcBgBIAEoCVIEY2hpcBIqChFoYXNfbmV1cmFsX2VuZ2luZRgCIAEoCFIPaGFzTmV1cmFsRW5naW5lEisKEWFjY2VsZXJhdGlvbl9tb2RlGAMgASgJUhBhY2NlbGVyYXRpb25Nb2RlEiwKEnRvdGFsX21lbW9yeV9ieXRlcxgEIAEoBFIQdG90YWxNZW1vcnlCeXRlcxIdCgpjb3JlX2NvdW50GAUgASgNUgljb3JlQ291bnQSKwoRcGVyZm9ybWFuY2VfY29yZXMYBiABKA1SEHBlcmZvcm1hbmNlQ29yZXMSKQoQZWZmaWNpZW5jeV9jb3JlcxgHIAEoDVIPZWZmaWNpZW5jeUNvcmVzEiIKDGFyY2hpdGVjdHVyZRgIIAEoCVIMYXJjaGl0ZWN0dXJlEhoKCHBsYXRmb3JtGAkgASgJUghwbGF0Zm9ybQ==');
@$core.Deprecated('Use acceleratorInfoDescriptor instead')
const AcceleratorInfo$json = const {
  '1': 'AcceleratorInfo',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'type', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.AcceleratorPreference', '10': 'type'},
    const {'1': 'available', '3': 3, '4': 1, '5': 8, '10': 'available'},
  ],
};

/// Descriptor for `AcceleratorInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acceleratorInfoDescriptor = $convert.base64Decode('Cg9BY2NlbGVyYXRvckluZm8SEgoEbmFtZRgBIAEoCVIEbmFtZRI5CgR0eXBlGAIgASgOMiUucnVuYW55d2hlcmUudjEuQWNjZWxlcmF0b3JQcmVmZXJlbmNlUgR0eXBlEhwKCWF2YWlsYWJsZRgDIAEoCFIJYXZhaWxhYmxl');
@$core.Deprecated('Use hardwareProfileResultDescriptor instead')
const HardwareProfileResult$json = const {
  '1': 'HardwareProfileResult',
  '2': const [
    const {'1': 'profile', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.HardwareProfile', '10': 'profile'},
    const {'1': 'accelerators', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.AcceleratorInfo', '10': 'accelerators'},
  ],
};

/// Descriptor for `HardwareProfileResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hardwareProfileResultDescriptor = $convert.base64Decode('ChVIYXJkd2FyZVByb2ZpbGVSZXN1bHQSOQoHcHJvZmlsZRgBIAEoCzIfLnJ1bmFueXdoZXJlLnYxLkhhcmR3YXJlUHJvZmlsZVIHcHJvZmlsZRJDCgxhY2NlbGVyYXRvcnMYAiADKAsyHy5ydW5hbnl3aGVyZS52MS5BY2NlbGVyYXRvckluZm9SDGFjY2VsZXJhdG9ycw==');
