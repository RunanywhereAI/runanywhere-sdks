///
//  Generated code. Do not modify.
//  source: stt_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class STTLanguage extends $pb.ProtobufEnum {
  static const STTLanguage STT_LANGUAGE_UNSPECIFIED = STTLanguage._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_UNSPECIFIED');
  static const STTLanguage STT_LANGUAGE_AUTO = STTLanguage._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_AUTO');
  static const STTLanguage STT_LANGUAGE_EN = STTLanguage._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_EN');
  static const STTLanguage STT_LANGUAGE_ES = STTLanguage._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_ES');
  static const STTLanguage STT_LANGUAGE_FR = STTLanguage._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_FR');
  static const STTLanguage STT_LANGUAGE_DE = STTLanguage._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_DE');
  static const STTLanguage STT_LANGUAGE_ZH = STTLanguage._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_ZH');
  static const STTLanguage STT_LANGUAGE_JA = STTLanguage._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_JA');
  static const STTLanguage STT_LANGUAGE_KO = STTLanguage._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_KO');
  static const STTLanguage STT_LANGUAGE_IT = STTLanguage._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_IT');
  static const STTLanguage STT_LANGUAGE_PT = STTLanguage._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_PT');
  static const STTLanguage STT_LANGUAGE_AR = STTLanguage._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_AR');
  static const STTLanguage STT_LANGUAGE_RU = STTLanguage._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_RU');
  static const STTLanguage STT_LANGUAGE_HI = STTLanguage._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STT_LANGUAGE_HI');

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

