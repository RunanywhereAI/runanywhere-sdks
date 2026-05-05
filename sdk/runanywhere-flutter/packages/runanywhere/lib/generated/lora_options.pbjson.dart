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
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.LoRAAdapterConfig.MetadataEntry', '10': 'metadata'},
    {'1': 'target_modules', '3': 5, '4': 3, '5': 9, '10': 'targetModules'},
  ],
  '3': [LoRAAdapterConfig_MetadataEntry$json],
  '8': [
    {'1': '_adapter_id'},
  ],
};

@$core.Deprecated('Use loRAAdapterConfigDescriptor instead')
const LoRAAdapterConfig_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `LoRAAdapterConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAAdapterConfigDescriptor = $convert.base64Decode(
    'ChFMb1JBQWRhcHRlckNvbmZpZxIhCgxhZGFwdGVyX3BhdGgYASABKAlSC2FkYXB0ZXJQYXRoEh'
    'QKBXNjYWxlGAIgASgCUgVzY2FsZRIiCgphZGFwdGVyX2lkGAMgASgJSABSCWFkYXB0ZXJJZIgB'
    'ARJLCghtZXRhZGF0YRgEIAMoCzIvLnJ1bmFueXdoZXJlLnYxLkxvUkFBZGFwdGVyQ29uZmlnLk'
    '1ldGFkYXRhRW50cnlSCG1ldGFkYXRhEiUKDnRhcmdldF9tb2R1bGVzGAUgAygJUg10YXJnZXRN'
    'b2R1bGVzGjsKDU1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKA'
    'lSBXZhbHVlOgI4AUINCgtfYWRhcHRlcl9pZA==');

@$core.Deprecated('Use loRAAdapterInfoDescriptor instead')
const LoRAAdapterInfo$json = {
  '1': 'LoRAAdapterInfo',
  '2': [
    {'1': 'adapter_id', '3': 1, '4': 1, '5': 9, '10': 'adapterId'},
    {'1': 'adapter_path', '3': 2, '4': 1, '5': 9, '10': 'adapterPath'},
    {'1': 'scale', '3': 3, '4': 1, '5': 2, '10': 'scale'},
    {'1': 'applied', '3': 4, '4': 1, '5': 8, '10': 'applied'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 6, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'loaded_at_ms', '3': 7, '4': 1, '5': 3, '10': 'loadedAtMs'},
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
    'NhZ2WIAQESHQoKZXJyb3JfY29kZRgGIAEoBVIJZXJyb3JDb2RlEiAKDGxvYWRlZF9hdF9tcxgH'
    'IAEoA1IKbG9hZGVkQXRNc0IQCg5fZXJyb3JfbWVzc2FnZQ==');

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
    {'1': 'license', '3': 11, '4': 1, '5': 9, '9': 2, '10': 'license', '17': true},
    {'1': 'tags', '3': 12, '4': 3, '5': 9, '10': 'tags'},
    {'1': 'metadata', '3': 13, '4': 3, '5': 11, '6': '.runanywhere.v1.LoraAdapterCatalogEntry.MetadataEntry', '10': 'metadata'},
    {'1': 'local_path', '3': 14, '4': 1, '5': 9, '9': 3, '10': 'localPath', '17': true},
    {'1': 'is_downloaded', '3': 15, '4': 1, '5': 8, '9': 4, '10': 'isDownloaded', '17': true},
    {'1': 'downloaded_at_unix_ms', '3': 16, '4': 1, '5': 3, '9': 5, '10': 'downloadedAtUnixMs', '17': true},
    {'1': 'is_imported', '3': 17, '4': 1, '5': 8, '9': 6, '10': 'isImported', '17': true},
    {'1': 'status_message', '3': 18, '4': 1, '5': 9, '9': 7, '10': 'statusMessage', '17': true},
  ],
  '3': [LoraAdapterCatalogEntry_MetadataEntry$json],
  '8': [
    {'1': '_author'},
    {'1': '_checksum_sha256'},
    {'1': '_license'},
    {'1': '_local_path'},
    {'1': '_is_downloaded'},
    {'1': '_downloaded_at_unix_ms'},
    {'1': '_is_imported'},
    {'1': '_status_message'},
  ],
};

@$core.Deprecated('Use loraAdapterCatalogEntryDescriptor instead')
const LoraAdapterCatalogEntry_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `LoraAdapterCatalogEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogEntryDescriptor = $convert.base64Decode(
    'ChdMb3JhQWRhcHRlckNhdGFsb2dFbnRyeRIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCV'
    'IEbmFtZRIgCgtkZXNjcmlwdGlvbhgDIAEoCVILZGVzY3JpcHRpb24SEAoDdXJsGAQgASgJUgN1'
    'cmwSGgoIZmlsZW5hbWUYBSABKAlSCGZpbGVuYW1lEisKEWNvbXBhdGlibGVfbW9kZWxzGAYgAy'
    'gJUhBjb21wYXRpYmxlTW9kZWxzEh0KCnNpemVfYnl0ZXMYByABKANSCXNpemVCeXRlcxIbCgZh'
    'dXRob3IYCCABKAlIAFIGYXV0aG9yiAEBEiMKDWRlZmF1bHRfc2NhbGUYCSABKAJSDGRlZmF1bH'
    'RTY2FsZRIsCg9jaGVja3N1bV9zaGEyNTYYCiABKAlIAVIOY2hlY2tzdW1TaGEyNTaIAQESHQoH'
    'bGljZW5zZRgLIAEoCUgCUgdsaWNlbnNliAEBEhIKBHRhZ3MYDCADKAlSBHRhZ3MSUQoIbWV0YW'
    'RhdGEYDSADKAsyNS5ydW5hbnl3aGVyZS52MS5Mb3JhQWRhcHRlckNhdGFsb2dFbnRyeS5NZXRh'
    'ZGF0YUVudHJ5UghtZXRhZGF0YRIiCgpsb2NhbF9wYXRoGA4gASgJSANSCWxvY2FsUGF0aIgBAR'
    'IoCg1pc19kb3dubG9hZGVkGA8gASgISARSDGlzRG93bmxvYWRlZIgBARI2ChVkb3dubG9hZGVk'
    'X2F0X3VuaXhfbXMYECABKANIBVISZG93bmxvYWRlZEF0VW5peE1ziAEBEiQKC2lzX2ltcG9ydG'
    'VkGBEgASgISAZSCmlzSW1wb3J0ZWSIAQESKgoOc3RhdHVzX21lc3NhZ2UYEiABKAlIB1INc3Rh'
    'dHVzTWVzc2FnZYgBARo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbH'
    'VlGAIgASgJUgV2YWx1ZToCOAFCCQoHX2F1dGhvckISChBfY2hlY2tzdW1fc2hhMjU2QgoKCF9s'
    'aWNlbnNlQg0KC19sb2NhbF9wYXRoQhAKDl9pc19kb3dubG9hZGVkQhgKFl9kb3dubG9hZGVkX2'
    'F0X3VuaXhfbXNCDgoMX2lzX2ltcG9ydGVkQhEKD19zdGF0dXNfbWVzc2FnZQ==');

@$core.Deprecated('Use loraAdapterCatalogQueryDescriptor instead')
const LoraAdapterCatalogQuery$json = {
  '1': 'LoraAdapterCatalogQuery',
  '2': [
    {'1': 'adapter_id', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'adapterId', '17': true},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'modelId', '17': true},
    {'1': 'downloaded_only', '3': 3, '4': 1, '5': 8, '9': 2, '10': 'downloadedOnly', '17': true},
    {'1': 'search_query', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'searchQuery', '17': true},
    {'1': 'tags', '3': 5, '4': 3, '5': 9, '10': 'tags'},
  ],
  '8': [
    {'1': '_adapter_id'},
    {'1': '_model_id'},
    {'1': '_downloaded_only'},
    {'1': '_search_query'},
  ],
};

/// Descriptor for `LoraAdapterCatalogQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogQueryDescriptor = $convert.base64Decode(
    'ChdMb3JhQWRhcHRlckNhdGFsb2dRdWVyeRIiCgphZGFwdGVyX2lkGAEgASgJSABSCWFkYXB0ZX'
    'JJZIgBARIeCghtb2RlbF9pZBgCIAEoCUgBUgdtb2RlbElkiAEBEiwKD2Rvd25sb2FkZWRfb25s'
    'eRgDIAEoCEgCUg5kb3dubG9hZGVkT25seYgBARImCgxzZWFyY2hfcXVlcnkYBCABKAlIA1ILc2'
    'VhcmNoUXVlcnmIAQESEgoEdGFncxgFIAMoCVIEdGFnc0INCgtfYWRhcHRlcl9pZEILCglfbW9k'
    'ZWxfaWRCEgoQX2Rvd25sb2FkZWRfb25seUIPCg1fc2VhcmNoX3F1ZXJ5');

@$core.Deprecated('Use loraAdapterCatalogListRequestDescriptor instead')
const LoraAdapterCatalogListRequest$json = {
  '1': 'LoraAdapterCatalogListRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.LoraAdapterCatalogQuery', '9': 0, '10': 'query', '17': true},
    {'1': 'include_counts', '3': 2, '4': 1, '5': 8, '10': 'includeCounts'},
  ],
  '8': [
    {'1': '_query'},
  ],
};

/// Descriptor for `LoraAdapterCatalogListRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogListRequestDescriptor = $convert.base64Decode(
    'Ch1Mb3JhQWRhcHRlckNhdGFsb2dMaXN0UmVxdWVzdBJCCgVxdWVyeRgBIAEoCzInLnJ1bmFueX'
    'doZXJlLnYxLkxvcmFBZGFwdGVyQ2F0YWxvZ1F1ZXJ5SABSBXF1ZXJ5iAEBEiUKDmluY2x1ZGVf'
    'Y291bnRzGAIgASgIUg1pbmNsdWRlQ291bnRzQggKBl9xdWVyeQ==');

@$core.Deprecated('Use loraAdapterCatalogListResultDescriptor instead')
const LoraAdapterCatalogListResult$json = {
  '1': 'LoraAdapterCatalogListResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'entries', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.LoraAdapterCatalogEntry', '10': 'entries'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'total_count', '3': 4, '4': 1, '5': 5, '10': 'totalCount'},
    {'1': 'filtered_count', '3': 5, '4': 1, '5': 5, '10': 'filteredCount'},
    {'1': 'downloaded_count', '3': 6, '4': 1, '5': 5, '10': 'downloadedCount'},
  ],
};

/// Descriptor for `LoraAdapterCatalogListResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogListResultDescriptor = $convert.base64Decode(
    'ChxMb3JhQWRhcHRlckNhdGFsb2dMaXN0UmVzdWx0EhgKB3N1Y2Nlc3MYASABKAhSB3N1Y2Nlc3'
    'MSQQoHZW50cmllcxgCIAMoCzInLnJ1bmFueXdoZXJlLnYxLkxvcmFBZGFwdGVyQ2F0YWxvZ0Vu'
    'dHJ5UgdlbnRyaWVzEiMKDWVycm9yX21lc3NhZ2UYAyABKAlSDGVycm9yTWVzc2FnZRIfCgt0b3'
    'RhbF9jb3VudBgEIAEoBVIKdG90YWxDb3VudBIlCg5maWx0ZXJlZF9jb3VudBgFIAEoBVINZmls'
    'dGVyZWRDb3VudBIpChBkb3dubG9hZGVkX2NvdW50GAYgASgFUg9kb3dubG9hZGVkQ291bnQ=');

@$core.Deprecated('Use loraAdapterCatalogGetRequestDescriptor instead')
const LoraAdapterCatalogGetRequest$json = {
  '1': 'LoraAdapterCatalogGetRequest',
  '2': [
    {'1': 'adapter_id', '3': 1, '4': 1, '5': 9, '10': 'adapterId'},
  ],
};

/// Descriptor for `LoraAdapterCatalogGetRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogGetRequestDescriptor = $convert.base64Decode(
    'ChxMb3JhQWRhcHRlckNhdGFsb2dHZXRSZXF1ZXN0Eh0KCmFkYXB0ZXJfaWQYASABKAlSCWFkYX'
    'B0ZXJJZA==');

@$core.Deprecated('Use loraAdapterCatalogGetResultDescriptor instead')
const LoraAdapterCatalogGetResult$json = {
  '1': 'LoraAdapterCatalogGetResult',
  '2': [
    {'1': 'found', '3': 1, '4': 1, '5': 8, '10': 'found'},
    {'1': 'entry', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.LoraAdapterCatalogEntry', '10': 'entry'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `LoraAdapterCatalogGetResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterCatalogGetResultDescriptor = $convert.base64Decode(
    'ChtMb3JhQWRhcHRlckNhdGFsb2dHZXRSZXN1bHQSFAoFZm91bmQYASABKAhSBWZvdW5kEj0KBW'
    'VudHJ5GAIgASgLMicucnVuYW55d2hlcmUudjEuTG9yYUFkYXB0ZXJDYXRhbG9nRW50cnlSBWVu'
    'dHJ5EiMKDWVycm9yX21lc3NhZ2UYAyABKAlSDGVycm9yTWVzc2FnZQ==');

@$core.Deprecated('Use loraAdapterDownloadCompletedRequestDescriptor instead')
const LoraAdapterDownloadCompletedRequest$json = {
  '1': 'LoraAdapterDownloadCompletedRequest',
  '2': [
    {'1': 'adapter_id', '3': 1, '4': 1, '5': 9, '10': 'adapterId'},
    {'1': 'local_path', '3': 2, '4': 1, '5': 9, '10': 'localPath'},
    {'1': 'size_bytes', '3': 3, '4': 1, '5': 3, '9': 0, '10': 'sizeBytes', '17': true},
    {'1': 'checksum_sha256', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'checksumSha256', '17': true},
    {'1': 'completed_at_unix_ms', '3': 5, '4': 1, '5': 3, '9': 2, '10': 'completedAtUnixMs', '17': true},
    {'1': 'imported', '3': 6, '4': 1, '5': 8, '10': 'imported'},
    {'1': 'status_message', '3': 7, '4': 1, '5': 9, '10': 'statusMessage'},
  ],
  '8': [
    {'1': '_size_bytes'},
    {'1': '_checksum_sha256'},
    {'1': '_completed_at_unix_ms'},
  ],
};

/// Descriptor for `LoraAdapterDownloadCompletedRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterDownloadCompletedRequestDescriptor = $convert.base64Decode(
    'CiNMb3JhQWRhcHRlckRvd25sb2FkQ29tcGxldGVkUmVxdWVzdBIdCgphZGFwdGVyX2lkGAEgAS'
    'gJUglhZGFwdGVySWQSHQoKbG9jYWxfcGF0aBgCIAEoCVIJbG9jYWxQYXRoEiIKCnNpemVfYnl0'
    'ZXMYAyABKANIAFIJc2l6ZUJ5dGVziAEBEiwKD2NoZWNrc3VtX3NoYTI1NhgEIAEoCUgBUg5jaG'
    'Vja3N1bVNoYTI1NogBARI0ChRjb21wbGV0ZWRfYXRfdW5peF9tcxgFIAEoA0gCUhFjb21wbGV0'
    'ZWRBdFVuaXhNc4gBARIaCghpbXBvcnRlZBgGIAEoCFIIaW1wb3J0ZWQSJQoOc3RhdHVzX21lc3'
    'NhZ2UYByABKAlSDXN0YXR1c01lc3NhZ2VCDQoLX3NpemVfYnl0ZXNCEgoQX2NoZWNrc3VtX3No'
    'YTI1NkIXChVfY29tcGxldGVkX2F0X3VuaXhfbXM=');

@$core.Deprecated('Use loraAdapterDownloadCompletedResultDescriptor instead')
const LoraAdapterDownloadCompletedResult$json = {
  '1': 'LoraAdapterDownloadCompletedResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'entry', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.LoraAdapterCatalogEntry', '10': 'entry'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'persisted', '3': 4, '4': 1, '5': 8, '10': 'persisted'},
  ],
};

/// Descriptor for `LoraAdapterDownloadCompletedResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loraAdapterDownloadCompletedResultDescriptor = $convert.base64Decode(
    'CiJMb3JhQWRhcHRlckRvd25sb2FkQ29tcGxldGVkUmVzdWx0EhgKB3N1Y2Nlc3MYASABKAhSB3'
    'N1Y2Nlc3MSPQoFZW50cnkYAiABKAsyJy5ydW5hbnl3aGVyZS52MS5Mb3JhQWRhcHRlckNhdGFs'
    'b2dFbnRyeVIFZW50cnkSIwoNZXJyb3JfbWVzc2FnZRgDIAEoCVIMZXJyb3JNZXNzYWdlEhwKCX'
    'BlcnNpc3RlZBgEIAEoCFIJcGVyc2lzdGVk');

@$core.Deprecated('Use loraCompatibilityResultDescriptor instead')
const LoraCompatibilityResult$json = {
  '1': 'LoraCompatibilityResult',
  '2': [
    {'1': 'is_compatible', '3': 1, '4': 1, '5': 8, '10': 'isCompatible'},
    {'1': 'error_message', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'base_model_required', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'baseModelRequired', '17': true},
    {'1': 'warnings', '3': 4, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
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
    'ZV9tb2RlbF9yZXF1aXJlZBgDIAEoCUgBUhFiYXNlTW9kZWxSZXF1aXJlZIgBARIaCgh3YXJuaW'
    '5ncxgEIAMoCVIId2FybmluZ3MSHQoKZXJyb3JfY29kZRgFIAEoBVIJZXJyb3JDb2RlQhAKDl9l'
    'cnJvcl9tZXNzYWdlQhYKFF9iYXNlX21vZGVsX3JlcXVpcmVk');

@$core.Deprecated('Use loRAApplyRequestDescriptor instead')
const LoRAApplyRequest$json = {
  '1': 'LoRAApplyRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'adapters', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.LoRAAdapterConfig', '10': 'adapters'},
    {'1': 'replace_existing', '3': 3, '4': 1, '5': 8, '10': 'replaceExisting'},
  ],
};

/// Descriptor for `LoRAApplyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAApplyRequestDescriptor = $convert.base64Decode(
    'ChBMb1JBQXBwbHlSZXF1ZXN0Eh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcXVlc3RJZBI9CghhZG'
    'FwdGVycxgCIAMoCzIhLnJ1bmFueXdoZXJlLnYxLkxvUkFBZGFwdGVyQ29uZmlnUghhZGFwdGVy'
    'cxIpChByZXBsYWNlX2V4aXN0aW5nGAMgASgIUg9yZXBsYWNlRXhpc3Rpbmc=');

@$core.Deprecated('Use loRAApplyResultDescriptor instead')
const LoRAApplyResult$json = {
  '1': 'LoRAApplyResult',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'adapters', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.LoRAAdapterInfo', '10': 'adapters'},
    {'1': 'success', '3': 3, '4': 1, '5': 8, '10': 'success'},
    {'1': 'error_message', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `LoRAApplyResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAApplyResultDescriptor = $convert.base64Decode(
    'Cg9Mb1JBQXBwbHlSZXN1bHQSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEjsKCGFkYX'
    'B0ZXJzGAIgAygLMh8ucnVuYW55d2hlcmUudjEuTG9SQUFkYXB0ZXJJbmZvUghhZGFwdGVycxIY'
    'CgdzdWNjZXNzGAMgASgIUgdzdWNjZXNzEigKDWVycm9yX21lc3NhZ2UYBCABKAlIAFIMZXJyb3'
    'JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYBSABKAVSCWVycm9yQ29kZUIQCg5fZXJyb3JfbWVz'
    'c2FnZQ==');

@$core.Deprecated('Use loRARemoveRequestDescriptor instead')
const LoRARemoveRequest$json = {
  '1': 'LoRARemoveRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'adapter_ids', '3': 2, '4': 3, '5': 9, '10': 'adapterIds'},
    {'1': 'adapter_paths', '3': 3, '4': 3, '5': 9, '10': 'adapterPaths'},
    {'1': 'clear_all', '3': 4, '4': 1, '5': 8, '10': 'clearAll'},
  ],
};

/// Descriptor for `LoRARemoveRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRARemoveRequestDescriptor = $convert.base64Decode(
    'ChFMb1JBUmVtb3ZlUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSHwoLYW'
    'RhcHRlcl9pZHMYAiADKAlSCmFkYXB0ZXJJZHMSIwoNYWRhcHRlcl9wYXRocxgDIAMoCVIMYWRh'
    'cHRlclBhdGhzEhsKCWNsZWFyX2FsbBgEIAEoCFIIY2xlYXJBbGw=');

@$core.Deprecated('Use loRAStateDescriptor instead')
const LoRAState$json = {
  '1': 'LoRAState',
  '2': [
    {'1': 'loaded_adapters', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.LoRAAdapterInfo', '10': 'loadedAdapters'},
    {'1': 'has_active_adapters', '3': 2, '4': 1, '5': 8, '10': 'hasActiveAdapters'},
    {'1': 'base_model_id', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'baseModelId', '17': true},
    {'1': 'error_message', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_base_model_id'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `LoRAState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loRAStateDescriptor = $convert.base64Decode(
    'CglMb1JBU3RhdGUSSAoPbG9hZGVkX2FkYXB0ZXJzGAEgAygLMh8ucnVuYW55d2hlcmUudjEuTG'
    '9SQUFkYXB0ZXJJbmZvUg5sb2FkZWRBZGFwdGVycxIuChNoYXNfYWN0aXZlX2FkYXB0ZXJzGAIg'
    'ASgIUhFoYXNBY3RpdmVBZGFwdGVycxInCg1iYXNlX21vZGVsX2lkGAMgASgJSABSC2Jhc2VNb2'
    'RlbElkiAEBEigKDWVycm9yX21lc3NhZ2UYBCABKAlIAVIMZXJyb3JNZXNzYWdliAEBEh0KCmVy'
    'cm9yX2NvZGUYBSABKAVSCWVycm9yQ29kZUIQCg5fYmFzZV9tb2RlbF9pZEIQCg5fZXJyb3JfbW'
    'Vzc2FnZQ==');

const $core.Map<$core.String, $core.dynamic> LoRAServiceBase$json = {
  '1': 'LoRA',
  '2': [
    {'1': 'RegisterCatalogEntry', '2': '.runanywhere.v1.LoraAdapterCatalogEntry', '3': '.runanywhere.v1.LoraAdapterCatalogEntry'},
    {'1': 'ListCatalog', '2': '.runanywhere.v1.LoraAdapterCatalogListRequest', '3': '.runanywhere.v1.LoraAdapterCatalogListResult'},
    {'1': 'QueryCatalog', '2': '.runanywhere.v1.LoraAdapterCatalogQuery', '3': '.runanywhere.v1.LoraAdapterCatalogListResult'},
    {'1': 'GetCatalogEntry', '2': '.runanywhere.v1.LoraAdapterCatalogGetRequest', '3': '.runanywhere.v1.LoraAdapterCatalogGetResult'},
    {'1': 'MarkDownloadCompleted', '2': '.runanywhere.v1.LoraAdapterDownloadCompletedRequest', '3': '.runanywhere.v1.LoraAdapterDownloadCompletedResult'},
    {'1': 'Apply', '2': '.runanywhere.v1.LoRAApplyRequest', '3': '.runanywhere.v1.LoRAApplyResult'},
    {'1': 'Remove', '2': '.runanywhere.v1.LoRARemoveRequest', '3': '.runanywhere.v1.LoRAState'},
    {'1': 'CheckCompatibility', '2': '.runanywhere.v1.LoRAAdapterConfig', '3': '.runanywhere.v1.LoraCompatibilityResult'},
    {'1': 'List', '2': '.runanywhere.v1.LoRAState', '3': '.runanywhere.v1.LoRAState'},
    {'1': 'State', '2': '.runanywhere.v1.LoRAState', '3': '.runanywhere.v1.LoRAState'},
  ],
};

@$core.Deprecated('Use loRAServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> LoRAServiceBase$messageJson = {
  '.runanywhere.v1.LoraAdapterCatalogEntry': LoraAdapterCatalogEntry$json,
  '.runanywhere.v1.LoraAdapterCatalogEntry.MetadataEntry': LoraAdapterCatalogEntry_MetadataEntry$json,
  '.runanywhere.v1.LoraAdapterCatalogListRequest': LoraAdapterCatalogListRequest$json,
  '.runanywhere.v1.LoraAdapterCatalogQuery': LoraAdapterCatalogQuery$json,
  '.runanywhere.v1.LoraAdapterCatalogListResult': LoraAdapterCatalogListResult$json,
  '.runanywhere.v1.LoraAdapterCatalogGetRequest': LoraAdapterCatalogGetRequest$json,
  '.runanywhere.v1.LoraAdapterCatalogGetResult': LoraAdapterCatalogGetResult$json,
  '.runanywhere.v1.LoraAdapterDownloadCompletedRequest': LoraAdapterDownloadCompletedRequest$json,
  '.runanywhere.v1.LoraAdapterDownloadCompletedResult': LoraAdapterDownloadCompletedResult$json,
  '.runanywhere.v1.LoRAApplyRequest': LoRAApplyRequest$json,
  '.runanywhere.v1.LoRAAdapterConfig': LoRAAdapterConfig$json,
  '.runanywhere.v1.LoRAAdapterConfig.MetadataEntry': LoRAAdapterConfig_MetadataEntry$json,
  '.runanywhere.v1.LoRAApplyResult': LoRAApplyResult$json,
  '.runanywhere.v1.LoRAAdapterInfo': LoRAAdapterInfo$json,
  '.runanywhere.v1.LoRARemoveRequest': LoRARemoveRequest$json,
  '.runanywhere.v1.LoRAState': LoRAState$json,
  '.runanywhere.v1.LoraCompatibilityResult': LoraCompatibilityResult$json,
};

/// Descriptor for `LoRA`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List loRAServiceDescriptor = $convert.base64Decode(
    'CgRMb1JBEmgKFFJlZ2lzdGVyQ2F0YWxvZ0VudHJ5EicucnVuYW55d2hlcmUudjEuTG9yYUFkYX'
    'B0ZXJDYXRhbG9nRW50cnkaJy5ydW5hbnl3aGVyZS52MS5Mb3JhQWRhcHRlckNhdGFsb2dFbnRy'
    'eRJqCgtMaXN0Q2F0YWxvZxItLnJ1bmFueXdoZXJlLnYxLkxvcmFBZGFwdGVyQ2F0YWxvZ0xpc3'
    'RSZXF1ZXN0GiwucnVuYW55d2hlcmUudjEuTG9yYUFkYXB0ZXJDYXRhbG9nTGlzdFJlc3VsdBJl'
    'CgxRdWVyeUNhdGFsb2cSJy5ydW5hbnl3aGVyZS52MS5Mb3JhQWRhcHRlckNhdGFsb2dRdWVyeR'
    'osLnJ1bmFueXdoZXJlLnYxLkxvcmFBZGFwdGVyQ2F0YWxvZ0xpc3RSZXN1bHQSbAoPR2V0Q2F0'
    'YWxvZ0VudHJ5EiwucnVuYW55d2hlcmUudjEuTG9yYUFkYXB0ZXJDYXRhbG9nR2V0UmVxdWVzdB'
    'orLnJ1bmFueXdoZXJlLnYxLkxvcmFBZGFwdGVyQ2F0YWxvZ0dldFJlc3VsdBKAAQoVTWFya0Rv'
    'd25sb2FkQ29tcGxldGVkEjMucnVuYW55d2hlcmUudjEuTG9yYUFkYXB0ZXJEb3dubG9hZENvbX'
    'BsZXRlZFJlcXVlc3QaMi5ydW5hbnl3aGVyZS52MS5Mb3JhQWRhcHRlckRvd25sb2FkQ29tcGxl'
    'dGVkUmVzdWx0EkoKBUFwcGx5EiAucnVuYW55d2hlcmUudjEuTG9SQUFwcGx5UmVxdWVzdBofLn'
    'J1bmFueXdoZXJlLnYxLkxvUkFBcHBseVJlc3VsdBJGCgZSZW1vdmUSIS5ydW5hbnl3aGVyZS52'
    'MS5Mb1JBUmVtb3ZlUmVxdWVzdBoZLnJ1bmFueXdoZXJlLnYxLkxvUkFTdGF0ZRJgChJDaGVja0'
    'NvbXBhdGliaWxpdHkSIS5ydW5hbnl3aGVyZS52MS5Mb1JBQWRhcHRlckNvbmZpZxonLnJ1bmFu'
    'eXdoZXJlLnYxLkxvcmFDb21wYXRpYmlsaXR5UmVzdWx0EjwKBExpc3QSGS5ydW5hbnl3aGVyZS'
    '52MS5Mb1JBU3RhdGUaGS5ydW5hbnl3aGVyZS52MS5Mb1JBU3RhdGUSPQoFU3RhdGUSGS5ydW5h'
    'bnl3aGVyZS52MS5Mb1JBU3RhdGUaGS5ydW5hbnl3aGVyZS52MS5Mb1JBU3RhdGU=');

