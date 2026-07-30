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

class HybridBackendKind extends $pb.ProtobufEnum {
  static const HybridBackendKind HYBRID_BACKEND_UNSPECIFIED =
      HybridBackendKind._(
          0, _omitEnumNames ? '' : 'HYBRID_BACKEND_UNSPECIFIED');
  static const HybridBackendKind HYBRID_BACKEND_LLAMACPP =
      HybridBackendKind._(1, _omitEnumNames ? '' : 'HYBRID_BACKEND_LLAMACPP');
  static const HybridBackendKind HYBRID_BACKEND_OPENROUTER =
      HybridBackendKind._(2, _omitEnumNames ? '' : 'HYBRID_BACKEND_OPENROUTER');
  static const HybridBackendKind HYBRID_BACKEND_SHERPA =
      HybridBackendKind._(3, _omitEnumNames ? '' : 'HYBRID_BACKEND_SHERPA');
  static const HybridBackendKind HYBRID_BACKEND_CLOUD =
      HybridBackendKind._(4, _omitEnumNames ? '' : 'HYBRID_BACKEND_CLOUD');

  static const $core.List<HybridBackendKind> values = <HybridBackendKind>[
    HYBRID_BACKEND_UNSPECIFIED,
    HYBRID_BACKEND_LLAMACPP,
    HYBRID_BACKEND_OPENROUTER,
    HYBRID_BACKEND_SHERPA,
    HYBRID_BACKEND_CLOUD,
  ];

  static final $core.List<HybridBackendKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static HybridBackendKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HybridBackendKind._(super.value, super.name);
}

class HybridModelType extends $pb.ProtobufEnum {
  static const HybridModelType HYBRID_MODEL_TYPE_UNSPECIFIED =
      HybridModelType._(
          0, _omitEnumNames ? '' : 'HYBRID_MODEL_TYPE_UNSPECIFIED');
  static const HybridModelType HYBRID_MODEL_TYPE_OFFLINE =
      HybridModelType._(1, _omitEnumNames ? '' : 'HYBRID_MODEL_TYPE_OFFLINE');
  static const HybridModelType HYBRID_MODEL_TYPE_ONLINE =
      HybridModelType._(2, _omitEnumNames ? '' : 'HYBRID_MODEL_TYPE_ONLINE');

  static const $core.List<HybridModelType> values = <HybridModelType>[
    HYBRID_MODEL_TYPE_UNSPECIFIED,
    HYBRID_MODEL_TYPE_OFFLINE,
    HYBRID_MODEL_TYPE_ONLINE,
  ];

  static final $core.List<HybridModelType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static HybridModelType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HybridModelType._(super.value, super.name);
}

class HybridRank extends $pb.ProtobufEnum {
  static const HybridRank HYBRID_RANK_UNSPECIFIED =
      HybridRank._(0, _omitEnumNames ? '' : 'HYBRID_RANK_UNSPECIFIED');
  static const HybridRank HYBRID_RANK_PREFER_LOCAL_FIRST =
      HybridRank._(1, _omitEnumNames ? '' : 'HYBRID_RANK_PREFER_LOCAL_FIRST');
  static const HybridRank HYBRID_RANK_PREFER_ONLINE_FIRST =
      HybridRank._(2, _omitEnumNames ? '' : 'HYBRID_RANK_PREFER_ONLINE_FIRST');

  static const $core.List<HybridRank> values = <HybridRank>[
    HYBRID_RANK_UNSPECIFIED,
    HYBRID_RANK_PREFER_LOCAL_FIRST,
    HYBRID_RANK_PREFER_ONLINE_FIRST,
  ];

  static final $core.List<HybridRank?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static HybridRank? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HybridRank._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
