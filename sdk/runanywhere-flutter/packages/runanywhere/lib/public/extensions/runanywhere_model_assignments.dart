// Wave 3: ModelAssignments namespace extension.
// Mirrors Swift RunAnywhere+ModelAssignments.swift.
// Provides model registration helpers (assign custom local models to registry).

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

class RunAnywhereModelAssignments {
  RunAnywhereModelAssignments._();
  static final RunAnywhereModelAssignments _instance =
      RunAnywhereModelAssignments._();
  static RunAnywhereModelAssignments get shared => _instance;

  /// Register a custom on-device model from a local file [localPath].
  /// Mirrors Swift `RunAnywhere.registerModel(at:)`.
  ModelInfo registerLocalModel({
    required String modelId,
    required String name,
    required Uri localPath,
    required InferenceFramework framework,
    ModelCategory category = ModelCategory.language,
    ModelFormat format = ModelFormat.gguf,
    String? description,
    int contextLength = 4096,
  }) {
    return RunAnywhereModels.shared.register(
      id: modelId,
      name: name,
      url: localPath,
      framework: framework,
      modality: category,
    );
  }

  /// Update the local path of an already-registered model after download.
  Future<void> updateLocalPath(String modelId, String localPath) =>
      RunAnywhereModels.shared.updateDownloadStatus(modelId, localPath);
}
