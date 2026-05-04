// Wave 3: VLMModels namespace extension.
// Mirrors Swift RunAnywhere+VLMModels.swift.
// Provides filtered model catalog for vision-language models.

import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
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
            m.category == ModelCategory.MODEL_CATEGORY_VISION ||
            m.category == ModelCategory.MODEL_CATEGORY_MULTIMODAL)
        .toList();
  }

  /// Returns a [VLMConfiguration] pre-filled with [modelId].
  VLMConfiguration configurationForModel(String modelId) =>
      VLMConfiguration(modelId: modelId);
}
