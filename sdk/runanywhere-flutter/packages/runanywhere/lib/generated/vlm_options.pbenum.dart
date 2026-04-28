///
//  Generated code. Do not modify.
//  source: vlm_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class VLMImageFormat extends $pb.ProtobufEnum {
  static const VLMImageFormat VLM_IMAGE_FORMAT_UNSPECIFIED = VLMImageFormat._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_UNSPECIFIED');
  static const VLMImageFormat VLM_IMAGE_FORMAT_JPEG = VLMImageFormat._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_JPEG');
  static const VLMImageFormat VLM_IMAGE_FORMAT_PNG = VLMImageFormat._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_PNG');
  static const VLMImageFormat VLM_IMAGE_FORMAT_WEBP = VLMImageFormat._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_WEBP');
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGB = VLMImageFormat._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_RAW_RGB');
  static const VLMImageFormat VLM_IMAGE_FORMAT_RAW_RGBA = VLMImageFormat._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_RAW_RGBA');
  static const VLMImageFormat VLM_IMAGE_FORMAT_BASE64 = VLMImageFormat._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_BASE64');
  static const VLMImageFormat VLM_IMAGE_FORMAT_FILE_PATH = VLMImageFormat._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_IMAGE_FORMAT_FILE_PATH');

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

class VLMErrorCode extends $pb.ProtobufEnum {
  static const VLMErrorCode VLM_ERROR_CODE_UNSPECIFIED = VLMErrorCode._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_ERROR_CODE_UNSPECIFIED');
  static const VLMErrorCode VLM_ERROR_CODE_INVALID_IMAGE = VLMErrorCode._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_ERROR_CODE_INVALID_IMAGE');
  static const VLMErrorCode VLM_ERROR_CODE_MODEL_NOT_LOADED = VLMErrorCode._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_ERROR_CODE_MODEL_NOT_LOADED');
  static const VLMErrorCode VLM_ERROR_CODE_UNSUPPORTED_FORMAT = VLMErrorCode._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_ERROR_CODE_UNSUPPORTED_FORMAT');
  static const VLMErrorCode VLM_ERROR_CODE_IMAGE_TOO_LARGE = VLMErrorCode._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VLM_ERROR_CODE_IMAGE_TOO_LARGE');

  static const $core.List<VLMErrorCode> values = <VLMErrorCode> [
    VLM_ERROR_CODE_UNSPECIFIED,
    VLM_ERROR_CODE_INVALID_IMAGE,
    VLM_ERROR_CODE_MODEL_NOT_LOADED,
    VLM_ERROR_CODE_UNSUPPORTED_FORMAT,
    VLM_ERROR_CODE_IMAGE_TOO_LARGE,
  ];

  static final $core.Map<$core.int, VLMErrorCode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VLMErrorCode? valueOf($core.int value) => _byValue[value];

  const VLMErrorCode._($core.int v, $core.String n) : super(v, n);
}

