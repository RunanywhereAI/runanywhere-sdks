// This is a generated file - do not edit.
//
// Generated from diarization.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class DiarizationStreamEventKind extends $pb.ProtobufEnum {
  static const DiarizationStreamEventKind
      DIARIZATION_STREAM_EVENT_KIND_UNSPECIFIED = DiarizationStreamEventKind._(
          0, _omitEnumNames ? '' : 'DIARIZATION_STREAM_EVENT_KIND_UNSPECIFIED');
  static const DiarizationStreamEventKind
      DIARIZATION_STREAM_EVENT_KIND_STARTED = DiarizationStreamEventKind._(
          1, _omitEnumNames ? '' : 'DIARIZATION_STREAM_EVENT_KIND_STARTED');
  static const DiarizationStreamEventKind DIARIZATION_STREAM_EVENT_KIND_UPDATE =
      DiarizationStreamEventKind._(
          2, _omitEnumNames ? '' : 'DIARIZATION_STREAM_EVENT_KIND_UPDATE');
  static const DiarizationStreamEventKind DIARIZATION_STREAM_EVENT_KIND_FINAL =
      DiarizationStreamEventKind._(
          3, _omitEnumNames ? '' : 'DIARIZATION_STREAM_EVENT_KIND_FINAL');
  static const DiarizationStreamEventKind DIARIZATION_STREAM_EVENT_KIND_ERROR =
      DiarizationStreamEventKind._(
          4, _omitEnumNames ? '' : 'DIARIZATION_STREAM_EVENT_KIND_ERROR');

  static const $core.List<DiarizationStreamEventKind> values =
      <DiarizationStreamEventKind>[
    DIARIZATION_STREAM_EVENT_KIND_UNSPECIFIED,
    DIARIZATION_STREAM_EVENT_KIND_STARTED,
    DIARIZATION_STREAM_EVENT_KIND_UPDATE,
    DIARIZATION_STREAM_EVENT_KIND_FINAL,
    DIARIZATION_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<DiarizationStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static DiarizationStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const DiarizationStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
