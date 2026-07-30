// This is a generated file - do not edit.
//
// Generated from diffusion_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class DiffusionMode extends $pb.ProtobufEnum {
  static const DiffusionMode DIFFUSION_MODE_UNSPECIFIED =
      DiffusionMode._(0, _omitEnumNames ? '' : 'DIFFUSION_MODE_UNSPECIFIED');
  static const DiffusionMode DIFFUSION_MODE_TEXT_TO_IMAGE =
      DiffusionMode._(1, _omitEnumNames ? '' : 'DIFFUSION_MODE_TEXT_TO_IMAGE');
  static const DiffusionMode DIFFUSION_MODE_IMAGE_TO_IMAGE =
      DiffusionMode._(2, _omitEnumNames ? '' : 'DIFFUSION_MODE_IMAGE_TO_IMAGE');
  static const DiffusionMode DIFFUSION_MODE_INPAINTING =
      DiffusionMode._(3, _omitEnumNames ? '' : 'DIFFUSION_MODE_INPAINTING');

  static const $core.List<DiffusionMode> values = <DiffusionMode>[
    DIFFUSION_MODE_UNSPECIFIED,
    DIFFUSION_MODE_TEXT_TO_IMAGE,
    DIFFUSION_MODE_IMAGE_TO_IMAGE,
    DIFFUSION_MODE_INPAINTING,
  ];

  static final $core.List<DiffusionMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static DiffusionMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionMode._(super.value, super.name);
}

/// DDPM and LCM are forward-looking; no SDK exposes them.
class DiffusionScheduler extends $pb.ProtobufEnum {
  static const DiffusionScheduler DIFFUSION_SCHEDULER_UNSPECIFIED =
      DiffusionScheduler._(
          0, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_UNSPECIFIED');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M =
      DiffusionScheduler._(
          1, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS =
      DiffusionScheduler._(
          2, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DDIM =
      DiffusionScheduler._(3, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DDIM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DDPM =
      DiffusionScheduler._(4, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DDPM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER =
      DiffusionScheduler._(
          5, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_EULER');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER_A =
      DiffusionScheduler._(
          6, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_EULER_A');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_PNDM =
      DiffusionScheduler._(7, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_PNDM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LMS =
      DiffusionScheduler._(8, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_LMS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LCM =
      DiffusionScheduler._(9, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_LCM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M_SDE =
      DiffusionScheduler._(
          10, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M_SDE');

  static const $core.List<DiffusionScheduler> values = <DiffusionScheduler>[
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
    DIFFUSION_SCHEDULER_DPMPP_2M_SDE,
  ];

  static final $core.List<DiffusionScheduler?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 10);
  static DiffusionScheduler? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionScheduler._(super.value, super.name);
}

class DiffusionModelVariant extends $pb.ProtobufEnum {
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_UNSPECIFIED =
      DiffusionModelVariant._(
          0, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_UNSPECIFIED');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SD_1_5 =
      DiffusionModelVariant._(
          1, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SD_1_5');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SD_2_1 =
      DiffusionModelVariant._(
          2, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SD_2_1');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXL =
      DiffusionModelVariant._(
          3, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SDXL');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXL_TURBO =
      DiffusionModelVariant._(
          4, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SDXL_TURBO');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_SDXS =
      DiffusionModelVariant._(
          5, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_SDXS');
  static const DiffusionModelVariant DIFFUSION_MODEL_VARIANT_LCM =
      DiffusionModelVariant._(
          6, _omitEnumNames ? '' : 'DIFFUSION_MODEL_VARIANT_LCM');

  static const $core.List<DiffusionModelVariant> values =
      <DiffusionModelVariant>[
    DIFFUSION_MODEL_VARIANT_UNSPECIFIED,
    DIFFUSION_MODEL_VARIANT_SD_1_5,
    DIFFUSION_MODEL_VARIANT_SD_2_1,
    DIFFUSION_MODEL_VARIANT_SDXL,
    DIFFUSION_MODEL_VARIANT_SDXL_TURBO,
    DIFFUSION_MODEL_VARIANT_SDXS,
    DIFFUSION_MODEL_VARIANT_LCM,
  ];

  static final $core.List<DiffusionModelVariant?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static DiffusionModelVariant? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionModelVariant._(super.value, super.name);
}

class DiffusionTokenizerSourceKind extends $pb.ProtobufEnum {
  static const DiffusionTokenizerSourceKind
      DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED =
      DiffusionTokenizerSourceKind._(0,
          _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED');
  static const DiffusionTokenizerSourceKind
      DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 =
      DiffusionTokenizerSourceKind._(1,
          _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15');
  static const DiffusionTokenizerSourceKind
      DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 =
      DiffusionTokenizerSourceKind._(2,
          _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2');
  static const DiffusionTokenizerSourceKind
      DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL =
      DiffusionTokenizerSourceKind._(3,
          _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL');
  static const DiffusionTokenizerSourceKind
      DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM = DiffusionTokenizerSourceKind._(
          4, _omitEnumNames ? '' : 'DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM');

  static const $core.List<DiffusionTokenizerSourceKind> values =
      <DiffusionTokenizerSourceKind>[
    DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2,
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL,
    DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM,
  ];

  static final $core.List<DiffusionTokenizerSourceKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static DiffusionTokenizerSourceKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionTokenizerSourceKind._(super.value, super.name);
}

class DiffusionStreamEventKind extends $pb.ProtobufEnum {
  static const DiffusionStreamEventKind
      DIFFUSION_STREAM_EVENT_KIND_UNSPECIFIED = DiffusionStreamEventKind._(
          0, _omitEnumNames ? '' : 'DIFFUSION_STREAM_EVENT_KIND_UNSPECIFIED');
  static const DiffusionStreamEventKind DIFFUSION_STREAM_EVENT_KIND_STARTED =
      DiffusionStreamEventKind._(
          1, _omitEnumNames ? '' : 'DIFFUSION_STREAM_EVENT_KIND_STARTED');
  static const DiffusionStreamEventKind DIFFUSION_STREAM_EVENT_KIND_PROGRESS =
      DiffusionStreamEventKind._(
          2, _omitEnumNames ? '' : 'DIFFUSION_STREAM_EVENT_KIND_PROGRESS');
  static const DiffusionStreamEventKind
      DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE =
      DiffusionStreamEventKind._(
          3,
          _omitEnumNames
              ? ''
              : 'DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE');
  static const DiffusionStreamEventKind DIFFUSION_STREAM_EVENT_KIND_COMPLETED =
      DiffusionStreamEventKind._(
          4, _omitEnumNames ? '' : 'DIFFUSION_STREAM_EVENT_KIND_COMPLETED');
  static const DiffusionStreamEventKind DIFFUSION_STREAM_EVENT_KIND_ERROR =
      DiffusionStreamEventKind._(
          5, _omitEnumNames ? '' : 'DIFFUSION_STREAM_EVENT_KIND_ERROR');

  static const $core.List<DiffusionStreamEventKind> values =
      <DiffusionStreamEventKind>[
    DIFFUSION_STREAM_EVENT_KIND_UNSPECIFIED,
    DIFFUSION_STREAM_EVENT_KIND_STARTED,
    DIFFUSION_STREAM_EVENT_KIND_PROGRESS,
    DIFFUSION_STREAM_EVENT_KIND_INTERMEDIATE_IMAGE,
    DIFFUSION_STREAM_EVENT_KIND_COMPLETED,
    DIFFUSION_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<DiffusionStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static DiffusionStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
