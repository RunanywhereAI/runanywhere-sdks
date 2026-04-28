///
//  Generated code. Do not modify.
//  source: vad_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class SpeechActivityKind extends $pb.ProtobufEnum {
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_UNSPECIFIED = SpeechActivityKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SPEECH_ACTIVITY_KIND_UNSPECIFIED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_SPEECH_STARTED = SpeechActivityKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SPEECH_ACTIVITY_KIND_SPEECH_STARTED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_SPEECH_ENDED = SpeechActivityKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SPEECH_ACTIVITY_KIND_SPEECH_ENDED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_ONGOING = SpeechActivityKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SPEECH_ACTIVITY_KIND_ONGOING');

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

