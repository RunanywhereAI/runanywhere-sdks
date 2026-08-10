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
