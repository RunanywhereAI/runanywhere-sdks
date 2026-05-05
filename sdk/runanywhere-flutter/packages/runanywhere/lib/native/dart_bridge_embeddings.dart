// SPDX-License-Identifier: Apache-2.0
//
// Thin generated-proto embeddings bridge. Commons lifecycle owns the loaded
// embeddings service; Dart passes generated request bytes and receives
// generated result bytes.

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

  void _validateRequest(EmbeddingsRequest request) {
    if (request.texts.where((text) => text.isNotEmpty).isEmpty) {
      throw ArgumentError('EmbeddingsRequest.texts is required');
    }
  }
}
