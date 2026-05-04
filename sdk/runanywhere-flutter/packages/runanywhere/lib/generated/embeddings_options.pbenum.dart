//
//  Generated code. Do not modify.
//  source: embeddings_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Embedding normalization mode. Mirrors rac_embeddings_normalize_t.
/// ---------------------------------------------------------------------------
class EmbeddingsNormalizeMode extends $pb.ProtobufEnum {
  static const EmbeddingsNormalizeMode EMBEDDINGS_NORMALIZE_MODE_UNSPECIFIED = EmbeddingsNormalizeMode._(0, _omitEnumNames ? '' : 'EMBEDDINGS_NORMALIZE_MODE_UNSPECIFIED');
  static const EmbeddingsNormalizeMode EMBEDDINGS_NORMALIZE_MODE_NONE = EmbeddingsNormalizeMode._(1, _omitEnumNames ? '' : 'EMBEDDINGS_NORMALIZE_MODE_NONE');
  static const EmbeddingsNormalizeMode EMBEDDINGS_NORMALIZE_MODE_L2 = EmbeddingsNormalizeMode._(2, _omitEnumNames ? '' : 'EMBEDDINGS_NORMALIZE_MODE_L2');

  static const $core.List<EmbeddingsNormalizeMode> values = <EmbeddingsNormalizeMode> [
    EMBEDDINGS_NORMALIZE_MODE_UNSPECIFIED,
    EMBEDDINGS_NORMALIZE_MODE_NONE,
    EMBEDDINGS_NORMALIZE_MODE_L2,
  ];

  static final $core.Map<$core.int, EmbeddingsNormalizeMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EmbeddingsNormalizeMode? valueOf($core.int value) => _byValue[value];

  const EmbeddingsNormalizeMode._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Embedding pooling strategy. Mirrors rac_embeddings_pooling_t.
/// ---------------------------------------------------------------------------
class EmbeddingsPoolingStrategy extends $pb.ProtobufEnum {
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED = EmbeddingsPoolingStrategy._(0, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED');
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_MEAN = EmbeddingsPoolingStrategy._(1, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_MEAN');
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_CLS = EmbeddingsPoolingStrategy._(2, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_CLS');
  static const EmbeddingsPoolingStrategy EMBEDDINGS_POOLING_STRATEGY_LAST = EmbeddingsPoolingStrategy._(3, _omitEnumNames ? '' : 'EMBEDDINGS_POOLING_STRATEGY_LAST');

  static const $core.List<EmbeddingsPoolingStrategy> values = <EmbeddingsPoolingStrategy> [
    EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED,
    EMBEDDINGS_POOLING_STRATEGY_MEAN,
    EMBEDDINGS_POOLING_STRATEGY_CLS,
    EMBEDDINGS_POOLING_STRATEGY_LAST,
  ];

  static final $core.Map<$core.int, EmbeddingsPoolingStrategy> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EmbeddingsPoolingStrategy? valueOf($core.int value) => _byValue[value];

  const EmbeddingsPoolingStrategy._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
