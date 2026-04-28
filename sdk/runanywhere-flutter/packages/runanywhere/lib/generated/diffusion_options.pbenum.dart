///
//  Generated code. Do not modify.
//  source: diffusion_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class DiffusionMode extends $pb.ProtobufEnum {
  static const DiffusionMode DIFFUSION_MODE_UNSPECIFIED = DiffusionMode._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODE_UNSPECIFIED');
  static const DiffusionMode DIFFUSION_MODE_TEXT_TO_IMAGE = DiffusionMode._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODE_TEXT_TO_IMAGE');
  static const DiffusionMode DIFFUSION_MODE_IMAGE_TO_IMAGE = DiffusionMode._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODE_IMAGE_TO_IMAGE');
  static const DiffusionMode DIFFUSION_MODE_INPAINTING = DiffusionMode._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODE_INPAINTING');

  static const $core.List<DiffusionMode> values = <DiffusionMode> [
    DIFFUSION_MODE_UNSPECIFIED,
    DIFFUSION_MODE_TEXT_TO_IMAGE,
    DIFFUSION_MODE_IMAGE_TO_IMAGE,
    DIFFUSION_MODE_INPAINTING,
  ];

  static final $core.Map<$core.int, DiffusionMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionMode? valueOf($core.int value) => _byValue[value];

  const DiffusionMode._($core.int v, $core.String n) : super(v, n);
}

class DiffusionScheduler extends $pb.ProtobufEnum {
  static const DiffusionScheduler DIFFUSION_SCHEDULER_UNSPECIFIED = DiffusionScheduler._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_UNSPECIFIED');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M = DiffusionScheduler._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS = DiffusionScheduler._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DDIM = DiffusionScheduler._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_DDIM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DDPM = DiffusionScheduler._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_DDPM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER = DiffusionScheduler._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_EULER');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER_A = DiffusionScheduler._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_EULER_A');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_PNDM = DiffusionScheduler._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_PNDM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LMS = DiffusionScheduler._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_LMS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LCM = DiffusionScheduler._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_SCHEDULER_LCM');

  static const $core.List<DiffusionScheduler> values = <DiffusionScheduler> [
    DIFFUSION_SCHEDULER_UNSPECIFIED,
    DIFFUSION_SCHEDULER_DPMPP_2M,
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    DIFFUSION_SCHEDULER_DDIM,
    DIFFUSION_SCHEDULER_DDPM,
    DIFFUSION_SCHEDULER_EULER,
    DIFFUSION_SCHEDULER_EULER_A,
    DIFFUSION_SCHEDULER_PNDM,
    DIFFUSION_SCHEDULER_LMS,
    DIFFUSION_SCHEDULER_LCM,
  ];

  static final $core.Map<$core.int, DiffusionScheduler> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionScheduler? valueOf($core.int value) => _byValue[value];

  const DiffusionScheduler._($core.int v, $core.String n) : super(v, n);
}

class DiffusionModelVariant extends $pb.ProtobufEnum {
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_UNSPECIFIED = DiffusionModelVariant._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_UNSPECIFIED');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SD_1_5 = DiffusionModelVariant._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_SD_1_5');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SD_2_1 = DiffusionModelVariant._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_SD_2_1');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXL = DiffusionModelVariant._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_SDXL');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXL_TURBO = DiffusionModelVariant._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_SDXL_TURBO');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXS = DiffusionModelVariant._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_SDXS');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_LCM = DiffusionModelVariant._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_MODEL_VARIANT_LCM');

  static const $core.List<DiffusionModelVariant> values = <DiffusionModelVariant> [
    DIFFUSION_MODEL_VARIANT_UNSPECIFIED,
    DIFFUSION_MODEL_VARIANT_SD_1_5,
    DIFFUSION_MODEL_VARIANT_SD_2_1,
    DIFFUSION_MODEL_VARIANT_SDXL,
    DIFFUSION_MODEL_VARIANT_SDXL_TURBO,
    DIFFUSION_MODEL_VARIANT_SDXS,
    DIFFUSION_MODEL_VARIANT_LCM,
  ];

  static final $core.Map<$core.int, DiffusionModelVariant> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionModelVariant? valueOf($core.int value) => _byValue[value];

  const DiffusionModelVariant._($core.int v, $core.String n) : super(v, n);
}

class DiffusionTokenizerSourceKind extends $pb.ProtobufEnum {
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED = DiffusionTokenizerSourceKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 = DiffusionTokenizerSourceKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 = DiffusionTokenizerSourceKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL = DiffusionTokenizerSourceKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL');
  static const DiffusionTokenizerSourceKind DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM = DiffusionTokenizerSourceKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM');

  static const $core.List<DiffusionTokenizerSourceKind> values = <DiffusionTokenizerSourceKind> [
    DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL,
    DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM,
  ];

  static final $core.Map<$core.int, DiffusionTokenizerSourceKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DiffusionTokenizerSourceKind? valueOf($core.int value) => _byValue[value];

  const DiffusionTokenizerSourceKind._($core.int v, $core.String n) : super(v, n);
}

