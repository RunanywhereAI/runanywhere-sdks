// This is a generated file - do not edit.
//
// Generated from embeddings_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class EmbeddingsPoolingStrategy extends $pb.ProtobufEnum {
  static const EmbeddingsPoolingStrategy
      EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED = EmbeddingsPoolingStrategy._(
          0, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED');
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_MEAN =
      EmbeddingsPoolingStrategy._(
          1, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_MEAN');
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_CLS =
      EmbeddingsPoolingStrategy._(
          2, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_CLS');
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_LAST =
      EmbeddingsPoolingStrategy._(
          3, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_LAST');

  static const $core.List<EmbeddingsPoolingStrategy> values =
      <EmbeddingsPoolingStrategy>[
    EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED,
    EMBEDDINGS_POOLING_STRATEGY_MEAN,
    EMBEDDINGS_POOLING_STRATEGY_CLS,
    EMBEDDINGS_POOLING_STRATEGY_LAST,
  ];

  static final $core.List<EmbeddingsPoolingStrategy?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static EmbeddingsPoolingStrategy? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EmbeddingsPoolingStrategy._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
