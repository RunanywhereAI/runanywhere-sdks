// This is a generated file - do not edit.
//
// Generated from tts_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Voice gender — union across SDKs.
/// Sources pre-IDL:
///   RN     TTSTypes.ts:117    ('male' | 'female' | 'neutral')
/// (Other SDKs did not expose voice listing pre-IDL; canonicalized here.)
/// ---------------------------------------------------------------------------
class TTSVoiceGender extends $pb.ProtobufEnum {
  static const TTSVoiceGender TTS_VOICE_GENDER_UNSPECIFIED =
      TTSVoiceGender._(0, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_UNSPECIFIED');
  static const TTSVoiceGender TTS_VOICE_GENDER_MALE =
      TTSVoiceGender._(1, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_MALE');
  static const TTSVoiceGender TTS_VOICE_GENDER_FEMALE =
      TTSVoiceGender._(2, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_FEMALE');
  static const TTSVoiceGender TTS_VOICE_GENDER_NEUTRAL =
      TTSVoiceGender._(3, _omitEnumNames ? '' : 'TTS_VOICE_GENDER_NEUTRAL');

  static const $core.List<TTSVoiceGender> values = <TTSVoiceGender>[
    TTS_VOICE_GENDER_UNSPECIFIED,
    TTS_VOICE_GENDER_MALE,
    TTS_VOICE_GENDER_FEMALE,
    TTS_VOICE_GENDER_NEUTRAL,
  ];

  static final $core.List<TTSVoiceGender?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static TTSVoiceGender? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TTSVoiceGender._(super.value, super.name);
}

class TTSStreamEventKind extends $pb.ProtobufEnum {
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_UNSPECIFIED =
      TTSStreamEventKind._(
          0, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_UNSPECIFIED');
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_STARTED =
      TTSStreamEventKind._(
          1, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_STARTED');
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_AUDIO_CHUNK =
      TTSStreamEventKind._(
          2, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_AUDIO_CHUNK');
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_PHONEME =
      TTSStreamEventKind._(
          3, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_PHONEME');
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_COMPLETED =
      TTSStreamEventKind._(
          4, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_COMPLETED');
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_ERROR =
      TTSStreamEventKind._(
          5, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_ERROR');
  static const TTSStreamEventKind TTS_STREAM_EVENT_KIND_PROGRESS =
      TTSStreamEventKind._(
          6, _omitEnumNames ? '' : 'TTS_STREAM_EVENT_KIND_PROGRESS');

  static const $core.List<TTSStreamEventKind> values = <TTSStreamEventKind>[
    TTS_STREAM_EVENT_KIND_UNSPECIFIED,
    TTS_STREAM_EVENT_KIND_STARTED,
    TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
    TTS_STREAM_EVENT_KIND_PHONEME,
    TTS_STREAM_EVENT_KIND_COMPLETED,
    TTS_STREAM_EVENT_KIND_ERROR,
    TTS_STREAM_EVENT_KIND_PROGRESS,
  ];

  static final $core.List<TTSStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static TTSStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TTSStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
