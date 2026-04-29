// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_models.dart — v4 Models capability. Owns the model
// registry surface: listing available models, refreshing from
// filesystem, and registering new models (single-file + multi-file).

import 'dart:async';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_init.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;

/// Model registry capability surface.
///
/// Access via `RunAnywhereSDK.instance.models`.
class RunAnywhereModels {
  RunAnywhereModels._();
  static final RunAnywhereModels _instance = RunAnywhereModels._();
  static RunAnywhereModels get shared => _instance;

  /// All available models from the C++ registry, merged with metadata
  /// from Dart-registered models (download URLs, context lengths, etc.).
  ///
  /// Runs one-shot filesystem discovery on first call.
  Future<List<ModelInfo>> available() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    if (!SdkState.shared.hasRunDiscovery) {
      await runDiscovery();
      SdkState.shared.hasRunDiscovery = true;
    }

    final cppModels =
        await DartBridgeModelRegistry.instance.getAllPublicModels();

    final uniqueModels = <String, ModelInfo>{};

    for (final model in cppModels) {
      uniqueModels[model.id] = model;
    }

    for (final dartModel in SdkState.shared.registeredModels) {
      final existing = uniqueModels[dartModel.id];
      if (existing != null) {
        uniqueModels[dartModel.id] = ModelInfo(
          id: dartModel.id,
          name: dartModel.name,
          category: dartModel.category,
          format: dartModel.format,
          framework: dartModel.framework,
          downloadURL: dartModel.downloadURL,
          localPath: existing.localPath ?? dartModel.localPath,
          artifactType: dartModel.artifactType,
          downloadSize: dartModel.downloadSize,
          contextLength: dartModel.contextLength,
          supportsThinking: dartModel.supportsThinking,
          thinkingPattern: dartModel.thinkingPattern,
          description: dartModel.description,
          source: dartModel.source,
        );
      } else {
        uniqueModels[dartModel.id] = dartModel;
      }
    }

    return List.unmodifiable(uniqueModels.values.toList());
  }

  /// Refresh the model registry — canonical §13 cross-SDK unified
  /// surface (0-arg). Routes through the commons C ABI
  /// `rac_model_registry_refresh`; rescans local filesystem and
  /// fetches the backend catalog in one shot.
  Future<void> refreshModelRegistry() async {
    if (!SdkState.shared.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Discovery');

    final result =
        await DartBridgeModelRegistry.instance.discoverDownloadedModels();
    if (result.discoveredModels.isNotEmpty) {
      logger.info(
          'Discovery found ${result.discoveredModels.length} downloaded models');
    }

    final ok = await DartBridgeModelRegistry.instance.refresh(
      includeRemoteCatalog: true,
      pruneOrphans: false,
    );
    if (!ok) {
      logger.warning('rac_model_registry_refresh reported failure');
    }
  }

  /// Register a single-file model with the SDK.
  ///
  /// Mirrors Swift `RunAnywhere.registerModel(...)`. Saves the model
  /// to the C++ registry (fire-and-forget) so the backend can
  /// discover and load it.
  ModelInfo register({
    String? id,
    required String name,
    required Uri url,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.language,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final format = _inferFormat(url.path);

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: format,
      framework: framework,
      downloadURL: url,
      artifactType: artifactType ?? ModelArtifactType.infer(url, format),
      downloadSize: memoryRequirement,
      supportsThinking: supportsThinking,
      source: ModelSource.local,
    );

    SdkState.shared.registeredModels.add(model);
    _saveToCppRegistry(model);
    return model;
  }

  /// Register a multi-file model (e.g. embedding model.onnx + vocab.txt).
  ModelInfo registerMultiFile({
    String? id,
    required String name,
    required List<ModelFileDescriptor> files,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.embedding,
    int? memoryRequirement,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');
    final primaryUrl = files.isNotEmpty ? files.first.url : null;

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: ModelFormat.onnx,
      framework: framework,
      downloadURL: primaryUrl,
      artifactType: MultiFileArtifact(files: files),
      downloadSize: memoryRequirement,
      source: ModelSource.local,
    );

    SdkState.shared.registeredModels.add(model);
    _saveToCppRegistry(model);
    return model;
  }

  /// Update the download status / local path for a model in the C++
  /// registry. Called by `ModelDownloadService` after a successful
  /// download.
  Future<void> updateDownloadStatus(String modelId, String? localPath) =>
      DartBridgeModelRegistry.instance.updateDownloadStatus(modelId, localPath);

  /// Remove a model from the C++ registry (called on delete).
  Future<void> remove(String modelId) =>
      DartBridgeModelRegistry.instance.removeModel(modelId);

  // -- private helpers ------------------------------------------------------

  static void _saveToCppRegistry(ModelInfo model) {
    unawaited(
      DartBridgeModelRegistry.instance.savePublicModel(model).then((success) {
        final logger = SDKLogger('RunAnywhere.Models');
        if (!success) {
          logger.warning('Failed to save model to C++ registry: ${model.id}');
        }
      }).catchError((Object error) {
        SDKLogger('RunAnywhere.Models')
            .error('Error saving model to C++ registry: $error');
      }),
    );
  }

  static ModelFormat _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.gguf')) return ModelFormat.gguf;
    if (lower.endsWith('.onnx')) return ModelFormat.onnx;
    if (lower.endsWith('.bin')) return ModelFormat.bin;
    if (lower.endsWith('.ort')) return ModelFormat.ort;
    return ModelFormat.unknown;
  }
}
