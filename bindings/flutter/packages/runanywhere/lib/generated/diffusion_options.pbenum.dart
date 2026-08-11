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

/// Only values with a C carrier are listed. UNSPECIFIED = the model's
/// configured scheduler, which is what every engine does.
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
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER =
      DiffusionScheduler._(
          4, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_EULER');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_EULER_A =
      DiffusionScheduler._(
          5, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_EULER_A');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_PNDM =
      DiffusionScheduler._(6, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_PNDM');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_LMS =
      DiffusionScheduler._(7, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_LMS');
  static const DiffusionScheduler DIFFUSION_SCHEDULER_DPMPP_2M_SDE =
      DiffusionScheduler._(
          8, _omitEnumNames ? '' : 'DIFFUSION_SCHEDULER_DPMPP_2M_SDE');

  static const $core.List<DiffusionScheduler> values = <DiffusionScheduler>[
    DIFFUSION_SCHEDULER_UNSPECIFIED,
    DIFFUSION_SCHEDULER_DPMPP_2M,
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS,
    DIFFUSION_SCHEDULER_DDIM,
    DIFFUSION_SCHEDULER_EULER,
    DIFFUSION_SCHEDULER_EULER_A,
    DIFFUSION_SCHEDULER_PNDM,
    DIFFUSION_SCHEDULER_LMS,
    DIFFUSION_SCHEDULER_DPMPP_2M_SDE,
  ];

  static final $core.List<DiffusionScheduler?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 8);
  static DiffusionScheduler? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionScheduler._(super.value, super.name);
}

/// Encoding of the returned image bytes.
class DiffusionOutputFormat extends $pb.ProtobufEnum {
  static const DiffusionOutputFormat DIFFUSION_OUTPUT_FORMAT_UNSPECIFIED =
      DiffusionOutputFormat._(
          0, _omitEnumNames ? '' : 'DIFFUSION_OUTPUT_FORMAT_UNSPECIFIED');
  static const DiffusionOutputFormat DIFFUSION_OUTPUT_FORMAT_PNG =
      DiffusionOutputFormat._(
          1, _omitEnumNames ? '' : 'DIFFUSION_OUTPUT_FORMAT_PNG');

  /// No JPEG or WEBP encoder exists in this tree yet. Requesting one is
  /// rejected outright; it is never silently answered with PNG.
  static const DiffusionOutputFormat DIFFUSION_OUTPUT_FORMAT_JPEG =
      DiffusionOutputFormat._(
          2, _omitEnumNames ? '' : 'DIFFUSION_OUTPUT_FORMAT_JPEG');
  static const DiffusionOutputFormat DIFFUSION_OUTPUT_FORMAT_WEBP =
      DiffusionOutputFormat._(
          3, _omitEnumNames ? '' : 'DIFFUSION_OUTPUT_FORMAT_WEBP');

  /// Escape hatch: no encode, 4 bytes per pixel, "image/raw-rgba".
  static const DiffusionOutputFormat DIFFUSION_OUTPUT_FORMAT_RAW_RGBA =
      DiffusionOutputFormat._(
          4, _omitEnumNames ? '' : 'DIFFUSION_OUTPUT_FORMAT_RAW_RGBA');

  static const $core.List<DiffusionOutputFormat> values =
      <DiffusionOutputFormat>[
    DIFFUSION_OUTPUT_FORMAT_UNSPECIFIED,
    DIFFUSION_OUTPUT_FORMAT_PNG,
    DIFFUSION_OUTPUT_FORMAT_JPEG,
    DIFFUSION_OUTPUT_FORMAT_WEBP,
    DIFFUSION_OUTPUT_FORMAT_RAW_RGBA,
  ];

  static final $core.List<DiffusionOutputFormat?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static DiffusionOutputFormat? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiffusionOutputFormat._(super.value, super.name);
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
