// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_frameworks.dart — framework discovery / querying.
// Mirrors Swift `RunAnywhere+Frameworks.swift`.

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

/// Framework discovery helpers.
///
/// Frameworks are derived from the set of currently-available
/// models; adding/removing models implicitly adds/removes their
/// framework.
class RunAnywhereFrameworks {
  RunAnywhereFrameworks._();

  /// Every inference framework with at least one registered model,
  /// sorted by display name.
  static Future<List<InferenceFramework>> getRegisteredFrameworks() async {
    final allModels = await RunAnywhereModels.shared.available();
    final frameworks = <InferenceFramework>{};
    for (final model in allModels) {
      frameworks.add(model.framework);
    }
    final result = frameworks.toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  /// Frameworks that provide the given capability (LLM / STT / TTS /
  /// VAD / voice / embedding / VLM), derived from the set of
  /// available models that match the capability's model categories.
  static Future<List<InferenceFramework>> getFrameworks(
    SDKComponent capability,
  ) async {
    final frameworks = <InferenceFramework>{};

    final Set<ModelCategory> relevantCategories;
    switch (capability) {
      case SDKComponent.llm:
        relevantCategories = {
          ModelCategory.language,
          ModelCategory.multimodal,
        };
        break;
      case SDKComponent.stt:
        relevantCategories = {ModelCategory.speechRecognition};
        break;
      case SDKComponent.tts:
        relevantCategories = {ModelCategory.speechSynthesis};
        break;
      case SDKComponent.vad:
        relevantCategories = {ModelCategory.audio};
        break;
      case SDKComponent.voice:
        relevantCategories = {
          ModelCategory.language,
          ModelCategory.speechRecognition,
          ModelCategory.speechSynthesis,
        };
        break;
      case SDKComponent.embedding:
        relevantCategories = {ModelCategory.embedding};
        break;
      case SDKComponent.vlm:
        relevantCategories = {ModelCategory.multimodal};
        break;
    }

    final allModels = await RunAnywhereModels.shared.available();
    for (final model in allModels) {
      if (relevantCategories.contains(model.category)) {
        frameworks.add(model.framework);
      }
    }

    final result = frameworks.toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  /// True if the given framework has at least one registered model.
  static Future<bool> isFrameworkAvailable(
    InferenceFramework framework,
  ) async {
    final frameworks = await getRegisteredFrameworks();
    return frameworks.contains(framework);
  }

  /// All models for a specific framework.
  static Future<List<ModelInfo>> modelsForFramework(
    InferenceFramework framework,
  ) async {
    final allModels = await RunAnywhereModels.shared.available();
    return allModels.where((model) => model.framework == framework).toList();
  }

  /// Downloaded models for a specific framework.
  static Future<List<ModelInfo>> downloadedModelsForFramework(
    InferenceFramework framework,
  ) async {
    final models = await modelsForFramework(framework);
    return models.where((model) => model.isDownloaded).toList();
  }
}
