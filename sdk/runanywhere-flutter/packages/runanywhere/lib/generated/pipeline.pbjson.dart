///
//  Generated code. Do not modify.
//  source: pipeline.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use deviceAffinityDescriptor instead')
const DeviceAffinity$json = const {
  '1': 'DeviceAffinity',
  '2': const [
    const {'1': 'DEVICE_AFFINITY_UNSPECIFIED', '2': 0},
    const {'1': 'DEVICE_AFFINITY_ANY', '2': 1},
    const {'1': 'DEVICE_AFFINITY_CPU', '2': 2},
    const {'1': 'DEVICE_AFFINITY_GPU', '2': 3},
    const {'1': 'DEVICE_AFFINITY_ANE', '2': 4},
  ],
};

/// Descriptor for `DeviceAffinity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List deviceAffinityDescriptor = $convert.base64Decode('Cg5EZXZpY2VBZmZpbml0eRIfChtERVZJQ0VfQUZGSU5JVFlfVU5TUEVDSUZJRUQQABIXChNERVZJQ0VfQUZGSU5JVFlfQU5ZEAESFwoTREVWSUNFX0FGRklOSVRZX0NQVRACEhcKE0RFVklDRV9BRkZJTklUWV9HUFUQAxIXChNERVZJQ0VfQUZGSU5JVFlfQU5FEAQ=');
@$core.Deprecated('Use edgePolicyDescriptor instead')
const EdgePolicy$json = const {
  '1': 'EdgePolicy',
  '2': const [
    const {'1': 'EDGE_POLICY_UNSPECIFIED', '2': 0},
    const {'1': 'EDGE_POLICY_BLOCK', '2': 1},
    const {'1': 'EDGE_POLICY_DROP_OLDEST', '2': 2},
    const {'1': 'EDGE_POLICY_DROP_NEWEST', '2': 3},
  ],
};

/// Descriptor for `EdgePolicy`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List edgePolicyDescriptor = $convert.base64Decode('CgpFZGdlUG9saWN5EhsKF0VER0VfUE9MSUNZX1VOU1BFQ0lGSUVEEAASFQoRRURHRV9QT0xJQ1lfQkxPQ0sQARIbChdFREdFX1BPTElDWV9EUk9QX09MREVTVBACEhsKF0VER0VfUE9MSUNZX0RST1BfTkVXRVNUEAM=');
@$core.Deprecated('Use pipelineSpecDescriptor instead')
const PipelineSpec$json = const {
  '1': 'PipelineSpec',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'operators', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.OperatorSpec', '10': 'operators'},
    const {'1': 'edges', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.EdgeSpec', '10': 'edges'},
    const {'1': 'options', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.PipelineOptions', '10': 'options'},
  ],
};

/// Descriptor for `PipelineSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pipelineSpecDescriptor = $convert.base64Decode('CgxQaXBlbGluZVNwZWMSEgoEbmFtZRgBIAEoCVIEbmFtZRI6CglvcGVyYXRvcnMYAiADKAsyHC5ydW5hbnl3aGVyZS52MS5PcGVyYXRvclNwZWNSCW9wZXJhdG9ycxIuCgVlZGdlcxgDIAMoCzIYLnJ1bmFueXdoZXJlLnYxLkVkZ2VTcGVjUgVlZGdlcxI5CgdvcHRpb25zGAQgASgLMh8ucnVuYW55d2hlcmUudjEuUGlwZWxpbmVPcHRpb25zUgdvcHRpb25z');
@$core.Deprecated('Use operatorSpecDescriptor instead')
const OperatorSpec$json = const {
  '1': 'OperatorSpec',
  '2': const [
    const {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'type', '3': 2, '4': 1, '5': 9, '10': 'type'},
    const {'1': 'params', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.OperatorSpec.ParamsEntry', '10': 'params'},
    const {'1': 'pinned_engine', '3': 4, '4': 1, '5': 9, '10': 'pinnedEngine'},
    const {'1': 'model_id', '3': 5, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'device', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.DeviceAffinity', '10': 'device'},
  ],
  '3': const [OperatorSpec_ParamsEntry$json],
};

@$core.Deprecated('Use operatorSpecDescriptor instead')
const OperatorSpec_ParamsEntry$json = const {
  '1': 'ParamsEntry',
  '2': const [
    const {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    const {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': const {'7': true},
};

/// Descriptor for `OperatorSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List operatorSpecDescriptor = $convert.base64Decode('CgxPcGVyYXRvclNwZWMSEgoEbmFtZRgBIAEoCVIEbmFtZRISCgR0eXBlGAIgASgJUgR0eXBlEkAKBnBhcmFtcxgDIAMoCzIoLnJ1bmFueXdoZXJlLnYxLk9wZXJhdG9yU3BlYy5QYXJhbXNFbnRyeVIGcGFyYW1zEiMKDXBpbm5lZF9lbmdpbmUYBCABKAlSDHBpbm5lZEVuZ2luZRIZCghtb2RlbF9pZBgFIAEoCVIHbW9kZWxJZBI2CgZkZXZpY2UYBiABKA4yHi5ydW5hbnl3aGVyZS52MS5EZXZpY2VBZmZpbml0eVIGZGV2aWNlGjkKC1BhcmFtc0VudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAE=');
@$core.Deprecated('Use edgeSpecDescriptor instead')
const EdgeSpec$json = const {
  '1': 'EdgeSpec',
  '2': const [
    const {'1': 'from', '3': 1, '4': 1, '5': 9, '10': 'from'},
    const {'1': 'to', '3': 2, '4': 1, '5': 9, '10': 'to'},
    const {'1': 'capacity', '3': 3, '4': 1, '5': 13, '10': 'capacity'},
    const {'1': 'policy', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.EdgePolicy', '10': 'policy'},
  ],
};

/// Descriptor for `EdgeSpec`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List edgeSpecDescriptor = $convert.base64Decode('CghFZGdlU3BlYxISCgRmcm9tGAEgASgJUgRmcm9tEg4KAnRvGAIgASgJUgJ0bxIaCghjYXBhY2l0eRgDIAEoDVIIY2FwYWNpdHkSMgoGcG9saWN5GAQgASgOMhoucnVuYW55d2hlcmUudjEuRWRnZVBvbGljeVIGcG9saWN5');
@$core.Deprecated('Use pipelineOptionsDescriptor instead')
const PipelineOptions$json = const {
  '1': 'PipelineOptions',
  '2': const [
    const {'1': 'latency_budget_ms', '3': 1, '4': 1, '5': 5, '10': 'latencyBudgetMs'},
    const {'1': 'emit_metrics', '3': 2, '4': 1, '5': 8, '10': 'emitMetrics'},
    const {'1': 'strict_validation', '3': 3, '4': 1, '5': 8, '10': 'strictValidation'},
  ],
};

/// Descriptor for `PipelineOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pipelineOptionsDescriptor = $convert.base64Decode('Cg9QaXBlbGluZU9wdGlvbnMSKgoRbGF0ZW5jeV9idWRnZXRfbXMYASABKAVSD2xhdGVuY3lCdWRnZXRNcxIhCgxlbWl0X21ldHJpY3MYAiABKAhSC2VtaXRNZXRyaWNzEisKEXN0cmljdF92YWxpZGF0aW9uGAMgASgIUhBzdHJpY3RWYWxpZGF0aW9u');
