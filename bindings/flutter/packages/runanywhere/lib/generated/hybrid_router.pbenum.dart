// This is a generated file - do not edit.
//
// Generated from hybrid_router.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Firebase AI Logic / developer.android.com InferenceMode, verbatim.
/// PREFER_* falls back silently across the boundary; ONLY_* fails instead.
class HybridInferenceMode extends $pb.ProtobufEnum {
  /// Treated as PREFER_ON_DEVICE, so the proto3 zero is the private default.
  static const HybridInferenceMode HYBRID_INFERENCE_MODE_UNSPECIFIED =
      HybridInferenceMode._(
          0, _omitEnumNames ? '' : 'HYBRID_INFERENCE_MODE_UNSPECIFIED');
  static const HybridInferenceMode HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE =
      HybridInferenceMode._(
          1, _omitEnumNames ? '' : 'HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE');
  static const HybridInferenceMode HYBRID_INFERENCE_MODE_ONLY_ON_DEVICE =
      HybridInferenceMode._(
          2, _omitEnumNames ? '' : 'HYBRID_INFERENCE_MODE_ONLY_ON_DEVICE');
  static const HybridInferenceMode HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD =
      HybridInferenceMode._(
          3, _omitEnumNames ? '' : 'HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD');
  static const HybridInferenceMode HYBRID_INFERENCE_MODE_ONLY_IN_CLOUD =
      HybridInferenceMode._(
          4, _omitEnumNames ? '' : 'HYBRID_INFERENCE_MODE_ONLY_IN_CLOUD');

  static const $core.List<HybridInferenceMode> values = <HybridInferenceMode>[
    HYBRID_INFERENCE_MODE_UNSPECIFIED,
    HYBRID_INFERENCE_MODE_PREFER_ON_DEVICE,
    HYBRID_INFERENCE_MODE_ONLY_ON_DEVICE,
    HYBRID_INFERENCE_MODE_PREFER_IN_CLOUD,
    HYBRID_INFERENCE_MODE_ONLY_IN_CLOUD,
  ];

  static final $core.List<HybridInferenceMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static HybridInferenceMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HybridInferenceMode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
