// SPDX-License-Identifier: Apache-2.0
//
// Embeddings capability backed by commons model lifecycle and lifecycle-owned
// generated-proto embedding.

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart'
    show ComponentLifecycleState;
import 'package:runanywhere/generated/embeddings_options.pb.dart'
    show EmbeddingsOptions, EmbeddingsRequest, EmbeddingsResult;
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_embeddings.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// Embeddings capability surface.
///
/// Access via `RunAnywhere.embeddings`. Model load/current/unload
/// state is owned by commons lifecycle; embed calls use the lifecycle-owned
/// generated-proto commons ABI.
class RunAnywhereEmbeddings {
  RunAnywhereEmbeddings._();
  static final RunAnywhereEmbeddings _instance = RunAnywhereEmbeddings._();
  static RunAnywhereEmbeddings get shared => _instance;

  /// True when commons lifecycle has a ready embeddings model.
  bool get isLoaded {
    final snapshot = _lifecycleSnapshot;
    return snapshot != null &&
        snapshot.state ==
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY &&
        snapshot.modelId.isNotEmpty;
  }

  /// Currently-loaded embeddings model id, or null.
  String? get currentModelId {
    final snapshot = _lifecycleSnapshot;
    if (snapshot == null ||
        snapshot.state !=
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ||
        snapshot.modelId.isEmpty) {
      return null;
    }
    return snapshot.modelId;
  }

  /// Generate an embedding vector for a single text.
  Future<EmbeddingsResult> embed(
    String text, {
    required String modelId,
    EmbeddingsOptions? options,
  }) async {
    if (!DartBridge.isInitialized) {
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
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    await _ensureLoaded(modelId);
    final lifecycleRequest = request.deepCopy();
    if (lifecycleRequest.modelId.isNotEmpty &&
        lifecycleRequest.modelId != modelId) {
      throw SDKException.invalidInput(
        'EmbeddingsRequest.model_id does not match requested modelId',
      );
    }
    lifecycleRequest.modelId = modelId;
    return DartBridgeEmbeddings.shared.embedBatchAsync(lifecycleRequest);
  }

  Future<void> unload() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final modelId = currentModelId ??
        (await RunAnywhereModelLifecycle.shared.current(
          model_pb.CurrentModelRequest(category: _embeddingsCategory),
        ))
            .modelId;
    if (modelId.isEmpty) return;

    final result = await RunAnywhereModelLifecycle.shared.unload(
      model_pb.ModelUnloadRequest(
        modelId: modelId,
        category: _embeddingsCategory,
      ),
    );
    if (!result.success) {
      throw SDKException.invalidState(
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'Embeddings lifecycle unload failed',
      );
    }
  }

  Future<void> _ensureLoaded(String modelId) async {
    if (currentModelId == modelId) return;
    final current = await RunAnywhereModelLifecycle.shared.current(
      model_pb.CurrentModelRequest(category: _embeddingsCategory),
    );
    if (current.found && current.modelId == modelId) return;

    final result = await RunAnywhereModelLifecycle.shared.load(
      model_pb.ModelLoadRequest(
        modelId: modelId,
        category: _embeddingsCategory,
        forceReload: true,
        validateAvailability: true,
      ),
    );
    if (!result.success) {
      throw SDKException.modelLoadFailed(
        modelId,
        result.errorMessage.isNotEmpty
            ? result.errorMessage
            : 'Embeddings lifecycle load failed',
      );
    }
  }

  ComponentLifecycleSnapshot? get _lifecycleSnapshot =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(
        SDKComponent.SDK_COMPONENT_EMBEDDINGS,
      );

  static const _embeddingsCategory =
      model_pb.ModelCategory.MODEL_CATEGORY_EMBEDDING;
}
