// This is a generated file - do not edit.
//
// Generated from stt_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

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
/// `rac_wire_string` annotations expose the BCP-47 base code for each value via
/// the codegen-generated `wireString` accessor (see idl/rac_options.proto and
/// idl/codegen/generate_swift_convenience.py). Swift SDK `bcp47Code` is sourced
/// from this annotation; the unspecified case falls back to "" by default.
class STTLanguage extends $pb.ProtobufEnum {
  static const STTLanguage STT_LANGUAGE_UNSPECIFIED =
      STTLanguage._(0, _omitEnumNames ? '' : 'STT_LANGUAGE_UNSPECIFIED');
  static const STTLanguage STT_LANGUAGE_AUTO =
      STTLanguage._(1, _omitEnumNames ? '' : 'STT_LANGUAGE_AUTO');
  static const STTLanguage STT_LANGUAGE_EN =
      STTLanguage._(2, _omitEnumNames ? '' : 'STT_LANGUAGE_EN');
  static const STTLanguage STT_LANGUAGE_ES =
      STTLanguage._(3, _omitEnumNames ? '' : 'STT_LANGUAGE_ES');
  static const STTLanguage STT_LANGUAGE_FR =
      STTLanguage._(4, _omitEnumNames ? '' : 'STT_LANGUAGE_FR');
  static const STTLanguage STT_LANGUAGE_DE =
      STTLanguage._(5, _omitEnumNames ? '' : 'STT_LANGUAGE_DE');
  static const STTLanguage STT_LANGUAGE_ZH =
      STTLanguage._(6, _omitEnumNames ? '' : 'STT_LANGUAGE_ZH');
  static const STTLanguage STT_LANGUAGE_JA =
      STTLanguage._(7, _omitEnumNames ? '' : 'STT_LANGUAGE_JA');
  static const STTLanguage STT_LANGUAGE_KO =
      STTLanguage._(8, _omitEnumNames ? '' : 'STT_LANGUAGE_KO');
  static const STTLanguage STT_LANGUAGE_IT =
      STTLanguage._(9, _omitEnumNames ? '' : 'STT_LANGUAGE_IT');
  static const STTLanguage STT_LANGUAGE_PT =
      STTLanguage._(10, _omitEnumNames ? '' : 'STT_LANGUAGE_PT');
  static const STTLanguage STT_LANGUAGE_AR =
      STTLanguage._(11, _omitEnumNames ? '' : 'STT_LANGUAGE_AR');
  static const STTLanguage STT_LANGUAGE_RU =
      STTLanguage._(12, _omitEnumNames ? '' : 'STT_LANGUAGE_RU');
  static const STTLanguage STT_LANGUAGE_HI =
      STTLanguage._(13, _omitEnumNames ? '' : 'STT_LANGUAGE_HI');

  static const $core.List<STTLanguage> values = <STTLanguage>[
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

  static final $core.List<STTLanguage?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 13);
  static STTLanguage? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const STTLanguage._(super.value, super.name);
}

class STTAudioEncoding extends $pb.ProtobufEnum {
  static const STTAudioEncoding STT_AUDIO_ENCODING_UNSPECIFIED =
      STTAudioEncoding._(
          0, _omitEnumNames ? '' : 'STT_AUDIO_ENCODING_UNSPECIFIED');
  static const STTAudioEncoding STT_AUDIO_ENCODING_PCM_S16_LE =
      STTAudioEncoding._(
          1, _omitEnumNames ? '' : 'STT_AUDIO_ENCODING_PCM_S16_LE');
  static const STTAudioEncoding STT_AUDIO_ENCODING_PCM_F32_LE =
      STTAudioEncoding._(
          2, _omitEnumNames ? '' : 'STT_AUDIO_ENCODING_PCM_F32_LE');
  static const STTAudioEncoding STT_AUDIO_ENCODING_CONTAINER =
      STTAudioEncoding._(
          3, _omitEnumNames ? '' : 'STT_AUDIO_ENCODING_CONTAINER');

  static const $core.List<STTAudioEncoding> values = <STTAudioEncoding>[
    STT_AUDIO_ENCODING_UNSPECIFIED,
    STT_AUDIO_ENCODING_PCM_S16_LE,
    STT_AUDIO_ENCODING_PCM_F32_LE,
    STT_AUDIO_ENCODING_CONTAINER,
  ];

  static final $core.List<STTAudioEncoding?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static STTAudioEncoding? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const STTAudioEncoding._(super.value, super.name);
}

class STTStreamEventKind extends $pb.ProtobufEnum {
  static const STTStreamEventKind STT_STREAM_EVENT_KIND_UNSPECIFIED =
      STTStreamEventKind._(
          0, _omitEnumNames ? '' : 'STT_STREAM_EVENT_KIND_UNSPECIFIED');
  static const STTStreamEventKind STT_STREAM_EVENT_KIND_STARTED =
      STTStreamEventKind._(
          1, _omitEnumNames ? '' : 'STT_STREAM_EVENT_KIND_STARTED');
  static const STTStreamEventKind STT_STREAM_EVENT_KIND_PARTIAL =
      STTStreamEventKind._(
          2, _omitEnumNames ? '' : 'STT_STREAM_EVENT_KIND_PARTIAL');
  static const STTStreamEventKind STT_STREAM_EVENT_KIND_FINAL =
      STTStreamEventKind._(
          3, _omitEnumNames ? '' : 'STT_STREAM_EVENT_KIND_FINAL');
  static const STTStreamEventKind STT_STREAM_EVENT_KIND_ENDPOINT =
      STTStreamEventKind._(
          4, _omitEnumNames ? '' : 'STT_STREAM_EVENT_KIND_ENDPOINT');
  static const STTStreamEventKind STT_STREAM_EVENT_KIND_ERROR =
      STTStreamEventKind._(
          5, _omitEnumNames ? '' : 'STT_STREAM_EVENT_KIND_ERROR');

  static const $core.List<STTStreamEventKind> values = <STTStreamEventKind>[
    STT_STREAM_EVENT_KIND_UNSPECIFIED,
    STT_STREAM_EVENT_KIND_STARTED,
    STT_STREAM_EVENT_KIND_PARTIAL,
    STT_STREAM_EVENT_KIND_FINAL,
    STT_STREAM_EVENT_KIND_ENDPOINT,
    STT_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<STTStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static STTStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const STTStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
