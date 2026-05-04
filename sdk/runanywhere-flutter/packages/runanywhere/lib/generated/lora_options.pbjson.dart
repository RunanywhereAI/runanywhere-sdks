//
//  Generated code. Do not modify.
//  source: lora_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use loRAAdapterConfigDescriptor instead')
const LoRAAdapterConfig$json = {
  '1': 'LoRAAdapterConfig',
  '2': [
    {'1': 'adapter_path', '3': 1, '4': 1, '5': 9, '10': 'adapterPath'},
    {'1': 'scale', '3': 2, '4': 1, '5': 2, '10': 'scale'},
    {'1': 'adapter_id', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'adapterId', '17': true},
  ],
  '8': [
    {'1': '_adapter_id'},
  ],
};

/// Descriptor for `LoRAAdapterConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAAdapterConfigDescriptor = $convert.base64Decode(
    'ChFMb1JBQWRhcHRlckNvbmZpZxIhCgxhZGFwdGVyX3BhdGgYASABKAlSC2FkYXB0ZXJQYXRoEh'
    'QKBXNjYWxlGAIgASgCUgVzY2FsZRIiCgphZGFwdGVyX2lkGAMgASgJSABSCWFkYXB0ZXJJZIgB'
    'AUINCgtfYWRhcHRlcl9pZA==');

@$core.Deprecated('Use loRAAdapterInfoDescriptor instead')
const LoRAAdapterInfo$json = {
  '1': 'LoRAAdapterInfo',
  '2': [
    {'1': 'adapter_id', '3': 1, '4': 1, '5': 9, '10': 'adapterId'},
    {'1': 'adapter_path', '3': 2, '4': 1, '5': 9, '10': 'adapterPath'},
    {'1': 'scale', '3': 3, '4': 1, '5': 2, '10': 'scale'},
    {'1': 'applied', '3': 4, '4': 1, '5': 8, '10': 'applied'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `LoRAAdapterInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAAdapterInfoDescriptor = $convert.base64Decode(
    'Cg9Mb1JBQWRhcHRlckluZm8SHQoKYWRhcHRlcl9pZBgBIAEoCVIJYWRhcHRlcklkEiEKDGFkYX'
    'B0ZXJfcGF0aBgCIAEoCVILYWRhcHRlclBhdGgSFAoFc2NhbGUYAyABKAJSBXNjYWxlEhgKB2Fw'
    'cGxpZWQYBCABKAhSB2FwcGxpZWQSKAoNZXJyb3JfbWVzc2FnZRgFIAEoCUgAUgxlcnJvck1lc3'
    'NhZ2WIAQFCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use loraAdapterCatalogEntryDescriptor instead')
const LoraAdapterCatalogEntry$json = {
  '1': 'LoraAdapterCatalogEntry',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'url', '3': 4, '4': 1, '5': 9, '10': 'url'},
    {'1': 'filename', '3': 5, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'compatible_models', '3': 6, '4': 3, '5': 9, '10': 'compatibleModels'},
    {'1': 'size_bytes', '3': 7, '4': 1, '5': 3, '10': 'sizeBytes'},
    {'1': 'author', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'author', '17': true},
    {'1': 'default_scale', '3': 9, '4': 1, '5': 2, '10': 'defaultScale'},
    {'1': 'checksum_sha256', '3': 10, '4': 1, '5': 9, '9': 1, '10': 'checksumSha256', '17': true},
  ],
  '8': [
    {'1': '_author'},
    {'1': '_checksum_sha256'},
  ],
};

/// Descriptor for `LoraAdapterCatalogEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogEntryDescriptor = $convert.base64Decode(
    'ChdMb3JhQWRhcHRlckNhdGFsb2dFbnRyeRIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCV'
    'IEbmFtZRIgCgtkZXNjcmlwdGlvbhgDIAEoCVILZGVzY3JpcHRpb24SEAoDdXJsGAQgASgJUgN1'
    'cmwSGgoIZmlsZW5hbWUYBSABKAlSCGZpbGVuYW1lEisKEWNvbXBhdGlibGVfbW9kZWxzGAYgAy'
    'gJUhBjb21wYXRpYmxlTW9kZWxzEh0KCnNpemVfYnl0ZXMYByABKANSCXNpemVCeXRlcxIbCgZh'
    'dXRob3IYCCABKAlIAFIGYXV0aG9yiAEBEiMKDWRlZmF1bHRfc2NhbGUYCSABKAJSDGRlZmF1bH'
    'RTY2FsZRIsCg9jaGVja3N1bV9zaGEyNTYYCiABKAlIAVIOY2hlY2tzdW1TaGEyNTaIAQFCCQoH'
    'X2F1dGhvckISChBfY2hlY2tzdW1fc2hhMjU2');

@$core.Deprecated('Use loraCompatibilityResultDescriptor instead')
const LoraCompatibilityResult$json = {
  '1': 'LoraCompatibilityResult',
  '2': [
    {'1': 'is_compatible', '3': 1, '4': 1, '5': 8, '10': 'isCompatible'},
    {'1': 'error_message', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'base_model_required', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'baseModelRequired', '17': true},
  ],
  '8': [
    {'1': '_error_message'},
    {'1': '_base_model_required'},
  ],
};

/// Descriptor for `LoraCompatibilityResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraCompatibilityResultDescriptor = $convert.base64Decode(
    'ChdMb3JhQ29tcGF0aWJpbGl0eVJlc3VsdBIjCg1pc19jb21wYXRpYmxlGAEgASgIUgxpc0NvbX'
    'BhdGlibGUSKAoNZXJyb3JfbWVzc2FnZRgCIAEoCUgAUgxlcnJvck1lc3NhZ2WIAQESMwoTYmFz'
    'ZV9tb2RlbF9yZXF1aXJlZBgDIAEoCUgBUhFiYXNlTW9kZWxSZXF1aXJlZIgBAUIQCg5fZXJyb3'
    'JfbWVzc2FnZUIWChRfYmFzZV9tb2RlbF9yZXF1aXJlZA==');

