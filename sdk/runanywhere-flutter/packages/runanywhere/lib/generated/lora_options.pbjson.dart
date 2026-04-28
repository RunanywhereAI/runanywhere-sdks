///
//  Generated code. Do not modify.
//  source: lora_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use loRAAdapterConfigDescriptor instead')
const LoRAAdapterConfig$json = const {
  '1': 'LoRAAdapterConfig',
  '2': const [
    const {'1': 'adapter_path', '3': 1, '4': 1, '5': 9, '10': 'adapterPath'},
    const {'1': 'scale', '3': 2, '4': 1, '5': 2, '10': 'scale'},
    const {'1': 'adapter_id', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'adapterId', '17': true},
  ],
  '8': const [
    const {'1': '_adapter_id'},
  ],
};

/// Descriptor for `LoRAAdapterConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAAdapterConfigDescriptor = $convert.base64Decode('ChFMb1JBQWRhcHRlckNvbmZpZxIhCgxhZGFwdGVyX3BhdGgYASABKAlSC2FkYXB0ZXJQYXRoEhQKBXNjYWxlGAIgASgCUgVzY2FsZRIiCgphZGFwdGVyX2lkGAMgASgJSABSCWFkYXB0ZXJJZIgBAUINCgtfYWRhcHRlcl9pZA==');
@$core.Deprecated('Use loRAAdapterInfoDescriptor instead')
const LoRAAdapterInfo$json = const {
  '1': 'LoRAAdapterInfo',
  '2': const [
    const {'1': 'adapter_id', '3': 1, '4': 1, '5': 9, '10': 'adapterId'},
    const {'1': 'adapter_path', '3': 2, '4': 1, '5': 9, '10': 'adapterPath'},
    const {'1': 'scale', '3': 3, '4': 1, '5': 2, '10': 'scale'},
    const {'1': 'applied', '3': 4, '4': 1, '5': 8, '10': 'applied'},
    const {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
  ],
  '8': const [
    const {'1': '_error_message'},
  ],
};

/// Descriptor for `LoRAAdapterInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAAdapterInfoDescriptor = $convert.base64Decode('Cg9Mb1JBQWRhcHRlckluZm8SHQoKYWRhcHRlcl9pZBgBIAEoCVIJYWRhcHRlcklkEiEKDGFkYXB0ZXJfcGF0aBgCIAEoCVILYWRhcHRlclBhdGgSFAoFc2NhbGUYAyABKAJSBXNjYWxlEhgKB2FwcGxpZWQYBCABKAhSB2FwcGxpZWQSKAoNZXJyb3JfbWVzc2FnZRgFIAEoCUgAUgxlcnJvck1lc3NhZ2WIAQFCEAoOX2Vycm9yX21lc3NhZ2U=');
@$core.Deprecated('Use loraAdapterCatalogEntryDescriptor instead')
const LoraAdapterCatalogEntry$json = const {
  '1': 'LoraAdapterCatalogEntry',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    const {'1': 'url', '3': 4, '4': 1, '5': 9, '10': 'url'},
    const {'1': 'filename', '3': 5, '4': 1, '5': 9, '10': 'filename'},
    const {'1': 'compatible_models', '3': 6, '4': 3, '5': 9, '10': 'compatibleModels'},
    const {'1': 'size_bytes', '3': 7, '4': 1, '5': 3, '10': 'sizeBytes'},
    const {'1': 'author', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'author', '17': true},
  ],
  '8': const [
    const {'1': '_author'},
  ],
};

/// Descriptor for `LoraAdapterCatalogEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogEntryDescriptor = $convert.base64Decode('ChdMb3JhQWRhcHRlckNhdGFsb2dFbnRyeRIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIgCgtkZXNjcmlwdGlvbhgDIAEoCVILZGVzY3JpcHRpb24SEAoDdXJsGAQgASgJUgN1cmwSGgoIZmlsZW5hbWUYBSABKAlSCGZpbGVuYW1lEisKEWNvbXBhdGlibGVfbW9kZWxzGAYgAygJUhBjb21wYXRpYmxlTW9kZWxzEh0KCnNpemVfYnl0ZXMYByABKANSCXNpemVCeXRlcxIbCgZhdXRob3IYCCABKAlIAFIGYXV0aG9yiAEBQgkKB19hdXRob3I=');
@$core.Deprecated('Use loraCompatibilityResultDescriptor instead')
const LoraCompatibilityResult$json = const {
  '1': 'LoraCompatibilityResult',
  '2': const [
    const {'1': 'is_compatible', '3': 1, '4': 1, '5': 8, '10': 'isCompatible'},
    const {'1': 'error_message', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    const {'1': 'base_model_required', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'baseModelRequired', '17': true},
  ],
  '8': const [
    const {'1': '_error_message'},
    const {'1': '_base_model_required'},
  ],
};

/// Descriptor for `LoraCompatibilityResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraCompatibilityResultDescriptor = $convert.base64Decode('ChdMb3JhQ29tcGF0aWJpbGl0eVJlc3VsdBIjCg1pc19jb21wYXRpYmxlGAEgASgIUgxpc0NvbXBhdGlibGUSKAoNZXJyb3JfbWVzc2FnZRgCIAEoCUgAUgxlcnJvck1lc3NhZ2WIAQESMwoTYmFzZV9tb2RlbF9yZXF1aXJlZBgDIAEoCUgBUhFiYXNlTW9kZWxSZXF1aXJlZIgBAUIQCg5fZXJyb3JfbWVzc2FnZUIWChRfYmFzZV9tb2RlbF9yZXF1aXJlZA==');
