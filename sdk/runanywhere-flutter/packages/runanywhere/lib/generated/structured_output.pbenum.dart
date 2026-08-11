// This is a generated file - do not edit.
//
// Generated from structured_output.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// How commons applies StructuredOutputOptions on the ordinary LLM generate
/// path. Platform SDKs must not invent a second policy.
class StructuredOutputMode extends $pb.ProtobufEnum {
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_UNSPECIFIED =
      StructuredOutputMode._(
          0, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_UNSPECIFIED');

  /// Compile schema→GBNF (or honor grammar/regex) and constrain decoding.
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_CONSTRAINED =
      StructuredOutputMode._(
          1, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_CONSTRAINED');

  /// Do not constrain decoding; validate the free-text result against schema.
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_VALIDATION_ONLY =
      StructuredOutputMode._(
          2, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_VALIDATION_ONLY');

  /// Constrained (when a decoder arm is present), then one repair retry if
  /// the first answer fails schema validation.
  static const StructuredOutputMode STRUCTURED_OUTPUT_MODE_REPAIR =
      StructuredOutputMode._(
          3, _omitEnumNames ? '' : 'STRUCTURED_OUTPUT_MODE_REPAIR');

  static const $core.List<StructuredOutputMode> values = <StructuredOutputMode>[
    STRUCTURED_OUTPUT_MODE_UNSPECIFIED,
    STRUCTURED_OUTPUT_MODE_CONSTRAINED,
    STRUCTURED_OUTPUT_MODE_VALIDATION_ONLY,
    STRUCTURED_OUTPUT_MODE_REPAIR,
  ];

  static final $core.List<StructuredOutputMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static StructuredOutputMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const StructuredOutputMode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
