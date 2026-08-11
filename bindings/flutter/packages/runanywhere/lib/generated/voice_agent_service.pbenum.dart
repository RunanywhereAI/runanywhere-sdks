// This is a generated file - do not edit.
//
// Generated from voice_agent_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class TurnDetection_Type extends $pb.ProtobufEnum {
  static const TurnDetection_Type TURN_DETECTION_TYPE_UNSPECIFIED =
      TurnDetection_Type._(
          0, _omitEnumNames ? '' : 'TURN_DETECTION_TYPE_UNSPECIFIED');
  static const TurnDetection_Type TURN_DETECTION_TYPE_VAD =
      TurnDetection_Type._(1, _omitEnumNames ? '' : 'TURN_DETECTION_TYPE_VAD');
  static const TurnDetection_Type TURN_DETECTION_TYPE_MANUAL =
      TurnDetection_Type._(
          2, _omitEnumNames ? '' : 'TURN_DETECTION_TYPE_MANUAL');

  static const $core.List<TurnDetection_Type> values = <TurnDetection_Type>[
    TURN_DETECTION_TYPE_UNSPECIFIED,
    TURN_DETECTION_TYPE_VAD,
    TURN_DETECTION_TYPE_MANUAL,
  ];

  static final $core.List<TurnDetection_Type?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static TurnDetection_Type? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TurnDetection_Type._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
