//
//  Generated code. Do not modify.
//  source: hardware_profile.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class AcceleratorPreference extends $pb.ProtobufEnum {
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_AUTO = AcceleratorPreference._(0, _omitEnumNames ? '' : 'ACCELERATOR_PREFERENCE_AUTO');
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_ANE = AcceleratorPreference._(1, _omitEnumNames ? '' : 'ACCELERATOR_PREFERENCE_ANE');
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_GPU = AcceleratorPreference._(2, _omitEnumNames ? '' : 'ACCELERATOR_PREFERENCE_GPU');
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_CPU = AcceleratorPreference._(3, _omitEnumNames ? '' : 'ACCELERATOR_PREFERENCE_CPU');

  static const $core.List<AcceleratorPreference> values = <AcceleratorPreference> [
    ACCELERATOR_PREFERENCE_AUTO,
    ACCELERATOR_PREFERENCE_ANE,
    ACCELERATOR_PREFERENCE_GPU,
    ACCELERATOR_PREFERENCE_CPU,
  ];

  static final $core.Map<$core.int, AcceleratorPreference> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AcceleratorPreference? valueOf($core.int value) => _byValue[value];

  const AcceleratorPreference._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
