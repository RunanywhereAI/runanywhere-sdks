// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_frameworks.dart — framework discovery / querying.
// Mirrors Swift `RunAnywhere+Frameworks.swift`.

import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show InferenceFramework, ModelCategory;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart';
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
      case SDKComponent.SDK_COMPONENT_LLM:
        relevantCategories = {
          ModelCategory.MODEL_CATEGORY_LANGUAGE,
          ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        };
        break;
      case SDKComponent.SDK_COMPONENT_STT:
        relevantCategories = {ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION};
        break;
      case SDKComponent.SDK_COMPONENT_TTS:
        relevantCategories = {ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS};
        break;
      case SDKComponent.SDK_COMPONENT_VAD:
        relevantCategories = {
          ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        };
        break;
      case SDKComponent.SDK_COMPONENT_VOICE_AGENT:
        relevantCategories = {
          ModelCategory.MODEL_CATEGORY_LANGUAGE,
          ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
          ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
          ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
        };
        break;
      case SDKComponent.SDK_COMPONENT_EMBEDDINGS:
        relevantCategories = {ModelCategory.MODEL_CATEGORY_EMBEDDING};
        break;
      case SDKComponent.SDK_COMPONENT_VLM:
        relevantCategories = {ModelCategory.MODEL_CATEGORY_MULTIMODAL};
        break;
      case SDKComponent.SDK_COMPONENT_DIFFUSION:
      case SDKComponent.SDK_COMPONENT_RAG:
      case SDKComponent.SDK_COMPONENT_WAKEWORD:
      case SDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION:
      case SDKComponent.SDK_COMPONENT_UNSPECIFIED:
      default:
        relevantCategories = {};
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
