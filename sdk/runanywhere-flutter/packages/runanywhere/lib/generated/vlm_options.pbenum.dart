//
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

///  ---------------------------------------------------------------------------
///  VLM image input format — union across all SDKs and the C ABI.
///
///  SDK ↔ proto enum mapping pre-IDL:
///    C ABI  / Kotlin / RN / Web all expose three numeric formats (FILE_PATH=0,
///           RGB_PIXELS=1, BASE64=2). Mapped to FILE_PATH, RAW_RGB, BASE64.
///    Swift  Format enum adds Apple-only cases uiImage / pixelBuffer that are
///           flattened to RAW_RGB before crossing the C ABI (see VLMTypes.swift
///           lines 70-89). RAW_RGBA is reserved for SDKs that pass straight
///           RGBA pixel buffers without the BGRA→RGB downsample step.
///    Dart   sealed class with the same three formats (filePath / rgbPixels /
///           base64); Flutter adapter passes RGB pixels through to the C ABI.
///
///  JPEG / PNG / WEBP are container hints carried in the encoded `bytes`
///  payload (no current SDK declares these as enum cases — they are
///  reserved here so we can disambiguate decoded vs encoded sources without a
///  schema migration once a backend exposes container detection).
///  ---------------------------------------------------------------------------
class VLMImageFormat extends $pb.ProtobufEnum {
  static const VLMImageFormat VLM_IMAGE_FORMAT_UNSPECIFIED = VLMImageFormat._(0, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_UNSPECIFIED');
  static const VLMImageFormat VLM_IMAGE_FORMAT_JPEG = VLMImageFormat._(1, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_JPEG');
  static const VLMImageFormat VLM_IMAGE_FORMAT_PNG = VLMImageFormat._(2, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_PNG');
  static const VLMImageFormat VLM_IMAGE_FORMAT_WEBP = VLMImageFormat._(3, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_WEBP');
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGB = VLMImageFormat._(4, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_RAW_RGB');
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGBA = VLMImageFormat._(5, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_RAW_RGBA');
  static const VLMImageFormat VLM_IMAGE_FORMAT_BASE64 = VLMImageFormat._(6, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_BASE64');
  static const VLMImageFormat VLM_IMAGE_FORMAT_FILE_PATH = VLMImageFormat._(7, _omitEnumNames ? '' : 'VLM_IMAGE_FORMAT_FILE_PATH');

  static const $core.List<VLMImageFormat> values = <VLMImageFormat> [
    VLM_IMAGE_FORMAT_UNSPECIFIED,
    VLM_IMAGE_FORMAT_JPEG,
    VLM_IMAGE_FORMAT_PNG,
    VLM_IMAGE_FORMAT_WEBP,
    VLM_IMAGE_FORMAT_RAW_RGB,
    VLM_IMAGE_FORMAT_RAW_RGBA,
    VLM_IMAGE_FORMAT_BASE64,
    VLM_IMAGE_FORMAT_FILE_PATH,
  ];

  static final $core.Map<$core.int, VLMImageFormat> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VLMImageFormat? valueOf($core.int value) => _byValue[value];

  const VLMImageFormat._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// VLM model family for chat-template selection.
/// Mirrors rac_vlm_model_family_t.
/// ---------------------------------------------------------------------------
class VLMModelFamily extends $pb.ProtobufEnum {
  static const VLMModelFamily VLM_MODEL_FAMILY_UNSPECIFIED = VLMModelFamily._(0, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_UNSPECIFIED');
  static const VLMModelFamily VLM_MODEL_FAMILY_AUTO = VLMModelFamily._(1, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_AUTO');
  static const VLMModelFamily VLM_MODEL_FAMILY_QWEN2_VL = VLMModelFamily._(2, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_QWEN2_VL');
  static const VLMModelFamily VLM_MODEL_FAMILY_SMOLVLM = VLMModelFamily._(3, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_SMOLVLM');
  static const VLMModelFamily VLM_MODEL_FAMILY_LLAVA = VLMModelFamily._(4, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_LLAVA');
  static const VLMModelFamily VLM_MODEL_FAMILY_CUSTOM = VLMModelFamily._(99, _omitEnumNames ? '' : 'VLM_MODEL_FAMILY_CUSTOM');

  static const $core.List<VLMModelFamily> values = <VLMModelFamily> [
    VLM_MODEL_FAMILY_UNSPECIFIED,
    VLM_MODEL_FAMILY_AUTO,
    VLM_MODEL_FAMILY_QWEN2_VL,
    VLM_MODEL_FAMILY_SMOLVLM,
    VLM_MODEL_FAMILY_LLAVA,
    VLM_MODEL_FAMILY_CUSTOM,
  ];

  static final $core.Map<$core.int, VLMModelFamily> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VLMModelFamily? valueOf($core.int value) => _byValue[value];

  const VLMModelFamily._($core.int v, $core.String n) : super(v, n);
}

///  ---------------------------------------------------------------------------
///  VLM error codes — canonical SDK-facing surface.
///  Sources pre-IDL:
///    Swift  CppBridge+VLM.swift:184  (notInitialized=1, modelLoadFailed=2,
///                                     processingFailed=3, invalidImage=4,
///                                     cancelled=5)
///    Dart   vlm_types.dart:164       (notInitialized=1, modelLoadFailed=2,
///                                     processingFailed=3, invalidImage=4,
///                                     cancelled=5)
///    RN     VLMTypes.ts:44           (NotInitialized=1, ModelLoadFailed=2,
///                                     ProcessingFailed=3, InvalidImage=4,
///                                     Cancelled=5)
///    Kotlin / Web                    (no enum declared pre-IDL)
///
///  The canonicalized set below narrows the surface to image-specific failure
///  modes that the C ABI can distinguish at the boundary; transport / lifecycle
///  errors (notInitialized, modelLoadFailed, processingFailed, cancelled) are
///  folded back into the shared rac_result_t error codes in rac_error.h and do
///  not appear here.
///  ---------------------------------------------------------------------------
class VLMErrorCode extends $pb.ProtobufEnum {
  static const VLMErrorCode VLM_ERROR_CODE_UNSPECIFIED = VLMErrorCode._(0, _omitEnumNames ? '' : 'VLM_ERROR_CODE_UNSPECIFIED');
  static const VLMErrorCode VLM_ERROR_CODE_INVALID_IMAGE = VLMErrorCode._(1, _omitEnumNames ? '' : 'VLM_ERROR_CODE_INVALID_IMAGE');
  static const VLMErrorCode VLM_ERROR_CODE_MODEL_NOT_LOADED = VLMErrorCode._(2, _omitEnumNames ? '' : 'VLM_ERROR_CODE_MODEL_NOT_LOADED');
  static const VLMErrorCode VLM_ERROR_CODE_UNSUPPORTED_FORMAT = VLMErrorCode._(3, _omitEnumNames ? '' : 'VLM_ERROR_CODE_UNSUPPORTED_FORMAT');
  static const VLMErrorCode VLM_ERROR_CODE_IMAGE_TOO_LARGE = VLMErrorCode._(4, _omitEnumNames ? '' : 'VLM_ERROR_CODE_IMAGE_TOO_LARGE');
  static const VLMErrorCode VLM_ERROR_CODE_NOT_INITIALIZED = VLMErrorCode._(5, _omitEnumNames ? '' : 'VLM_ERROR_CODE_NOT_INITIALIZED');
  static const VLMErrorCode VLM_ERROR_CODE_MODEL_LOAD_FAILED = VLMErrorCode._(6, _omitEnumNames ? '' : 'VLM_ERROR_CODE_MODEL_LOAD_FAILED');
  static const VLMErrorCode VLM_ERROR_CODE_PROCESSING_FAILED = VLMErrorCode._(7, _omitEnumNames ? '' : 'VLM_ERROR_CODE_PROCESSING_FAILED');
  static const VLMErrorCode VLM_ERROR_CODE_CANCELLED = VLMErrorCode._(8, _omitEnumNames ? '' : 'VLM_ERROR_CODE_CANCELLED');

  static const $core.List<VLMErrorCode> values = <VLMErrorCode> [
    VLM_ERROR_CODE_UNSPECIFIED,
    VLM_ERROR_CODE_INVALID_IMAGE,
    VLM_ERROR_CODE_MODEL_NOT_LOADED,
    VLM_ERROR_CODE_UNSUPPORTED_FORMAT,
    VLM_ERROR_CODE_IMAGE_TOO_LARGE,
    VLM_ERROR_CODE_NOT_INITIALIZED,
    VLM_ERROR_CODE_MODEL_LOAD_FAILED,
    VLM_ERROR_CODE_PROCESSING_FAILED,
    VLM_ERROR_CODE_CANCELLED,
  ];

  static final $core.Map<$core.int, VLMErrorCode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VLMErrorCode? valueOf($core.int value) => _byValue[value];

  const VLMErrorCode._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
