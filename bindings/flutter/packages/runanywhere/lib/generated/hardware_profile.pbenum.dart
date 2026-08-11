// This is a generated file - do not edit.
//
// Generated from hardware_profile.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Hardware acceleration preference for inference. Device CLASS, not graphics
/// API. A hint, never a hard requirement — the runtime may fall back.
/// UNSPECIFIED means "you choose".
///
/// Canonical single enum. It lives in this file rather than model_types.proto
/// because model_types.proto already imports this file; placing it here avoids
/// a cyclic import.
/// ---------------------------------------------------------------------------
class AccelerationPreference extends $pb.ProtobufEnum {
  static const AccelerationPreference ACCELERATION_PREFERENCE_UNSPECIFIED =
      AccelerationPreference._(
          0, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_UNSPECIFIED');
  static const AccelerationPreference ACCELERATION_PREFERENCE_AUTO =
      AccelerationPreference._(
          1, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_AUTO');
  static const AccelerationPreference ACCELERATION_PREFERENCE_CPU =
      AccelerationPreference._(
          2, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_CPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_GPU =
      AccelerationPreference._(
          3, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_GPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_NPU =
      AccelerationPreference._(
          4, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_NPU');

  static const $core.List<AccelerationPreference> values =
      <AccelerationPreference>[
    ACCELERATION_PREFERENCE_UNSPECIFIED,
    ACCELERATION_PREFERENCE_AUTO,
    ACCELERATION_PREFERENCE_CPU,
    ACCELERATION_PREFERENCE_GPU,
    ACCELERATION_PREFERENCE_NPU,
  ];

  static final $core.List<AccelerationPreference?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static AccelerationPreference? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AccelerationPreference._(super.value, super.name);
}

/// Pre-flight Qualcomm Hexagon NPU probe. Mirrors QHexRT's engine-owned C ABI
/// (`rac/qhexrt/rac_qhexrt.h`) and is serialized by
/// rac_qhexrt_probe_proto(). Enum values equal the Hexagon HTP version number
/// to stay in lock-step with rac_qhexrt_hexagon_arch_t.
class HexagonArch extends $pb.ProtobufEnum {
  static const HexagonArch HEXAGON_ARCH_UNKNOWN =
      HexagonArch._(0, _omitEnumNames ? '' : 'HEXAGON_ARCH_UNKNOWN');
  static const HexagonArch HEXAGON_ARCH_V68 =
      HexagonArch._(68, _omitEnumNames ? '' : 'HEXAGON_ARCH_V68');
  static const HexagonArch HEXAGON_ARCH_V69 =
      HexagonArch._(69, _omitEnumNames ? '' : 'HEXAGON_ARCH_V69');
  static const HexagonArch HEXAGON_ARCH_V73 =
      HexagonArch._(73, _omitEnumNames ? '' : 'HEXAGON_ARCH_V73');
  static const HexagonArch HEXAGON_ARCH_V75 =
      HexagonArch._(75, _omitEnumNames ? '' : 'HEXAGON_ARCH_V75');
  static const HexagonArch HEXAGON_ARCH_V79 =
      HexagonArch._(79, _omitEnumNames ? '' : 'HEXAGON_ARCH_V79');
  static const HexagonArch HEXAGON_ARCH_V81 =
      HexagonArch._(81, _omitEnumNames ? '' : 'HEXAGON_ARCH_V81');

  static const $core.List<HexagonArch> values = <HexagonArch>[
    HEXAGON_ARCH_UNKNOWN,
    HEXAGON_ARCH_V68,
    HEXAGON_ARCH_V69,
    HEXAGON_ARCH_V73,
    HEXAGON_ARCH_V75,
    HEXAGON_ARCH_V79,
    HEXAGON_ARCH_V81,
  ];

  static final $core.Map<$core.int, HexagonArch> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static HexagonArch? valueOf($core.int value) => _byValue[value];

  const HexagonArch._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
