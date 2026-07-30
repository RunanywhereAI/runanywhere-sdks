// This is a generated file - do not edit.
//
// Generated from vlm_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// The JPEG/PNG/WEBP and RAW_RGBA values are reserved: no backend detects
/// containers yet, and no SDK passes straight RGBA. Swift's Apple-only uiImage
/// and pixelBuffer cases flatten to RAW_RGB before crossing the C ABI.
class VLMImageFormat extends $pb.ProtobufEnum {
  static const VLMImageFormat VLM_IMAGE_FORMAT_UNSPECIFIED =
      VLMImageFormat._(0, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_UNSPECIFIED');
  static const VLMImageFormat VLM_IMAGE_FORMAT_JPEG =
      VLMImageFormat._(1, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_JPEG');
  static const VLMImageFormat VLM_IMAGE_FORMAT_PNG =
      VLMImageFormat._(2, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_PNG');
  static const VLMImageFormat VLM_IMAGE_FORMAT_WEBP =
      VLMImageFormat._(3, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_WEBP');
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGB =
      VLMImageFormat._(4, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_RAW_RGB');
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGBA =
      VLMImageFormat._(5, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_RAW_RGBA');
  static const VLMImageFormat VLM_IMAGE_FORMAT_BASE64 =
      VLMImageFormat._(6, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_BASE64');
  static const VLMImageFormat VLM_IMAGE_FORMAT_FILE_PATH =
      VLMImageFormat._(7, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_FILE_PATH');

  static const $core.List<VLMImageFormat> values = <VLMImageFormat>[
    VLM_IMAGE_FORMAT_UNSPECIFIED,
    VLM_IMAGE_FORMAT_JPEG,
    VLM_IMAGE_FORMAT_PNG,
    VLM_IMAGE_FORMAT_WEBP,
    VLM_IMAGE_FORMAT_RAW_RGB,
    VLM_IMAGE_FORMAT_RAW_RGBA,
    VLM_IMAGE_FORMAT_BASE64,
    VLM_IMAGE_FORMAT_FILE_PATH,
  ];

  static final $core.List<VLMImageFormat?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static VLMImageFormat? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VLMImageFormat._(super.value, super.name);
}

class VLMModelFamily extends $pb.ProtobufEnum {
  static const VLMModelFamily VLM_MODEL_FAMILY_UNSPECIFIED =
      VLMModelFamily._(0, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_UNSPECIFIED');
  static const VLMModelFamily VLM_MODEL_FAMILY_AUTO =
      VLMModelFamily._(1, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_AUTO');
  static const VLMModelFamily VLM_MODEL_FAMILY_QWEN2_VL =
      VLMModelFamily._(2, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_QWEN2_VL');
  static const VLMModelFamily VLM_MODEL_FAMILY_SMOLVLM =
      VLMModelFamily._(3, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_SMOLVLM');
  static const VLMModelFamily VLM_MODEL_FAMILY_LLAVA =
      VLMModelFamily._(4, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_LLAVA');
  static const VLMModelFamily VLM_MODEL_FAMILY_CUSTOM =
      VLMModelFamily._(99, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_CUSTOM');

  static const $core.List<VLMModelFamily> values = <VLMModelFamily>[
    VLM_MODEL_FAMILY_UNSPECIFIED,
    VLM_MODEL_FAMILY_AUTO,
    VLM_MODEL_FAMILY_QWEN2_VL,
    VLM_MODEL_FAMILY_SMOLVLM,
    VLM_MODEL_FAMILY_LLAVA,
    VLM_MODEL_FAMILY_CUSTOM,
  ];

  static final $core.Map<$core.int, VLMModelFamily> _byValue =
      $pb.ProtobufEnum.initByValue(values);
  static VLMModelFamily? valueOf($core.int value) => _byValue[value];

  const VLMModelFamily._(super.value, super.name);
}

class VLMStreamEventKind extends $pb.ProtobufEnum {
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_UNSPECIFIED =
      VLMStreamEventKind._(
          0, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_UNSPECIFIED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_STARTED =
      VLMStreamEventKind._(
          1, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_STARTED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_IMAGE_ENCODED =
      VLMStreamEventKind._(
          2, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_IMAGE_ENCODED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_TOKEN =
      VLMStreamEventKind._(
          3, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_TOKEN');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_COMPLETED =
      VLMStreamEventKind._(
          4, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_COMPLETED');
  static const VLMStreamEventKind VLM_STREAM_EVENT_KIND_ERROR =
      VLMStreamEventKind._(
          5, _omitEnumNames ? '' : 'VLM_STREAM_EVENT_KIND_ERROR');

  static const $core.List<VLMStreamEventKind> values = <VLMStreamEventKind>[
    VLM_STREAM_EVENT_KIND_UNSPECIFIED,
    VLM_STREAM_EVENT_KIND_STARTED,
    VLM_STREAM_EVENT_KIND_IMAGE_ENCODED,
    VLM_STREAM_EVENT_KIND_TOKEN,
    VLM_STREAM_EVENT_KIND_COMPLETED,
    VLM_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<VLMStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static VLMStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VLMStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
