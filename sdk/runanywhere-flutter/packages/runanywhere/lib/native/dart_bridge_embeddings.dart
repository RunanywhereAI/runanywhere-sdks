// SPDX-License-Identifier: Apache-2.0
//
// Thin generated-proto embeddings bridge. Commons lifecycle owns the loaded
// embeddings service; Dart passes generated request bytes and receives
// generated result bytes.

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/embeddings_options.pb.dart'
    show EmbeddingsRequest, EmbeddingsResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

class DartBridgeEmbeddings {
  DartBridgeEmbeddings._();
  static final DartBridgeEmbeddings shared = DartBridgeEmbeddings._();

  static EmbeddingsResult Function(EmbeddingsRequest)?
      _embedBatchLifecycleProtoForTesting;

  static void setEmbedBatchLifecycleProtoForTesting(
    EmbeddingsResult Function(EmbeddingsRequest)? override,
  ) {
    _embedBatchLifecycleProtoForTesting = override;
  }

  /// Synchronous variant retained for the unit-test harness (which drives it
  /// with [setEmbedBatchLifecycleProtoForTesting]). Production callers use
  /// [embedBatchAsync], which runs the blocking native call off the UI isolate.
  EmbeddingsResult embedBatch(EmbeddingsRequest request) {
    _validateRequest(request);

    final override = _embedBatchLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    final fn = RacNative.bindings.rac_embeddings_embed_batch_lifecycle_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_embeddings_embed_batch_lifecycle_proto is unavailable',
      );
    }

    return DartBridgeProtoUtils.callRequest<EmbeddingsResult>(
      request: request,
      invoke: fn,
      decode: EmbeddingsResult.fromBuffer,
      symbol: 'rac_embeddings_embed_batch_lifecycle_proto',
    );
  }

  /// Embed a batch through the lifecycle-owned generated-proto ABI, running the
  /// blocking native call in a short-lived worker isolate (`Isolate.run`) so the
  /// calling isolate — usually the Flutter UI isolate — stays responsive.
  /// Embedding a large batch (e.g. RAG ingest) is a long synchronous block; on
  /// the UI isolate it freezes frames. Mirrors `dart_bridge_stt.dart`'s
  /// `transcribeLifecycleProtoAsync`: this ABI is lifecycle-owned (no Dart-held
  /// handle), so the worker re-resolves the engine via the commons model
  /// lifecycle — nothing isolate-bound crosses.
  Future<EmbeddingsResult> embedBatchAsync(EmbeddingsRequest request) async {
    _validateRequest(request);

    final override = _embedBatchLifecycleProtoForTesting;
    if (override != null) {
      return override(request);
    }

    if (RacNative.bindings.rac_embeddings_embed_batch_lifecycle_proto == null) {
      throw UnsupportedError(
        'rac_embeddings_embed_batch_lifecycle_proto is unavailable',
      );
    }

    final requestBytes = request.writeToBuffer();
    final resultBytes =
        await Isolate.run(() => _embeddingsEmbedBatchWorker(requestBytes));
    return EmbeddingsResult.fromBuffer(resultBytes);
  }

  void _validateRequest(EmbeddingsRequest request) {
    if (request.texts.where((text) => text.isNotEmpty).isEmpty) {
      throw ArgumentError('EmbeddingsRequest.texts is required');
    }
  }
}

/// Blocking body of [DartBridgeEmbeddings.embedBatchAsync]: a plain
/// request→response proto call with no callbacks. Top-level so the
/// `Isolate.run` closure captures only its sendable `Uint8List` argument.
/// `RacNative.bindings` is a per-isolate static — the worker re-resolves the
/// dylib symbols on first access (idempotent `PlatformLoader.loadCommons()`,
/// same convention as the LLM/STT/TTS workers). Returns the serialized
/// EmbeddingsResult so the main isolate owns the decode.
Uint8List _embeddingsEmbedBatchWorker(Uint8List requestBytes) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_embeddings_embed_batch_lifecycle_proto;
  if (fn == null) {
    throw UnsupportedError(
      'rac_embeddings_embed_batch_lifecycle_proto is unavailable',
    );
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  final out = calloc<RacProtoBuffer>();
  try {
    bindings.rac_proto_buffer_init(out);
    final code = fn(requestPtr, requestBytes.length, out);
    DartBridgeProtoUtils.ensureSuccess(
      out,
      code,
      'rac_embeddings_embed_batch_lifecycle_proto',
    );
    if (out.ref.data == nullptr || out.ref.size == 0) {
      return Uint8List(0);
    }
    return Uint8List.fromList(out.ref.data.asTypedList(out.ref.size));
  } finally {
    bindings.rac_proto_buffer_free(out);
    calloc.free(out);
    calloc.free(requestPtr);
  }
}
