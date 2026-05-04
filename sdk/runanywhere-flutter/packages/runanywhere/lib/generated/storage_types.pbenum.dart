//
//  Generated code. Do not modify.
//  source: storage_types.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// NPU chipset detected on the host device. Used to drive Genie / vendor-NPU
/// model-download URL selection and runtime backend wiring.
/// Sources pre-IDL:
///   Dart   npu_chip.dart:14    (snapdragon8Elite, snapdragon8EliteGen5)
/// Canonical superset (this file): vendor-grouped, vendor-agnostic.
/// ---------------------------------------------------------------------------
class NPUChip extends $pb.ProtobufEnum {
  static const NPUChip NPU_CHIP_UNSPECIFIED = NPUChip._(0, _omitEnumNames ? '' : 'NPU_CHIP_UNSPECIFIED');
  static const NPUChip NPU_CHIP_NONE = NPUChip._(1, _omitEnumNames ? '' : 'NPU_CHIP_NONE');
  static const NPUChip NPU_CHIP_APPLE_NEURAL_ENGINE = NPUChip._(2, _omitEnumNames ? '' : 'NPU_CHIP_APPLE_NEURAL_ENGINE');
  static const NPUChip NPU_CHIP_QUALCOMM_HEXAGON = NPUChip._(3, _omitEnumNames ? '' : 'NPU_CHIP_QUALCOMM_HEXAGON');
  static const NPUChip NPU_CHIP_MEDIATEK_APU = NPUChip._(4, _omitEnumNames ? '' : 'NPU_CHIP_MEDIATEK_APU');
  static const NPUChip NPU_CHIP_GOOGLE_TPU = NPUChip._(5, _omitEnumNames ? '' : 'NPU_CHIP_GOOGLE_TPU');
  static const NPUChip NPU_CHIP_INTEL_NPU = NPUChip._(6, _omitEnumNames ? '' : 'NPU_CHIP_INTEL_NPU');
  static const NPUChip NPU_CHIP_OTHER = NPUChip._(99, _omitEnumNames ? '' : 'NPU_CHIP_OTHER');

  static const $core.List<NPUChip> values = <NPUChip> [
    NPU_CHIP_UNSPECIFIED,
    NPU_CHIP_NONE,
    NPU_CHIP_APPLE_NEURAL_ENGINE,
    NPU_CHIP_QUALCOMM_HEXAGON,
    NPU_CHIP_MEDIATEK_APU,
    NPU_CHIP_GOOGLE_TPU,
    NPU_CHIP_INTEL_NPU,
    NPU_CHIP_OTHER,
  ];

  static final $core.Map<$core.int, NPUChip> _byValue = $pb.ProtobufEnum.initByValue(values);
  static NPUChip? valueOf($core.int value) => _byValue[value];

  const NPUChip._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
