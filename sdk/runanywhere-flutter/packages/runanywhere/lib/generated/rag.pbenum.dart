// This is a generated file - do not edit.
//
// Generated from rag.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class RAGStreamEventKind extends $pb.ProtobufEnum {
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_UNSPECIFIED =
      RAGStreamEventKind._(
          0, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_UNSPECIFIED');
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED =
      RAGStreamEventKind._(
          1, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED');
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED =
      RAGStreamEventKind._(
          2, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED');
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_CONTEXT_READY =
      RAGStreamEventKind._(
          3, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_CONTEXT_READY');
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_TOKEN =
      RAGStreamEventKind._(
          4, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_TOKEN');
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_COMPLETED =
      RAGStreamEventKind._(
          5, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_COMPLETED');
  static const RAGStreamEventKind RAG_STREAM_EVENT_KIND_ERROR =
      RAGStreamEventKind._(
          6, _omitEnumNames ? '' : 'RAG_STREAM_EVENT_KIND_ERROR');

  static const $core.List<RAGStreamEventKind> values = <RAGStreamEventKind>[
    RAG_STREAM_EVENT_KIND_UNSPECIFIED,
    RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED,
    RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED,
    RAG_STREAM_EVENT_KIND_CONTEXT_READY,
    RAG_STREAM_EVENT_KIND_TOKEN,
    RAG_STREAM_EVENT_KIND_COMPLETED,
    RAG_STREAM_EVENT_KIND_ERROR,
  ];

  static final $core.List<RAGStreamEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static RAGStreamEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RAGStreamEventKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
