// SPDX-License-Identifier: Apache-2.0
//
// Generated-proto RAG session bridge.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/rag.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

typedef _RagRegisterNative = ffi.Int32 Function();
typedef _RagRegisterDart = int Function();

class DartBridgeRAG {
  DartBridgeRAG._();
  static final DartBridgeRAG shared = DartBridgeRAG._();

  ffi.Pointer<ffi.Void>? _session;
  bool _registered = false;

  bool get isCreated => _session != null;

  void register() {
    if (_registered) return;

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagRegisterNative, _RagRegisterDart>(
      'rac_backend_rag_register',
    );
    final result = fn();
    if (result != RAC_SUCCESS && result != -401) {
      throw StateError(
        'rac_backend_rag_register failed: '
        '${RacResultCode.getMessage(result)}',
      );
    }
    _registered = true;
  }

  void unregister() {
    if (!_registered) return;

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagRegisterNative, _RagRegisterDart>(
      'rac_backend_rag_unregister',
    );
    final result = fn();
    if (result != RAC_SUCCESS && result != -401) {
      throw StateError(
        'rac_backend_rag_unregister failed: '
        '${RacResultCode.getMessage(result)}',
      );
    }
    _registered = false;
  }

  void createPipeline(RAGConfiguration config) {
    destroyPipeline();

    final fn = RacNative.bindings.rac_rag_session_create_proto;
    if (fn == null) {
      throw UnsupportedError('rac_rag_session_create_proto is unavailable');
    }

    final bytes = config.writeToBuffer();
    final ptr = DartBridgeProtoUtils.copyBytes(bytes);
    final out = calloc<ffi.Pointer<ffi.Void>>();

    try {
      final rc = fn(ptr, bytes.length, out);
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_rag_session_create_proto failed: '
          '${RacResultCode.getMessage(rc)}',
        );
      }
      _session = out.value;
    } finally {
      calloc.free(ptr);
      calloc.free(out);
    }
  }

  Future<void> createPipelineAsync(RAGConfiguration config) async =>
      createPipeline(config);

  void destroyPipeline() {
    final session = _session;
    if (session != null) {
      RacNative.bindings.rac_rag_session_destroy_proto?.call(session);
      _session = null;
    }
  }

  RAGStatistics ingestDocument(RAGDocument document) {
    final session = _requireSession();
    final fn = RacNative.bindings.rac_rag_ingest_proto;
    if (fn == null) {
      throw UnsupportedError('rac_rag_ingest_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<RAGStatistics>(
      handle: session,
      request: document,
      invoke: fn,
      decode: RAGStatistics.fromBuffer,
      symbol: 'rac_rag_ingest_proto',
    );
  }

  Future<RAGStatistics> addDocumentAsync(
    String text, {
    String? metadataJson,
  }) async {
    return ingestDocument(RAGDocument(text: text, metadataJson: metadataJson));
  }

  Future<RAGStatistics> addDocumentsBatchAsync(
    List<Map<String, String>> documents,
  ) async {
    RAGStatistics stats = RAGStatistics();
    for (final doc in documents) {
      stats = ingestDocument(RAGDocument(
        text: doc['text'] ?? '',
        metadataJson: doc['metadataJson'],
      ));
    }
    return stats;
  }

  RAGStatistics clearDocuments() {
    final session = _requireSession();
    final fn = RacNative.bindings.rac_rag_clear_proto;
    if (fn == null) {
      throw UnsupportedError('rac_rag_clear_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<RAGStatistics>(
      invoke: (out) => fn(session, out),
      decode: RAGStatistics.fromBuffer,
      symbol: 'rac_rag_clear_proto',
    );
  }

  int get documentCount {
    if (_session == null) return 0;
    return getStatistics().indexedChunks.toInt();
  }

  RAGResult query(RAGQueryOptions options) {
    final session = _requireSession();
    final fn = RacNative.bindings.rac_rag_query_proto;
    if (fn == null) {
      throw UnsupportedError('rac_rag_query_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<RAGResult>(
      handle: session,
      request: options,
      invoke: fn,
      decode: RAGResult.fromBuffer,
      symbol: 'rac_rag_query_proto',
    );
  }

  Future<RAGResult> queryAsync(RAGQueryOptions options) async => query(options);

  RAGStatistics getStatistics() {
    final session = _requireSession();
    final fn = RacNative.bindings.rac_rag_stats_proto;
    if (fn == null) {
      throw UnsupportedError('rac_rag_stats_proto is unavailable');
    }
    return DartBridgeProtoUtils.callOut<RAGStatistics>(
      invoke: (out) => fn(session, out),
      decode: RAGStatistics.fromBuffer,
      symbol: 'rac_rag_stats_proto',
    );
  }

  ffi.Pointer<ffi.Void> _requireSession() {
    final session = _session;
    if (session == null) {
      throw StateError(
          'RAG pipeline not created. Call createPipeline() first.');
    }
    return session;
  }
}
