///
//  Generated code. Do not modify.
//  source: storage_types.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class NPUChip extends $pb.ProtobufEnum {
  static const NPUChip NPU_CHIP_UNSPECIFIED = NPUChip._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_UNSPECIFIED');
  static const NPUChip NPU_CHIP_NONE = NPUChip._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_NONE');
  static const NPUChip NPU_CHIP_APPLE_NEURAL_ENGINE = NPUChip._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_APPLE_NEURAL_ENGINE');
  static const NPUChip NPU_CHIP_QUALCOMM_HEXAGON = NPUChip._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_QUALCOMM_HEXAGON');
  static const NPUChip NPU_CHIP_MEDIATEK_APU = NPUChip._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_MEDIATEK_APU');
  static const NPUChip NPU_CHIP_GOOGLE_TPU = NPUChip._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_GOOGLE_TPU');
  static const NPUChip NPU_CHIP_INTEL_NPU = NPUChip._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_INTEL_NPU');
  static const NPUChip NPU_CHIP_OTHER = NPUChip._(99, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NPU_CHIP_OTHER');

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

