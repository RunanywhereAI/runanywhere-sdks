///
//  Generated code. Do not modify.
//  source: solutions.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class SolutionType extends $pb.ProtobufEnum {
  static const SolutionType SOLUTION_TYPE_UNSPECIFIED = SolutionType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SOLUTION_TYPE_UNSPECIFIED');
  static const SolutionType SOLUTION_TYPE_VOICE_AGENT = SolutionType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SOLUTION_TYPE_VOICE_AGENT');
  static const SolutionType SOLUTION_TYPE_RAG = SolutionType._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SOLUTION_TYPE_RAG');
  static const SolutionType SOLUTION_TYPE_WAKEWORD = SolutionType._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SOLUTION_TYPE_WAKEWORD');
  static const SolutionType SOLUTION_TYPE_TIME_SERIES = SolutionType._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SOLUTION_TYPE_TIME_SERIES');
  static const SolutionType SOLUTION_TYPE_AGENT_LOOP = SolutionType._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SOLUTION_TYPE_AGENT_LOOP');

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
  static const AudioSource AUDIO_SOURCE_UNSPECIFIED = AudioSource._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_SOURCE_UNSPECIFIED');
  static const AudioSource AUDIO_SOURCE_MICROPHONE = AudioSource._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_SOURCE_MICROPHONE');
  static const AudioSource AUDIO_SOURCE_FILE = AudioSource._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_SOURCE_FILE');
  static const AudioSource AUDIO_SOURCE_CALLBACK = AudioSource._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_SOURCE_CALLBACK');

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
  static const VectorStore VECTOR_STORE_UNSPECIFIED = VectorStore._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VECTOR_STORE_UNSPECIFIED');
  static const VectorStore VECTOR_STORE_USEARCH = VectorStore._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VECTOR_STORE_USEARCH');
  static const VectorStore VECTOR_STORE_PGVECTOR = VectorStore._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VECTOR_STORE_PGVECTOR');

  static const $core.List<VectorStore> values = <VectorStore> [
    VECTOR_STORE_UNSPECIFIED,
    VECTOR_STORE_USEARCH,
    VECTOR_STORE_PGVECTOR,
  ];

  static final $core.Map<$core.int, VectorStore> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VectorStore? valueOf($core.int value) => _byValue[value];

  const VectorStore._($core.int v, $core.String n) : super(v, n);
}

