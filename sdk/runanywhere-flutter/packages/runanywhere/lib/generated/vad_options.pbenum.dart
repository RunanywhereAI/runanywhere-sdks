//
//  Generated code. Do not modify.
//  source: vad_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Speech-activity lifecycle kind.
/// Sources pre-IDL:
///   Swift  VADTypes.swift:235               (started, ended)
///   Kotlin VADTypes.kt:171                  (STARTED, ENDED)
///   Dart   runanywhere_vad.dart:28          (started, ended)
///   RN     VADTypes.ts:43                   ('started' | 'ended')
///   Web    VADTypes.ts:8                    (Started, Ended, Ongoing)   ← only SDK with ONGOING
///   C ABI  rac_vad_types.h:107              (RAC_SPEECH_STARTED, RAC_SPEECH_ENDED, RAC_SPEECH_ONGOING)
/// Canonical union: STARTED, ENDED, ONGOING.
/// ---------------------------------------------------------------------------
class SpeechActivityKind extends $pb.ProtobufEnum {
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_UNSPECIFIED = SpeechActivityKind._(0, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_UNSPECIFIED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_SPEECH_STARTED = SpeechActivityKind._(1, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_SPEECH_STARTED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_SPEECH_ENDED = SpeechActivityKind._(2, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_SPEECH_ENDED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_ONGOING = SpeechActivityKind._(3, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_ONGOING');

  static const $core.List<SpeechActivityKind> values = <SpeechActivityKind> [
    SPEECH_ACTIVITY_KIND_UNSPECIFIED,
    SPEECH_ACTIVITY_KIND_SPEECH_STARTED,
    SPEECH_ACTIVITY_KIND_SPEECH_ENDED,
    SPEECH_ACTIVITY_KIND_ONGOING,
  ];

  static final $core.Map<$core.int, SpeechActivityKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static SpeechActivityKind? valueOf($core.int value) => _byValue[value];

  const SpeechActivityKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
