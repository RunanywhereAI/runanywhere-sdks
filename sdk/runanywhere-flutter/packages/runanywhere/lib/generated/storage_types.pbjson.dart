///
//  Generated code. Do not modify.
//  source: storage_types.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use nPUChipDescriptor instead')
const NPUChip$json = const {
  '1': 'NPUChip',
  '2': const [
    const {'1': 'NPU_CHIP_UNSPECIFIED', '2': 0},
    const {'1': 'NPU_CHIP_NONE', '2': 1},
    const {'1': 'NPU_CHIP_APPLE_NEURAL_ENGINE', '2': 2},
    const {'1': 'NPU_CHIP_QUALCOMM_HEXAGON', '2': 3},
    const {'1': 'NPU_CHIP_MEDIATEK_APU', '2': 4},
    const {'1': 'NPU_CHIP_GOOGLE_TPU', '2': 5},
    const {'1': 'NPU_CHIP_INTEL_NPU', '2': 6},
    const {'1': 'NPU_CHIP_OTHER', '2': 99},
  ],
};

/// Descriptor for `NPUChip`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List nPUChipDescriptor = $convert.base64Decode('CgdOUFVDaGlwEhgKFE5QVV9DSElQX1VOU1BFQ0lGSUVEEAASEQoNTlBVX0NISVBfTk9ORRABEiAKHE5QVV9DSElQX0FQUExFX05FVVJBTF9FTkdJTkUQAhIdChlOUFVfQ0hJUF9RVUFMQ09NTV9IRVhBR09OEAMSGQoVTlBVX0NISVBfTUVESUFURUtfQVBVEAQSFwoTTlBVX0NISVBfR09PR0xFX1RQVRAFEhYKEk5QVV9DSElQX0lOVEVMX05QVRAGEhIKDk5QVV9DSElQX09USEVSEGM=');
@$core.Deprecated('Use deviceStorageInfoDescriptor instead')
const DeviceStorageInfo$json = const {
  '1': 'DeviceStorageInfo',
  '2': const [
    const {'1': 'total_bytes', '3': 1, '4': 1, '5': 3, '10': 'totalBytes'},
    const {'1': 'free_bytes', '3': 2, '4': 1, '5': 3, '10': 'freeBytes'},
    const {'1': 'used_bytes', '3': 3, '4': 1, '5': 3, '10': 'usedBytes'},
    const {'1': 'used_percent', '3': 4, '4': 1, '5': 2, '10': 'usedPercent'},
  ],
};

/// Descriptor for `DeviceStorageInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceStorageInfoDescriptor = $convert.base64Decode('ChFEZXZpY2VTdG9yYWdlSW5mbxIfCgt0b3RhbF9ieXRlcxgBIAEoA1IKdG90YWxCeXRlcxIdCgpmcmVlX2J5dGVzGAIgASgDUglmcmVlQnl0ZXMSHQoKdXNlZF9ieXRlcxgDIAEoA1IJdXNlZEJ5dGVzEiEKDHVzZWRfcGVyY2VudBgEIAEoAlILdXNlZFBlcmNlbnQ=');
@$core.Deprecated('Use appStorageInfoDescriptor instead')
const AppStorageInfo$json = const {
  '1': 'AppStorageInfo',
  '2': const [
    const {'1': 'documents_bytes', '3': 1, '4': 1, '5': 3, '10': 'documentsBytes'},
    const {'1': 'cache_bytes', '3': 2, '4': 1, '5': 3, '10': 'cacheBytes'},
    const {'1': 'app_support_bytes', '3': 3, '4': 1, '5': 3, '10': 'appSupportBytes'},
    const {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
  ],
};

/// Descriptor for `AppStorageInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appStorageInfoDescriptor = $convert.base64Decode('Cg5BcHBTdG9yYWdlSW5mbxInCg9kb2N1bWVudHNfYnl0ZXMYASABKANSDmRvY3VtZW50c0J5dGVzEh8KC2NhY2hlX2J5dGVzGAIgASgDUgpjYWNoZUJ5dGVzEioKEWFwcF9zdXBwb3J0X2J5dGVzGAMgASgDUg9hcHBTdXBwb3J0Qnl0ZXMSHwoLdG90YWxfYnl0ZXMYBCABKANSCnRvdGFsQnl0ZXM=');
@$core.Deprecated('Use modelStorageMetricsDescriptor instead')
const ModelStorageMetrics$json = const {
  '1': 'ModelStorageMetrics',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'size_on_disk_bytes', '3': 2, '4': 1, '5': 3, '10': 'sizeOnDiskBytes'},
    const {'1': 'last_used_ms', '3': 3, '4': 1, '5': 3, '9': 0, '10': 'lastUsedMs', '17': true},
  ],
  '8': const [
    const {'1': '_last_used_ms'},
  ],
};

/// Descriptor for `ModelStorageMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelStorageMetricsDescriptor = $convert.base64Decode('ChNNb2RlbFN0b3JhZ2VNZXRyaWNzEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEisKEnNpemVfb25fZGlza19ieXRlcxgCIAEoA1IPc2l6ZU9uRGlza0J5dGVzEiUKDGxhc3RfdXNlZF9tcxgDIAEoA0gAUgpsYXN0VXNlZE1ziAEBQg8KDV9sYXN0X3VzZWRfbXM=');
@$core.Deprecated('Use storageInfoDescriptor instead')
const StorageInfo$json = const {
  '1': 'StorageInfo',
  '2': const [
    const {'1': 'app', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.AppStorageInfo', '10': 'app'},
    const {'1': 'device', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.DeviceStorageInfo', '10': 'device'},
    const {'1': 'models', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelStorageMetrics', '10': 'models'},
    const {'1': 'total_models', '3': 4, '4': 1, '5': 5, '10': 'totalModels'},
    const {'1': 'total_models_bytes', '3': 5, '4': 1, '5': 3, '10': 'totalModelsBytes'},
  ],
};

/// Descriptor for `StorageInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageInfoDescriptor = $convert.base64Decode('CgtTdG9yYWdlSW5mbxIwCgNhcHAYASABKAsyHi5ydW5hbnl3aGVyZS52MS5BcHBTdG9yYWdlSW5mb1IDYXBwEjkKBmRldmljZRgCIAEoCzIhLnJ1bmFueXdoZXJlLnYxLkRldmljZVN0b3JhZ2VJbmZvUgZkZXZpY2USOwoGbW9kZWxzGAMgAygLMiMucnVuYW55d2hlcmUudjEuTW9kZWxTdG9yYWdlTWV0cmljc1IGbW9kZWxzEiEKDHRvdGFsX21vZGVscxgEIAEoBVILdG90YWxNb2RlbHMSLAoSdG90YWxfbW9kZWxzX2J5dGVzGAUgASgDUhB0b3RhbE1vZGVsc0J5dGVz');
@$core.Deprecated('Use storageAvailabilityDescriptor instead')
const StorageAvailability$json = const {
  '1': 'StorageAvailability',
  '2': const [
    const {'1': 'is_available', '3': 1, '4': 1, '5': 8, '10': 'isAvailable'},
    const {'1': 'required_bytes', '3': 2, '4': 1, '5': 3, '10': 'requiredBytes'},
    const {'1': 'available_bytes', '3': 3, '4': 1, '5': 3, '10': 'availableBytes'},
    const {'1': 'warning_message', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'warningMessage', '17': true},
    const {'1': 'recommendation', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'recommendation', '17': true},
  ],
  '8': const [
    const {'1': '_warning_message'},
    const {'1': '_recommendation'},
  ],
};

/// Descriptor for `StorageAvailability`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageAvailabilityDescriptor = $convert.base64Decode('ChNTdG9yYWdlQXZhaWxhYmlsaXR5EiEKDGlzX2F2YWlsYWJsZRgBIAEoCFILaXNBdmFpbGFibGUSJQoOcmVxdWlyZWRfYnl0ZXMYAiABKANSDXJlcXVpcmVkQnl0ZXMSJwoPYXZhaWxhYmxlX2J5dGVzGAMgASgDUg5hdmFpbGFibGVCeXRlcxIsCg93YXJuaW5nX21lc3NhZ2UYBCABKAlIAFIOd2FybmluZ01lc3NhZ2WIAQESKwoOcmVjb21tZW5kYXRpb24YBSABKAlIAVIOcmVjb21tZW5kYXRpb26IAQFCEgoQX3dhcm5pbmdfbWVzc2FnZUIRCg9fcmVjb21tZW5kYXRpb24=');
@$core.Deprecated('Use storedModelDescriptor instead')
const StoredModel$json = const {
  '1': 'StoredModel',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'size_bytes', '3': 3, '4': 1, '5': 3, '10': 'sizeBytes'},
    const {'1': 'local_path', '3': 4, '4': 1, '5': 9, '10': 'localPath'},
    const {'1': 'downloaded_at_ms', '3': 5, '4': 1, '5': 3, '9': 0, '10': 'downloadedAtMs', '17': true},
  ],
  '8': const [
    const {'1': '_downloaded_at_ms'},
  ],
};

/// Descriptor for `StoredModel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storedModelDescriptor = $convert.base64Decode('CgtTdG9yZWRNb2RlbBIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBISCgRuYW1lGAIgASgJUgRuYW1lEh0KCnNpemVfYnl0ZXMYAyABKANSCXNpemVCeXRlcxIdCgpsb2NhbF9wYXRoGAQgASgJUglsb2NhbFBhdGgSLQoQZG93bmxvYWRlZF9hdF9tcxgFIAEoA0gAUg5kb3dubG9hZGVkQXRNc4gBAUITChFfZG93bmxvYWRlZF9hdF9tcw==');
