//
//  Generated code. Do not modify.
//  source: stt_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// STT language hint. Sources pre-IDL:
///   Swift  STTConfiguration default = "en-US", STTOptions default = "en"
///   Kotlin STTConfiguration default = "en-US", STTOptions default = "en"
///   Dart   STTOptions language nullable; auto-detect when null
///   RN     STTOptions.language?: string (free-form)
///   Web    STTTranscribeOptions.language?: string (free-form)
///   C ABI  RAC_STT_DEFAULT_LANGUAGE = "en"
/// Free-form BCP-47 strings are collapsed to base language codes here.
/// AUTO is the explicit "detect from audio" sentinel; UNSPECIFIED falls
/// back to the backend default (typically "en").
/// ---------------------------------------------------------------------------
class STTLanguage extends $pb.ProtobufEnum {
  static const STTLanguage STT_LANGUAGE_UNSPECIFIED = STTLanguage._(0, _omitEnumNames ? '' : 'STT_LANGUAGE_UNSPECIFIED');
  static const STTLanguage STT_LANGUAGE_AUTO = STTLanguage._(1, _omitEnumNames ? '' : 'STT_LANGUAGE_AUTO');
  static const STTLanguage STT_LANGUAGE_EN = STTLanguage._(2, _omitEnumNames ? '' : 'STT_LANGUAGE_EN');
  static const STTLanguage STT_LANGUAGE_ES = STTLanguage._(3, _omitEnumNames ? '' : 'STT_LANGUAGE_ES');
  static const STTLanguage STT_LANGUAGE_FR = STTLanguage._(4, _omitEnumNames ? '' : 'STT_LANGUAGE_FR');
  static const STTLanguage STT_LANGUAGE_DE = STTLanguage._(5, _omitEnumNames ? '' : 'STT_LANGUAGE_DE');
  static const STTLanguage STT_LANGUAGE_ZH = STTLanguage._(6, _omitEnumNames ? '' : 'STT_LANGUAGE_ZH');
  static const STTLanguage STT_LANGUAGE_JA = STTLanguage._(7, _omitEnumNames ? '' : 'STT_LANGUAGE_JA');
  static const STTLanguage STT_LANGUAGE_KO = STTLanguage._(8, _omitEnumNames ? '' : 'STT_LANGUAGE_KO');
  static const STTLanguage STT_LANGUAGE_IT = STTLanguage._(9, _omitEnumNames ? '' : 'STT_LANGUAGE_IT');
  static const STTLanguage STT_LANGUAGE_PT = STTLanguage._(10, _omitEnumNames ? '' : 'STT_LANGUAGE_PT');
  static const STTLanguage STT_LANGUAGE_AR = STTLanguage._(11, _omitEnumNames ? '' : 'STT_LANGUAGE_AR');
  static const STTLanguage STT_LANGUAGE_RU = STTLanguage._(12, _omitEnumNames ? '' : 'STT_LANGUAGE_RU');
  static const STTLanguage STT_LANGUAGE_HI = STTLanguage._(13, _omitEnumNames ? '' : 'STT_LANGUAGE_HI');

  static const $core.List<STTLanguage> values = <STTLanguage> [
    STT_LANGUAGE_UNSPECIFIED,
    STT_LANGUAGE_AUTO,
    STT_LANGUAGE_EN,
    STT_LANGUAGE_ES,
    STT_LANGUAGE_FR,
    STT_LANGUAGE_DE,
    STT_LANGUAGE_ZH,
    STT_LANGUAGE_JA,
    STT_LANGUAGE_KO,
    STT_LANGUAGE_IT,
    STT_LANGUAGE_PT,
    STT_LANGUAGE_AR,
    STT_LANGUAGE_RU,
    STT_LANGUAGE_HI,
  ];

  static final $core.Map<$core.int, STTLanguage> _byValue = $pb.ProtobufEnum.initByValue(values);
  static STTLanguage? valueOf($core.int value) => _byValue[value];

  const STTLanguage._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
