// This is a generated file - do not edit.
//
// Generated from rac_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class Rac_options {
  static final racDefault = $pb.Extension<$core.String>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'racDefault',
      50001,
      $pb.PbFieldType.OS);
  static final racRequired = $pb.Extension<$core.bool>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'racRequired',
      50002,
      $pb.PbFieldType.OB);
  static final racMin = $pb.Extension<$core.int>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'racMin',
      50004,
      $pb.PbFieldType.O3);
  static final racMax = $pb.Extension<$core.int>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'racMax',
      50005,
      $pb.PbFieldType.O3);
  static final racMinFloat = $pb.Extension<$core.double>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'racMinFloat',
      50006,
      $pb.PbFieldType.OD);
  static final racMaxFloat = $pb.Extension<$core.double>(
      _omitMessageNames ? '' : 'google.protobuf.FieldOptions',
      _omitFieldNames ? '' : 'racMaxFloat',
      50007,
      $pb.PbFieldType.OD);
  static final racDisplayName = $pb.Extension<$core.String>(
      _omitMessageNames ? '' : 'google.protobuf.EnumValueOptions',
      _omitFieldNames ? '' : 'racDisplayName',
      50010,
      $pb.PbFieldType.OS);
  static final racAnalyticsKey = $pb.Extension<$core.String>(
      _omitMessageNames ? '' : 'google.protobuf.EnumValueOptions',
      _omitFieldNames ? '' : 'racAnalyticsKey',
      50011,
      $pb.PbFieldType.OS);
  static final racWireString = $pb.Extension<$core.String>(
      _omitMessageNames ? '' : 'google.protobuf.EnumValueOptions',
      _omitFieldNames ? '' : 'racWireString',
      50012,
      $pb.PbFieldType.OS);
  static void registerAllExtensions($pb.ExtensionRegistry registry) {
    registry.add(racDefault);
    registry.add(racRequired);
    registry.add(racMin);
    registry.add(racMax);
    registry.add(racMinFloat);
    registry.add(racMaxFloat);
    registry.add(racDisplayName);
    registry.add(racAnalyticsKey);
    registry.add(racWireString);
  }
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
