///
//  Generated code. Do not modify.
//  source: hardware_profile.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class AcceleratorPreference extends $pb.ProtobufEnum {
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_AUTO = AcceleratorPreference._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATOR_PREFERENCE_AUTO');
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_ANE = AcceleratorPreference._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATOR_PREFERENCE_ANE');
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_GPU = AcceleratorPreference._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATOR_PREFERENCE_GPU');
  static const AcceleratorPreference ACCELERATOR_PREFERENCE_CPU = AcceleratorPreference._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATOR_PREFERENCE_CPU');

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

