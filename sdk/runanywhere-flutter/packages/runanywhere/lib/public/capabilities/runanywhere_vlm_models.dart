// Wave 3: VLMModels namespace extension.
// Mirrors Swift RunAnywhere+VLMModels.swift.
// Provides filtered model catalog for vision-language models.

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/generated/vlm_options.pb.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

class RunAnywhereVLMModels {
  RunAnywhereVLMModels._();
  static final RunAnywhereVLMModels _instance = RunAnywhereVLMModels._();
  static RunAnywhereVLMModels get shared => _instance;

  /// Returns all available VLM models (vision and multimodal categories).
  Future<List<ModelInfo>> available() async {
    final all = await RunAnywhereModels.shared.available();
    return all
        .where((m) =>
            m.category == ModelCategory.vision ||
            m.category == ModelCategory.multimodal)
        .toList();
  }

  /// Returns a [VLMConfiguration] pre-filled with [modelId].
  VLMConfiguration configurationForModel(String modelId) =>
      VLMConfiguration(modelId: modelId);
}
