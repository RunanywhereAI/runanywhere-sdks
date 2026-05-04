// Wave 3: ModelManagement namespace extension.
// Mirrors Swift RunAnywhere+ModelManagement.swift.
// Provides model lifecycle helpers beyond RunAnywhereModels (listing/download).

import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

class RunAnywhereModelManagement {
  RunAnywhereModelManagement._();
  static final RunAnywhereModelManagement _instance =
      RunAnywhereModelManagement._();
  static RunAnywhereModelManagement get shared => _instance;

  /// Returns all locally-downloaded models (localPath is non-null).
  Future<List<ModelInfo>> downloaded() async {
    final all = await RunAnywhereModels.shared.available();
    return all.where((m) => m.isDownloaded).toList();
  }

  /// Returns all models filtered by [category].
  Future<List<ModelInfo>> modelsForCategory(ModelCategory category) async {
    final all = await RunAnywhereModels.shared.available();
    return all.where((m) => m.category == category).toList();
  }

  /// Removes a downloaded model's local files and updates the registry.
  Future<void> remove(String modelId) =>
      RunAnywhereModels.shared.remove(modelId);
}
