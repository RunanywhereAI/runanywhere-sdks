//
//  Generated code. Do not modify.
//  source: tts_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Voice gender — union across SDKs.
/// Sources pre-IDL:
///   RN     TTSTypes.ts:117    ('male' | 'female' | 'neutral')
/// (Other SDKs did not expose voice listing pre-IDL; canonicalized here.)
/// ---------------------------------------------------------------------------
class TTSVoiceGender extends $pb.ProtobufEnum {
  static const TTSVoiceGender TTS_VOICE_GENDER_UNSPECIFIED = TTSVoiceGender._(0, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_UNSPECIFIED');
  static const TTSVoiceGender TTS_VOICE_GENDER_MALE = TTSVoiceGender._(1, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_MALE');
  static const TTSVoiceGender TTS_VOICE_GENDER_FEMALE = TTSVoiceGender._(2, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_FEMALE');
  static const TTSVoiceGender TTS_VOICE_GENDER_NEUTRAL = TTSVoiceGender._(3, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_NEUTRAL');

  static const $core.List<TTSVoiceGender> values = <TTSVoiceGender> [
    TTS_VOICE_GENDER_UNSPECIFIED,
    TTS_VOICE_GENDER_MALE,
    TTS_VOICE_GENDER_FEMALE,
    TTS_VOICE_GENDER_NEUTRAL,
  ];

  static final $core.Map<$core.int, TTSVoiceGender> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TTSVoiceGender? valueOf($core.int value) => _byValue[value];

  const TTSVoiceGender._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
