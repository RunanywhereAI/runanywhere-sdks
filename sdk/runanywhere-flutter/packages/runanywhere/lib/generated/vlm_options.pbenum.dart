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

/// ---------------------------------------------------------------------------
/// VLM image input format — union across all SDKs and the C ABI.
///
/// SDK ↔ proto enum mapping pre-IDL:
///   C ABI  / Kotlin / RN / Web all expose three numeric formats (FILE_PATH=0,
///          RGB_PIXELS=1, BASE64=2). Mapped to FILE_PATH, RAW_RGB, BASE64.
///   Swift  Format enum adds Apple-only cases uiImage / pixelBuffer that are
///          flattened to RAW_RGB before crossing the C ABI (see VLMTypes.swift
///          lines 70-89). RAW_RGBA is reserved for SDKs that pass straight
///          RGBA pixel buffers without the BGRA→RGB downsample step.
///   Dart   sealed class with the same three formats (filePath / rgbPixels /
///          base64); Flutter adapter passes RGB pixels through to the C ABI.
///
/// JPEG / PNG / WEBP are container hints carried in the encoded `bytes`
/// payload (no current SDK declares these as enum cases — they are
/// reserved here so we can disambiguate decoded vs encoded sources without a
/// schema migration once a backend exposes container detection).
/// ---------------------------------------------------------------------------
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

  /// RN RGBPixels / Web RGBPixels /
  /// C ABI RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGBA =
      VLMImageFormat._(5, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_RAW_RGBA');

  /// (Swift UIImage path produces RGBA
  /// before downsample; pre-IDL no SDK
  /// exposes RGBA over the C ABI)
  static const VLMImageFormat VLM_IMAGE_FORMAT_BASE64 =
      VLMImageFormat._(6, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_BASE64');

  /// Dart base64 / RN Base64 /
  /// Web Base64 /
  /// C ABI RAC_VLM_IMAGE_FORMAT_BASE64
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

/// ---------------------------------------------------------------------------
/// VLM model family for chat-template selection.
/// Mirrors rac_vlm_model_family_t.
/// ---------------------------------------------------------------------------
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
