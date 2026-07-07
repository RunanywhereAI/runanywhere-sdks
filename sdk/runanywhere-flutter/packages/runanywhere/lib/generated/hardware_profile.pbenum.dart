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
/// Hardware acceleration preference for inference. Canonical single enum —
/// previously duplicated as `AcceleratorPreference` (ANE/GPU/CPU/AUTO) in this
/// file and `AccelerationPreference` in model_types.proto. Consolidated here
/// because it is a pure hardware concept and
/// hardware_profile.proto has no imports (model_types.proto already imports
/// this file — placing the enum here avoids a cyclic import). Sources pre-IDL:
///   Web    enums.ts:165   (Auto / WebGPU / CPU)
///   Swift  extensions     (CPU / GPU / NPU / Metal)
///   Kotlin enum           (CPU / GPU / NPU / Vulkan)
/// Canonicalized union below.
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
  static const AccelerationPreference ACCELERATION_PREFERENCE_WEBGPU =
      AccelerationPreference._(
          5, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_WEBGPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_METAL =
      AccelerationPreference._(
          6, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_METAL');
  static const AccelerationPreference ACCELERATION_PREFERENCE_VULKAN =
      AccelerationPreference._(
          7, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_VULKAN');

  static const $core.List<AccelerationPreference> values =
      <AccelerationPreference>[
    ACCELERATION_PREFERENCE_UNSPECIFIED,
    ACCELERATION_PREFERENCE_AUTO,
    ACCELERATION_PREFERENCE_CPU,
    ACCELERATION_PREFERENCE_GPU,
    ACCELERATION_PREFERENCE_NPU,
    ACCELERATION_PREFERENCE_WEBGPU,
    ACCELERATION_PREFERENCE_METAL,
    ACCELERATION_PREFERENCE_VULKAN,
  ];

  static final $core.List<AccelerationPreference?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static AccelerationPreference? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AccelerationPreference._(super.value, super.name);
}

/// Logical hardware service contract. Mirrors the C ABI in
/// sdk/runanywhere-commons/include/rac/router/rac_hardware_abi.h:
///   - rac_hardware_profile_get → GetProfile
///   - rac_hardware_get_accelerators → GetAccelerators
///   - rac_hardware_set_accelerator_preference → SetAcceleratorPreference
///
/// Native device probes (chip detection, neural engine queries, GPU
/// discovery, memory/cores) remain platform-adapter owned. C++ caches and
/// serves the normalized HardwareProfile/AcceleratorInfo messages.
/// Pre-flight Qualcomm Hexagon NPU probe. Mirrors the C ABI struct
/// rac_npu_info_t (rac/infrastructure/device/rac_npu_capability.h); served
/// over the proto-buffer ABI by rac_npu_probe_proto(). Enum values equal the
/// Hexagon HTP version number to stay in lock-step with rac_hexagon_arch_t.
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
