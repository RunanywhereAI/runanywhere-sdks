// This is a generated file - do not edit.
//
// Generated from pipeline.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class DeviceAffinity extends $pb.ProtobufEnum {
  static const DeviceAffinity DEVICE_AFFINITY_UNSPECIFIED =
      DeviceAffinity._(0, _omitEnumNames ? '' : 'DEVICE_AFFINITY_UNSPECIFIED');
  static const DeviceAffinity DEVICE_AFFINITY_ANY =
      DeviceAffinity._(1, _omitEnumNames ? '' : 'DEVICE_AFFINITY_ANY');
  static const DeviceAffinity DEVICE_AFFINITY_CPU =
      DeviceAffinity._(2, _omitEnumNames ? '' : 'DEVICE_AFFINITY_CPU');
  static const DeviceAffinity DEVICE_AFFINITY_GPU =
      DeviceAffinity._(3, _omitEnumNames ? '' : 'DEVICE_AFFINITY_GPU');
  static const DeviceAffinity DEVICE_AFFINITY_ANE =
      DeviceAffinity._(4, _omitEnumNames ? '' : 'DEVICE_AFFINITY_ANE');

  static const $core.List<DeviceAffinity> values = <DeviceAffinity>[
    DEVICE_AFFINITY_UNSPECIFIED,
    DEVICE_AFFINITY_ANY,
    DEVICE_AFFINITY_CPU,
    DEVICE_AFFINITY_GPU,
    DEVICE_AFFINITY_ANE,
  ];

  static final $core.List<DeviceAffinity?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static DeviceAffinity? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DeviceAffinity._(super.value, super.name);
}

class EdgePolicy extends $pb.ProtobufEnum {
  static const EdgePolicy EDGE_POLICY_UNSPECIFIED =
      EdgePolicy._(0, _omitEnumNames ? '' : 'EDGE_POLICY_UNSPECIFIED');

  /// Producer blocks when channel is full (default, safest).
  static const EdgePolicy EDGE_POLICY_BLOCK =
      EdgePolicy._(1, _omitEnumNames ? '' : 'EDGE_POLICY_BLOCK');

  /// Oldest item is dropped when channel is full (audio routing only).
  static const EdgePolicy EDGE_POLICY_DROP_OLDEST =
      EdgePolicy._(2, _omitEnumNames ? '' : 'EDGE_POLICY_DROP_OLDEST');

  /// Newest item is dropped when channel is full (pager coalescing).
  static const EdgePolicy EDGE_POLICY_DROP_NEWEST =
      EdgePolicy._(3, _omitEnumNames ? '' : 'EDGE_POLICY_DROP_NEWEST');

  static const $core.List<EdgePolicy> values = <EdgePolicy>[
    EDGE_POLICY_UNSPECIFIED,
    EDGE_POLICY_BLOCK,
    EDGE_POLICY_DROP_OLDEST,
    EDGE_POLICY_DROP_NEWEST,
  ];

  static final $core.List<EdgePolicy?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static EdgePolicy? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EdgePolicy._(super.value, super.name);
}

/// ---------------------------------------------------------------------------
/// Pipeline lifecycle status — shared by compile/start/stop results.
/// ---------------------------------------------------------------------------
class PipelineStatus extends $pb.ProtobufEnum {
  static const PipelineStatus PIPELINE_STATUS_UNSPECIFIED =
      PipelineStatus._(0, _omitEnumNames ? '' : 'PIPELINE_STATUS_UNSPECIFIED');
  static const PipelineStatus PIPELINE_STATUS_OK =
      PipelineStatus._(1, _omitEnumNames ? '' : 'PIPELINE_STATUS_OK');
  static const PipelineStatus PIPELINE_STATUS_FAILED =
      PipelineStatus._(2, _omitEnumNames ? '' : 'PIPELINE_STATUS_FAILED');

  static const $core.List<PipelineStatus> values = <PipelineStatus>[
    PIPELINE_STATUS_UNSPECIFIED,
    PIPELINE_STATUS_OK,
    PIPELINE_STATUS_FAILED,
  ];

  static final $core.List<PipelineStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static PipelineStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PipelineStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
