//
//  Generated code. Do not modify.
//  source: storage_types.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use nPUChipDescriptor instead')
const NPUChip$json = {
  '1': 'NPUChip',
  '2': [
    {'1': 'NPU_CHIP_UNSPECIFIED', '2': 0},
    {'1': 'NPU_CHIP_NONE', '2': 1},
    {'1': 'NPU_CHIP_APPLE_NEURAL_ENGINE', '2': 2},
    {'1': 'NPU_CHIP_QUALCOMM_HEXAGON', '2': 3},
    {'1': 'NPU_CHIP_MEDIATEK_APU', '2': 4},
    {'1': 'NPU_CHIP_GOOGLE_TPU', '2': 5},
    {'1': 'NPU_CHIP_INTEL_NPU', '2': 6},
    {'1': 'NPU_CHIP_OTHER', '2': 99},
  ],
};

/// Descriptor for `NPUChip`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List nPUChipDescriptor = $convert.base64Decode(
    'CgdOUFVDaGlwEhgKFE5QVV9DSElQX1VOU1BFQ0lGSUVEEAASEQoNTlBVX0NISVBfTk9ORRABEi'
    'AKHE5QVV9DSElQX0FQUExFX05FVVJBTF9FTkdJTkUQAhIdChlOUFVfQ0hJUF9RVUFMQ09NTV9I'
    'RVhBR09OEAMSGQoVTlBVX0NISVBfTUVESUFURUtfQVBVEAQSFwoTTlBVX0NISVBfR09PR0xFX1'
    'RQVRAFEhYKEk5QVV9DSElQX0lOVEVMX05QVRAGEhIKDk5QVV9DSElQX09USEVSEGM=');

@$core.Deprecated('Use deviceStorageInfoDescriptor instead')
const DeviceStorageInfo$json = {
  '1': 'DeviceStorageInfo',
  '2': [
    {'1': 'total_bytes', '3': 1, '4': 1, '5': 3, '10': 'totalBytes'},
    {'1': 'free_bytes', '3': 2, '4': 1, '5': 3, '10': 'freeBytes'},
    {'1': 'used_bytes', '3': 3, '4': 1, '5': 3, '10': 'usedBytes'},
    {'1': 'used_percent', '3': 4, '4': 1, '5': 2, '10': 'usedPercent'},
  ],
};

/// Descriptor for `DeviceStorageInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceStorageInfoDescriptor = $convert.base64Decode(
    'ChFEZXZpY2VTdG9yYWdlSW5mbxIfCgt0b3RhbF9ieXRlcxgBIAEoA1IKdG90YWxCeXRlcxIdCg'
    'pmcmVlX2J5dGVzGAIgASgDUglmcmVlQnl0ZXMSHQoKdXNlZF9ieXRlcxgDIAEoA1IJdXNlZEJ5'
    'dGVzEiEKDHVzZWRfcGVyY2VudBgEIAEoAlILdXNlZFBlcmNlbnQ=');

@$core.Deprecated('Use appStorageInfoDescriptor instead')
const AppStorageInfo$json = {
  '1': 'AppStorageInfo',
  '2': [
    {'1': 'documents_bytes', '3': 1, '4': 1, '5': 3, '10': 'documentsBytes'},
    {'1': 'cache_bytes', '3': 2, '4': 1, '5': 3, '10': 'cacheBytes'},
    {'1': 'app_support_bytes', '3': 3, '4': 1, '5': 3, '10': 'appSupportBytes'},
    {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
  ],
};

/// Descriptor for `AppStorageInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List appStorageInfoDescriptor = $convert.base64Decode(
    'Cg5BcHBTdG9yYWdlSW5mbxInCg9kb2N1bWVudHNfYnl0ZXMYASABKANSDmRvY3VtZW50c0J5dG'
    'VzEh8KC2NhY2hlX2J5dGVzGAIgASgDUgpjYWNoZUJ5dGVzEioKEWFwcF9zdXBwb3J0X2J5dGVz'
    'GAMgASgDUg9hcHBTdXBwb3J0Qnl0ZXMSHwoLdG90YWxfYnl0ZXMYBCABKANSCnRvdGFsQnl0ZX'
    'M=');

@$core.Deprecated('Use modelStorageMetricsDescriptor instead')
const ModelStorageMetrics$json = {
  '1': 'ModelStorageMetrics',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'size_on_disk_bytes', '3': 2, '4': 1, '5': 3, '10': 'sizeOnDiskBytes'},
    {'1': 'last_used_ms', '3': 3, '4': 1, '5': 3, '9': 0, '10': 'lastUsedMs', '17': true},
  ],
  '8': [
    {'1': '_last_used_ms'},
  ],
};

/// Descriptor for `ModelStorageMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelStorageMetricsDescriptor = $convert.base64Decode(
    'ChNNb2RlbFN0b3JhZ2VNZXRyaWNzEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEisKEnNpem'
    'Vfb25fZGlza19ieXRlcxgCIAEoA1IPc2l6ZU9uRGlza0J5dGVzEiUKDGxhc3RfdXNlZF9tcxgD'
    'IAEoA0gAUgpsYXN0VXNlZE1ziAEBQg8KDV9sYXN0X3VzZWRfbXM=');

@$core.Deprecated('Use storageInfoDescriptor instead')
const StorageInfo$json = {
  '1': 'StorageInfo',
  '2': [
    {'1': 'app', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.AppStorageInfo', '10': 'app'},
    {'1': 'device', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.DeviceStorageInfo', '10': 'device'},
    {'1': 'models', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelStorageMetrics', '10': 'models'},
    {'1': 'total_models', '3': 4, '4': 1, '5': 5, '10': 'totalModels'},
    {'1': 'total_models_bytes', '3': 5, '4': 1, '5': 3, '10': 'totalModelsBytes'},
  ],
};

/// Descriptor for `StorageInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageInfoDescriptor = $convert.base64Decode(
    'CgtTdG9yYWdlSW5mbxIwCgNhcHAYASABKAsyHi5ydW5hbnl3aGVyZS52MS5BcHBTdG9yYWdlSW'
    '5mb1IDYXBwEjkKBmRldmljZRgCIAEoCzIhLnJ1bmFueXdoZXJlLnYxLkRldmljZVN0b3JhZ2VJ'
    'bmZvUgZkZXZpY2USOwoGbW9kZWxzGAMgAygLMiMucnVuYW55d2hlcmUudjEuTW9kZWxTdG9yYW'
    'dlTWV0cmljc1IGbW9kZWxzEiEKDHRvdGFsX21vZGVscxgEIAEoBVILdG90YWxNb2RlbHMSLAoS'
    'dG90YWxfbW9kZWxzX2J5dGVzGAUgASgDUhB0b3RhbE1vZGVsc0J5dGVz');

@$core.Deprecated('Use storageAvailabilityDescriptor instead')
const StorageAvailability$json = {
  '1': 'StorageAvailability',
  '2': [
    {'1': 'is_available', '3': 1, '4': 1, '5': 8, '10': 'isAvailable'},
    {'1': 'required_bytes', '3': 2, '4': 1, '5': 3, '10': 'requiredBytes'},
    {'1': 'available_bytes', '3': 3, '4': 1, '5': 3, '10': 'availableBytes'},
    {'1': 'warning_message', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'warningMessage', '17': true},
    {'1': 'recommendation', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'recommendation', '17': true},
  ],
  '8': [
    {'1': '_warning_message'},
    {'1': '_recommendation'},
  ],
};

/// Descriptor for `StorageAvailability`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageAvailabilityDescriptor = $convert.base64Decode(
    'ChNTdG9yYWdlQXZhaWxhYmlsaXR5EiEKDGlzX2F2YWlsYWJsZRgBIAEoCFILaXNBdmFpbGFibG'
    'USJQoOcmVxdWlyZWRfYnl0ZXMYAiABKANSDXJlcXVpcmVkQnl0ZXMSJwoPYXZhaWxhYmxlX2J5'
    'dGVzGAMgASgDUg5hdmFpbGFibGVCeXRlcxIsCg93YXJuaW5nX21lc3NhZ2UYBCABKAlIAFIOd2'
    'FybmluZ01lc3NhZ2WIAQESKwoOcmVjb21tZW5kYXRpb24YBSABKAlIAVIOcmVjb21tZW5kYXRp'
    'b26IAQFCEgoQX3dhcm5pbmdfbWVzc2FnZUIRCg9fcmVjb21tZW5kYXRpb24=');

@$core.Deprecated('Use storedModelDescriptor instead')
const StoredModel$json = {
  '1': 'StoredModel',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'size_bytes', '3': 3, '4': 1, '5': 3, '10': 'sizeBytes'},
    {'1': 'local_path', '3': 4, '4': 1, '5': 9, '10': 'localPath'},
    {'1': 'downloaded_at_ms', '3': 5, '4': 1, '5': 3, '9': 0, '10': 'downloadedAtMs', '17': true},
  ],
  '8': [
    {'1': '_downloaded_at_ms'},
  ],
};

/// Descriptor for `StoredModel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storedModelDescriptor = $convert.base64Decode(
    'CgtTdG9yZWRNb2RlbBIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBISCgRuYW1lGAIgASgJUg'
    'RuYW1lEh0KCnNpemVfYnl0ZXMYAyABKANSCXNpemVCeXRlcxIdCgpsb2NhbF9wYXRoGAQgASgJ'
    'Uglsb2NhbFBhdGgSLQoQZG93bmxvYWRlZF9hdF9tcxgFIAEoA0gAUg5kb3dubG9hZGVkQXRNc4'
    'gBAUITChFfZG93bmxvYWRlZF9hdF9tcw==');

@$core.Deprecated('Use storageInfoRequestDescriptor instead')
const StorageInfoRequest$json = {
  '1': 'StorageInfoRequest',
  '2': [
    {'1': 'include_device', '3': 1, '4': 1, '5': 8, '10': 'includeDevice'},
    {'1': 'include_app', '3': 2, '4': 1, '5': 8, '10': 'includeApp'},
    {'1': 'include_models', '3': 3, '4': 1, '5': 8, '10': 'includeModels'},
  ],
};

/// Descriptor for `StorageInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageInfoRequestDescriptor = $convert.base64Decode(
    'ChJTdG9yYWdlSW5mb1JlcXVlc3QSJQoOaW5jbHVkZV9kZXZpY2UYASABKAhSDWluY2x1ZGVEZX'
    'ZpY2USHwoLaW5jbHVkZV9hcHAYAiABKAhSCmluY2x1ZGVBcHASJQoOaW5jbHVkZV9tb2RlbHMY'
    'AyABKAhSDWluY2x1ZGVNb2RlbHM=');

@$core.Deprecated('Use storageInfoResultDescriptor instead')
const StorageInfoResult$json = {
  '1': 'StorageInfoResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'info', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.StorageInfo', '10': 'info'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `StorageInfoResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageInfoResultDescriptor = $convert.base64Decode(
    'ChFTdG9yYWdlSW5mb1Jlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEi8KBGluZm8YAi'
    'ABKAsyGy5ydW5hbnl3aGVyZS52MS5TdG9yYWdlSW5mb1IEaW5mbxIjCg1lcnJvcl9tZXNzYWdl'
    'GAMgASgJUgxlcnJvck1lc3NhZ2U=');

@$core.Deprecated('Use storageAvailabilityRequestDescriptor instead')
const StorageAvailabilityRequest$json = {
  '1': 'StorageAvailabilityRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'required_bytes', '3': 2, '4': 1, '5': 3, '10': 'requiredBytes'},
    {'1': 'safety_margin', '3': 3, '4': 1, '5': 1, '10': 'safetyMargin'},
    {'1': 'include_existing_model_bytes', '3': 4, '4': 1, '5': 8, '10': 'includeExistingModelBytes'},
  ],
};

/// Descriptor for `StorageAvailabilityRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageAvailabilityRequestDescriptor = $convert.base64Decode(
    'ChpTdG9yYWdlQXZhaWxhYmlsaXR5UmVxdWVzdBIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZB'
    'IlCg5yZXF1aXJlZF9ieXRlcxgCIAEoA1INcmVxdWlyZWRCeXRlcxIjCg1zYWZldHlfbWFyZ2lu'
    'GAMgASgBUgxzYWZldHlNYXJnaW4SPwocaW5jbHVkZV9leGlzdGluZ19tb2RlbF9ieXRlcxgEIA'
    'EoCFIZaW5jbHVkZUV4aXN0aW5nTW9kZWxCeXRlcw==');

@$core.Deprecated('Use storageAvailabilityResultDescriptor instead')
const StorageAvailabilityResult$json = {
  '1': 'StorageAvailabilityResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'availability', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.StorageAvailability', '10': 'availability'},
    {'1': 'warnings', '3': 3, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 4, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `StorageAvailabilityResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageAvailabilityResultDescriptor = $convert.base64Decode(
    'ChlTdG9yYWdlQXZhaWxhYmlsaXR5UmVzdWx0EhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3MSRw'
    'oMYXZhaWxhYmlsaXR5GAIgASgLMiMucnVuYW55d2hlcmUudjEuU3RvcmFnZUF2YWlsYWJpbGl0'
    'eVIMYXZhaWxhYmlsaXR5EhoKCHdhcm5pbmdzGAMgAygJUgh3YXJuaW5ncxIjCg1lcnJvcl9tZX'
    'NzYWdlGAQgASgJUgxlcnJvck1lc3NhZ2U=');

@$core.Deprecated('Use storageDeletePlanRequestDescriptor instead')
const StorageDeletePlanRequest$json = {
  '1': 'StorageDeletePlanRequest',
  '2': [
    {'1': 'model_ids', '3': 1, '4': 3, '5': 9, '10': 'modelIds'},
    {'1': 'required_bytes', '3': 2, '4': 1, '5': 3, '10': 'requiredBytes'},
    {'1': 'include_cache', '3': 3, '4': 1, '5': 8, '10': 'includeCache'},
    {'1': 'oldest_first', '3': 4, '4': 1, '5': 8, '10': 'oldestFirst'},
  ],
};

/// Descriptor for `StorageDeletePlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageDeletePlanRequestDescriptor = $convert.base64Decode(
    'ChhTdG9yYWdlRGVsZXRlUGxhblJlcXVlc3QSGwoJbW9kZWxfaWRzGAEgAygJUghtb2RlbElkcx'
    'IlCg5yZXF1aXJlZF9ieXRlcxgCIAEoA1INcmVxdWlyZWRCeXRlcxIjCg1pbmNsdWRlX2NhY2hl'
    'GAMgASgIUgxpbmNsdWRlQ2FjaGUSIQoMb2xkZXN0X2ZpcnN0GAQgASgIUgtvbGRlc3RGaXJzdA'
    '==');

@$core.Deprecated('Use storageDeleteCandidateDescriptor instead')
const StorageDeleteCandidate$json = {
  '1': 'StorageDeleteCandidate',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'reclaimable_bytes', '3': 2, '4': 1, '5': 3, '10': 'reclaimableBytes'},
    {'1': 'last_used_ms', '3': 3, '4': 1, '5': 3, '9': 0, '10': 'lastUsedMs', '17': true},
    {'1': 'is_loaded', '3': 4, '4': 1, '5': 8, '10': 'isLoaded'},
    {'1': 'local_path', '3': 5, '4': 1, '5': 9, '10': 'localPath'},
  ],
  '8': [
    {'1': '_last_used_ms'},
  ],
};

/// Descriptor for `StorageDeleteCandidate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageDeleteCandidateDescriptor = $convert.base64Decode(
    'ChZTdG9yYWdlRGVsZXRlQ2FuZGlkYXRlEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEisKEX'
    'JlY2xhaW1hYmxlX2J5dGVzGAIgASgDUhByZWNsYWltYWJsZUJ5dGVzEiUKDGxhc3RfdXNlZF9t'
    'cxgDIAEoA0gAUgpsYXN0VXNlZE1ziAEBEhsKCWlzX2xvYWRlZBgEIAEoCFIIaXNMb2FkZWQSHQ'
    'oKbG9jYWxfcGF0aBgFIAEoCVIJbG9jYWxQYXRoQg8KDV9sYXN0X3VzZWRfbXM=');

@$core.Deprecated('Use storageDeletePlanDescriptor instead')
const StorageDeletePlan$json = {
  '1': 'StorageDeletePlan',
  '2': [
    {'1': 'can_reclaim_required_bytes', '3': 1, '4': 1, '5': 8, '10': 'canReclaimRequiredBytes'},
    {'1': 'required_bytes', '3': 2, '4': 1, '5': 3, '10': 'requiredBytes'},
    {'1': 'reclaimable_bytes', '3': 3, '4': 1, '5': 3, '10': 'reclaimableBytes'},
    {'1': 'candidates', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.StorageDeleteCandidate', '10': 'candidates'},
    {'1': 'warnings', '3': 5, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `StorageDeletePlan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageDeletePlanDescriptor = $convert.base64Decode(
    'ChFTdG9yYWdlRGVsZXRlUGxhbhI7ChpjYW5fcmVjbGFpbV9yZXF1aXJlZF9ieXRlcxgBIAEoCF'
    'IXY2FuUmVjbGFpbVJlcXVpcmVkQnl0ZXMSJQoOcmVxdWlyZWRfYnl0ZXMYAiABKANSDXJlcXVp'
    'cmVkQnl0ZXMSKwoRcmVjbGFpbWFibGVfYnl0ZXMYAyABKANSEHJlY2xhaW1hYmxlQnl0ZXMSRg'
    'oKY2FuZGlkYXRlcxgEIAMoCzImLnJ1bmFueXdoZXJlLnYxLlN0b3JhZ2VEZWxldGVDYW5kaWRh'
    'dGVSCmNhbmRpZGF0ZXMSGgoId2FybmluZ3MYBSADKAlSCHdhcm5pbmdzEiMKDWVycm9yX21lc3'
    'NhZ2UYBiABKAlSDGVycm9yTWVzc2FnZQ==');

@$core.Deprecated('Use storageDeleteRequestDescriptor instead')
const StorageDeleteRequest$json = {
  '1': 'StorageDeleteRequest',
  '2': [
    {'1': 'model_ids', '3': 1, '4': 3, '5': 9, '10': 'modelIds'},
    {'1': 'delete_files', '3': 2, '4': 1, '5': 8, '10': 'deleteFiles'},
    {'1': 'clear_registry_paths', '3': 3, '4': 1, '5': 8, '10': 'clearRegistryPaths'},
    {'1': 'unload_if_loaded', '3': 4, '4': 1, '5': 8, '10': 'unloadIfLoaded'},
    {'1': 'dry_run', '3': 5, '4': 1, '5': 8, '10': 'dryRun'},
  ],
};

/// Descriptor for `StorageDeleteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageDeleteRequestDescriptor = $convert.base64Decode(
    'ChRTdG9yYWdlRGVsZXRlUmVxdWVzdBIbCgltb2RlbF9pZHMYASADKAlSCG1vZGVsSWRzEiEKDG'
    'RlbGV0ZV9maWxlcxgCIAEoCFILZGVsZXRlRmlsZXMSMAoUY2xlYXJfcmVnaXN0cnlfcGF0aHMY'
    'AyABKAhSEmNsZWFyUmVnaXN0cnlQYXRocxIoChB1bmxvYWRfaWZfbG9hZGVkGAQgASgIUg51bm'
    'xvYWRJZkxvYWRlZBIXCgdkcnlfcnVuGAUgASgIUgZkcnlSdW4=');

@$core.Deprecated('Use storageDeleteResultDescriptor instead')
const StorageDeleteResult$json = {
  '1': 'StorageDeleteResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'deleted_bytes', '3': 2, '4': 1, '5': 3, '10': 'deletedBytes'},
    {'1': 'deleted_model_ids', '3': 3, '4': 3, '5': 9, '10': 'deletedModelIds'},
    {'1': 'failed_model_ids', '3': 4, '4': 3, '5': 9, '10': 'failedModelIds'},
    {'1': 'warnings', '3': 5, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `StorageDeleteResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageDeleteResultDescriptor = $convert.base64Decode(
    'ChNTdG9yYWdlRGVsZXRlUmVzdWx0EhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3MSIwoNZGVsZX'
    'RlZF9ieXRlcxgCIAEoA1IMZGVsZXRlZEJ5dGVzEioKEWRlbGV0ZWRfbW9kZWxfaWRzGAMgAygJ'
    'Ug9kZWxldGVkTW9kZWxJZHMSKAoQZmFpbGVkX21vZGVsX2lkcxgEIAMoCVIOZmFpbGVkTW9kZW'
    'xJZHMSGgoId2FybmluZ3MYBSADKAlSCHdhcm5pbmdzEiMKDWVycm9yX21lc3NhZ2UYBiABKAlS'
    'DGVycm9yTWVzc2FnZQ==');

