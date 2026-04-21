//
//  Generated code. Do not modify.
//  source: pipeline.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class DeviceAffinity extends $pb.ProtobufEnum {
  static const DeviceAffinity DEVICE_AFFINITY_UNSPECIFIED = DeviceAffinity._(0, _omitEnumNames ? '' : 'DEVICE_AFFINITY_UNSPECIFIED');
  static const DeviceAffinity DEVICE_AFFINITY_ANY = DeviceAffinity._(1, _omitEnumNames ? '' : 'DEVICE_AFFINITY_ANY');
  static const DeviceAffinity DEVICE_AFFINITY_CPU = DeviceAffinity._(2, _omitEnumNames ? '' : 'DEVICE_AFFINITY_CPU');
  static const DeviceAffinity DEVICE_AFFINITY_GPU = DeviceAffinity._(3, _omitEnumNames ? '' : 'DEVICE_AFFINITY_GPU');
  static const DeviceAffinity DEVICE_AFFINITY_ANE = DeviceAffinity._(4, _omitEnumNames ? '' : 'DEVICE_AFFINITY_ANE');

  static const $core.List<DeviceAffinity> values = <DeviceAffinity> [
    DEVICE_AFFINITY_UNSPECIFIED,
    DEVICE_AFFINITY_ANY,
    DEVICE_AFFINITY_CPU,
    DEVICE_AFFINITY_GPU,
    DEVICE_AFFINITY_ANE,
  ];

  static final $core.Map<$core.int, DeviceAffinity> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DeviceAffinity? valueOf($core.int value) => _byValue[value];

  const DeviceAffinity._($core.int v, $core.String n) : super(v, n);
}

class EdgePolicy extends $pb.ProtobufEnum {
  static const EdgePolicy EDGE_POLICY_UNSPECIFIED = EdgePolicy._(0, _omitEnumNames ? '' : 'EDGE_POLICY_UNSPECIFIED');
  static const EdgePolicy EDGE_POLICY_BLOCK = EdgePolicy._(1, _omitEnumNames ? '' : 'EDGE_POLICY_BLOCK');
  static const EdgePolicy EDGE_POLICY_DROP_OLDEST = EdgePolicy._(2, _omitEnumNames ? '' : 'EDGE_POLICY_DROP_OLDEST');
  static const EdgePolicy EDGE_POLICY_DROP_NEWEST = EdgePolicy._(3, _omitEnumNames ? '' : 'EDGE_POLICY_DROP_NEWEST');

  static const $core.List<EdgePolicy> values = <EdgePolicy> [
    EDGE_POLICY_UNSPECIFIED,
    EDGE_POLICY_BLOCK,
    EDGE_POLICY_DROP_OLDEST,
    EDGE_POLICY_DROP_NEWEST,
  ];

  static final $core.Map<$core.int, EdgePolicy> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EdgePolicy? valueOf($core.int value) => _byValue[value];

  const EdgePolicy._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
