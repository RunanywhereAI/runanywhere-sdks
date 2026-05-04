// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_embeddings.dart - Embeddings capability.

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/embeddings_options.pb.dart'
    show EmbeddingsOptions, EmbeddingsRequest, EmbeddingsResult;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

/// Embeddings capability surface.
///
/// Access via `RunAnywhereSDK.instance.embeddings`. Mirrors Swift
/// `RunAnywhere.embed(text:modelId:options:)`.
class RunAnywhereEmbeddings {
  RunAnywhereEmbeddings._();
  static final RunAnywhereEmbeddings _instance = RunAnywhereEmbeddings._();
  static RunAnywhereEmbeddings get shared => _instance;

  /// Generate an embedding vector for a single text.
  ///
  /// Returns an [EmbeddingsResult] containing one vector under `vectors[0]`.
  /// - [text]: the input text to embed.
  /// - [modelId]: the embeddings model identifier (registry id or path).
  /// - [options]: optional per-call overrides.
  Future<EmbeddingsResult> embed(
    String text, {
    required String modelId,
    EmbeddingsOptions? options,
  }) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    return embedBatch(
      EmbeddingsRequest(texts: [text], options: options),
      modelId: modelId,
    );
  }

  Future<EmbeddingsResult> embedBatch(
    EmbeddingsRequest request, {
    required String modelId,
  }) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    if (DartBridge.embeddings.currentModelId != modelId) {
      final models = await RunAnywhereModels.shared.available();
      final model = models.where((m) => m.id == modelId).firstOrNull;
      if (model == null) {
        throw SDKException.modelNotFound(
            'Embeddings model not found: $modelId');
      }
      if (model.localPath.isEmpty) {
        throw SDKException.modelNotDownloaded(
          'Embeddings model is not downloaded. Call downloadModel() first.',
        );
      }
      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKException.modelNotFound(
          'Could not resolve embeddings model file path for: $modelId',
        );
      }
      DartBridge.embeddings.load(modelId, resolvedPath);
    }

    return DartBridge.embeddings.embedBatch(request);
  }

  Future<void> unload() async => DartBridge.embeddings.unload();
}
