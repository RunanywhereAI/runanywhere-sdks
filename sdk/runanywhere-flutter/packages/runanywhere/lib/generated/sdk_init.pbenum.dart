// This is a generated file - do not edit.
//
// Generated from sdk_init.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Phase identifiers — used by SdkInitResult.phase to indicate which phase the
/// result describes. Mirrors the SDK_INIT_* analytics events (started /
/// completed / failed) that exist in sdk_events.proto.
/// ---------------------------------------------------------------------------
class SdkInitPhase extends $pb.ProtobufEnum {
  static const SdkInitPhase SDK_INIT_PHASE_UNSPECIFIED =
      SdkInitPhase._(0, _omitEnumNames ? '' : 'SDK_INIT_PHASE_UNSPECIFIED');
  static const SdkInitPhase SDK_INIT_PHASE_ONE =
      SdkInitPhase._(1, _omitEnumNames ? '' : 'SDK_INIT_PHASE_ONE');
  static const SdkInitPhase SDK_INIT_PHASE_TWO =
      SdkInitPhase._(2, _omitEnumNames ? '' : 'SDK_INIT_PHASE_TWO');
  static const SdkInitPhase SDK_INIT_PHASE_RETRY_HTTP =
      SdkInitPhase._(3, _omitEnumNames ? '' : 'SDK_INIT_PHASE_RETRY_HTTP');

  static const $core.List<SdkInitPhase> values = <SdkInitPhase>[
    SDK_INIT_PHASE_UNSPECIFIED,
    SDK_INIT_PHASE_ONE,
    SDK_INIT_PHASE_TWO,
    SDK_INIT_PHASE_RETRY_HTTP,
  ];

  static final $core.List<SdkInitPhase?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static SdkInitPhase? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SdkInitPhase._(super.value, super.name);
}

/// ---------------------------------------------------------------------------
/// Environment values — must match RAC_ENV_* in
/// sdk/runanywhere-commons/include/rac/infrastructure/network/rac_environment.h
/// (development=0, production=2). Numeric values are part of the wire format;
/// do not reorder. Number 1 was formerly SDK_INIT_ENVIRONMENT_STAGING and is
/// reserved so PRODUCTION stays at 2 (shipped commons / xcframework layout).
/// ---------------------------------------------------------------------------
class SdkInitEnvironment extends $pb.ProtobufEnum {
  static const SdkInitEnvironment SDK_INIT_ENVIRONMENT_DEVELOPMENT =
      SdkInitEnvironment._(
          0, _omitEnumNames ? '' : 'SDK_INIT_ENVIRONMENT_DEVELOPMENT');
  static const SdkInitEnvironment SDK_INIT_ENVIRONMENT_PRODUCTION =
      SdkInitEnvironment._(
          2, _omitEnumNames ? '' : 'SDK_INIT_ENVIRONMENT_PRODUCTION');

  static const $core.List<SdkInitEnvironment> values = <SdkInitEnvironment>[
    SDK_INIT_ENVIRONMENT_DEVELOPMENT,
    SDK_INIT_ENVIRONMENT_PRODUCTION,
  ];

  static final $core.Map<$core.int, SdkInitEnvironment> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static SdkInitEnvironment? valueOf($core.int value) => _byValue[value];

  const SdkInitEnvironment._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
