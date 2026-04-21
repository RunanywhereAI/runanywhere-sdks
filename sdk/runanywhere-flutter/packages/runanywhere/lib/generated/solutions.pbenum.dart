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
