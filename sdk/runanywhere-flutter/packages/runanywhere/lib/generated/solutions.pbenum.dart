//
//  Generated code. Do not modify.
//  source: solutions.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// SolutionType — discriminator for the kind of solution backing a
/// `SolutionConfig` / `SolutionHandle`. Mirrors the `SolutionConfig.config`
/// oneof arms so frontends can switch on a single enum value rather than
/// inspecting the oneof shape.
/// ---------------------------------------------------------------------------
class SolutionType extends $pb.ProtobufEnum {
  static const SolutionType SOLUTION_TYPE_UNSPECIFIED = SolutionType._(0, _omitEnumNames ? '' : 'SOLUTION_TYPE_UNSPECIFIED');
  static const SolutionType SOLUTION_TYPE_VOICE_AGENT = SolutionType._(1, _omitEnumNames ? '' : 'SOLUTION_TYPE_VOICE_AGENT');
  static const SolutionType SOLUTION_TYPE_RAG = SolutionType._(2, _omitEnumNames ? '' : 'SOLUTION_TYPE_RAG');
  static const SolutionType SOLUTION_TYPE_WAKEWORD = SolutionType._(3, _omitEnumNames ? '' : 'SOLUTION_TYPE_WAKEWORD');
  static const SolutionType SOLUTION_TYPE_TIME_SERIES = SolutionType._(4, _omitEnumNames ? '' : 'SOLUTION_TYPE_TIME_SERIES');
  static const SolutionType SOLUTION_TYPE_AGENT_LOOP = SolutionType._(5, _omitEnumNames ? '' : 'SOLUTION_TYPE_AGENT_LOOP');

  static const $core.List<SolutionType> values = <SolutionType> [
    SOLUTION_TYPE_UNSPECIFIED,
    SOLUTION_TYPE_VOICE_AGENT,
    SOLUTION_TYPE_RAG,
    SOLUTION_TYPE_WAKEWORD,
    SOLUTION_TYPE_TIME_SERIES,
    SOLUTION_TYPE_AGENT_LOOP,
  ];

  static final $core.Map<$core.int, SolutionType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static SolutionType? valueOf($core.int value) => _byValue[value];

  const SolutionType._($core.int v, $core.String n) : super(v, n);
}

class AudioSource extends $pb.ProtobufEnum {
  static const AudioSource AUDIO_SOURCE_UNSPECIFIED = AudioSource._(0, _omitEnumNames ? '' : 'AUDIO_SOURCE_UNSPECIFIED');
  static const AudioSource AUDIO_SOURCE_MICROPHONE = AudioSource._(1, _omitEnumNames ? '' : 'AUDIO_SOURCE_MICROPHONE');
  static const AudioSource AUDIO_SOURCE_FILE = AudioSource._(2, _omitEnumNames ? '' : 'AUDIO_SOURCE_FILE');
  static const AudioSource AUDIO_SOURCE_CALLBACK = AudioSource._(3, _omitEnumNames ? '' : 'AUDIO_SOURCE_CALLBACK');

  static const $core.List<AudioSource> values = <AudioSource> [
    AUDIO_SOURCE_UNSPECIFIED,
    AUDIO_SOURCE_MICROPHONE,
    AUDIO_SOURCE_FILE,
    AUDIO_SOURCE_CALLBACK,
  ];

  static final $core.Map<$core.int, AudioSource> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AudioSource? valueOf($core.int value) => _byValue[value];

  const AudioSource._($core.int v, $core.String n) : super(v, n);
}

class VectorStore extends $pb.ProtobufEnum {
  static const VectorStore VECTOR_STORE_UNSPECIFIED = VectorStore._(0, _omitEnumNames ? '' : 'VECTOR_STORE_UNSPECIFIED');
  static const VectorStore VECTOR_STORE_USEARCH = VectorStore._(1, _omitEnumNames ? '' : 'VECTOR_STORE_USEARCH');
  static const VectorStore VECTOR_STORE_PGVECTOR = VectorStore._(2, _omitEnumNames ? '' : 'VECTOR_STORE_PGVECTOR');

  static const $core.List<VectorStore> values = <VectorStore> [
    VECTOR_STORE_UNSPECIFIED,
    VECTOR_STORE_USEARCH,
    VECTOR_STORE_PGVECTOR,
  ];

  static final $core.Map<$core.int, VectorStore> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VectorStore? valueOf($core.int value) => _byValue[value];

  const VectorStore._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
