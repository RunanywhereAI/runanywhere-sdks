// This is a generated file - do not edit.
//
// Generated from vad_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class SpeechActivityKind extends $pb.ProtobufEnum {
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_UNSPECIFIED =
      SpeechActivityKind._(
          0, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_UNSPECIFIED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_SPEECH_STARTED =
      SpeechActivityKind._(
          1, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_SPEECH_STARTED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_SPEECH_ENDED =
      SpeechActivityKind._(
          2, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_SPEECH_ENDED');
  static const SpeechActivityKind SPEECH_ACTIVITY_KIND_ONGOING =
      SpeechActivityKind._(
          3, _omitEnumNames ? '' : 'SPEECH_ACTIVITY_KIND_ONGOING');

  static const $core.List<SpeechActivityKind> values = <SpeechActivityKind>[
    SPEECH_ACTIVITY_KIND_UNSPECIFIED,
    SPEECH_ACTIVITY_KIND_SPEECH_STARTED,
    SPEECH_ACTIVITY_KIND_SPEECH_ENDED,
    SPEECH_ACTIVITY_KIND_ONGOING,
  ];

  static final $core.List<SpeechActivityKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static SpeechActivityKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SpeechActivityKind._(super.value, super.name);
}

class VADStreamEventKind extends $pb.ProtobufEnum {
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_UNSPECIFIED =
      VADStreamEventKind._(
          0, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_UNSPECIFIED');
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_STARTED =
      VADStreamEventKind._(
          1, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_STARTED');
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_FRAME =
      VADStreamEventKind._(
          2, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_FRAME');
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY =
      VADStreamEventKind._(
          3, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY');
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_STATISTICS =
      VADStreamEventKind._(
          4, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_STATISTICS');
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_STOPPED =
      VADStreamEventKind._(
          5, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_STOPPED');
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_ERROR =
      VADStreamEventKind._(
          6, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_ERROR');

  /// Speech that interrupts active assistant playback. Downstream pipeline
  /// also routes this through InterruptedEvent/InterruptReason.
  static const VADStreamEventKind VAD_STREAM_EVENT_KIND_BARGE_IN =
      VADStreamEventKind._(
          7, _omitEnumNames ? '' : 'VAD_STREAM_EVENT_KIND_BARGE_IN');

  static const $core.List<VADStreamEventKind> values = <VADStreamEventKind>[
    VAD_STREAM_EVENT_KIND_UNSPECIFIED,
    VAD_STREAM_EVENT_KIND_STARTED,
    VAD_STREAM_EVENT_KIND_FRAME,
    VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
    VAD_STREAM_EVENT_KIND_STATISTICS,
    VAD_STREAM_EVENT_KIND_STOPPED,
    VAD_STREAM_EVENT_KIND_ERROR,
    VAD_STREAM_EVENT_KIND_BARGE_IN,
  ];

  static final $core.List<VADStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static VADStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const VADStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
