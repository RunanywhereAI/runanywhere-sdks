// SPDX-License-Identifier: Apache-2.0
//
// Generated-proto RAG session bridge.

import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/rag.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

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

  /// Ingest a document, running the blocking chunk→embed→index work in a
  /// short-lived worker isolate (`Isolate.run`) so the calling isolate — usually
  /// the Flutter UI isolate — stays responsive. The RAG session is process-
  /// global C++ state (in-memory, mutex-protected vector store + ONNX
  /// embeddings + llama.cpp, no file I/O on this path), so its address is valid
  /// on the worker; this is the same cross-isolate engine use that
  /// `dart_bridge_llm.dart`'s worker already relies on.
  Future<RAGStatistics> ingestDocumentAsync(RAGDocument document) async {
    final session = _requireSession();
    if (RacNative.bindings.rac_rag_ingest_proto == null) {
      throw UnsupportedError('rac_rag_ingest_proto is unavailable');
    }
    final sessionAddr = session.address;
    final requestBytes = document.writeToBuffer();
    final resultBytes =
        await Isolate.run(() => _ragIngestWorker(sessionAddr, requestBytes));
    return RAGStatistics.fromBuffer(resultBytes);
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

  /// Query the pipeline, running the blocking embed→retrieve→LLM-generate work
  /// in a short-lived worker isolate (`Isolate.run`) so the calling isolate —
  /// usually the Flutter UI isolate — stays responsive for the whole answer.
  /// `rac_rag_query_proto` runs the LLM generation inline (max_tokens/
  /// temperature/system_prompt), so this is the heavy chat call. Same
  /// cross-isolate engine use as `dart_bridge_llm.dart` (see
  /// [ingestDocumentAsync]); the synchronous [query] is retained for callers
  /// that need it.
  Future<RAGResult> queryAsync(RAGQueryOptions options) async {
    final session = _requireSession();
    if (RacNative.bindings.rac_rag_query_proto == null) {
      throw UnsupportedError('rac_rag_query_proto is unavailable');
    }
    final sessionAddr = session.address;
    final requestBytes = options.writeToBuffer();
    final resultBytes =
        await Isolate.run(() => _ragQueryWorker(sessionAddr, requestBytes));
    return RAGResult.fromBuffer(resultBytes);
  }

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

// MARK: - Worker-isolate entry points
//
// Top-level so the `Isolate.run` closures capture only sendable values (the
// session address as an int + the request `Uint8List`). The RAG session is
// process-global C++ state, so `Pointer.fromAddress` reconstitutes a valid
// pointer on the worker isolate; the session's ONNX embeddings + llama.cpp LLM
// are invoked cross-isolate exactly as `dart_bridge_llm.dart`'s worker does,
// and the vector store is in-memory + mutex-protected (no file I/O on these
// paths). `RacNative.bindings` re-resolves the dylib symbols on first access
// (idempotent `PlatformLoader.loadCommons()`). Each returns the serialized
// proto result so the calling isolate owns the decode.

Uint8List _ragIngestWorker(int sessionAddr, Uint8List requestBytes) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_rag_ingest_proto;
  if (fn == null) {
    throw UnsupportedError('rac_rag_ingest_proto is unavailable');
  }
  final session = ffi.Pointer<ffi.Void>.fromAddress(sessionAddr);
  final reqPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  final out = calloc<RacProtoBuffer>();
  try {
    bindings.rac_proto_buffer_init(out);
    final code = fn(session, reqPtr, requestBytes.length, out);
    DartBridgeProtoUtils.ensureSuccess(out, code, 'rac_rag_ingest_proto');
    if (out.ref.data == ffi.nullptr || out.ref.size == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(out.ref.data.asTypedList(out.ref.size));
  } finally {
    bindings.rac_proto_buffer_free(out);
    calloc.free(reqPtr);
    calloc.free(out);
  }
}

Uint8List _ragQueryWorker(int sessionAddr, Uint8List requestBytes) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_rag_query_proto;
  if (fn == null) {
    throw UnsupportedError('rac_rag_query_proto is unavailable');
  }
  final session = ffi.Pointer<ffi.Void>.fromAddress(sessionAddr);
  final reqPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  final out = calloc<RacProtoBuffer>();
  try {
    bindings.rac_proto_buffer_init(out);
    final code = fn(session, reqPtr, requestBytes.length, out);
    DartBridgeProtoUtils.ensureSuccess(out, code, 'rac_rag_query_proto');
    if (out.ref.data == ffi.nullptr || out.ref.size == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(out.ref.data.asTypedList(out.ref.size));
  } finally {
    bindings.rac_proto_buffer_free(out);
    calloc.free(reqPtr);
    calloc.free(out);
  }
}
