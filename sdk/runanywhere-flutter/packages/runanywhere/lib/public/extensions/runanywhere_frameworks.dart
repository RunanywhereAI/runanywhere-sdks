/// RunAnywhere + Frameworks
///
/// Public API for framework discovery and querying.
/// Mirrors Swift's RunAnywhere+Frameworks.swift.
library runanywhere_frameworks;

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/public/runanywhere.dart';

// =============================================================================
// Framework Discovery Extensions
// =============================================================================

/// Extension methods for framework discovery
extension RunAnywhereFrameworks on RunAnywhere {
  /// Get all registered frameworks derived from available models
  /// - Returns: List of available inference frameworks that have models registered
  static Future<List<InferenceFramework>> getRegisteredFrameworks() async {
    // Derive frameworks from registered models - this is the source of truth
    final allModels = await RunAnywhere.availableModels();
    final frameworks = <InferenceFramework>{};

    for (final model in allModels) {
      // Add the model's framework (1:1 mapping)
      frameworks.add(model.framework);
    }

    final result = frameworks.toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  /// Get all registered frameworks for a specific capability
  /// - Parameter capability: The capability/component type to filter by
  /// - Returns: List of frameworks that provide the specified capability
  static Future<List<InferenceFramework>> getFrameworks(
      SDKComponent capability) async {
    final frameworks = <InferenceFramework>{};

    // Map capability to model categories
    final Set<ModelCategory> relevantCategories;
    switch (capability) {
      case SDKComponent.llm:
        relevantCategories = {ModelCategory.language, ModelCategory.multimodal};
      case SDKComponent.stt:
        relevantCategories = {ModelCategory.speechRecognition};
      case SDKComponent.tts:
        relevantCategories = {ModelCategory.speechSynthesis};
      case SDKComponent.vad:
        relevantCategories = {ModelCategory.audio};
      case SDKComponent.voice:
        relevantCategories = {
          ModelCategory.language,
          ModelCategory.speechRecognition,
          ModelCategory.speechSynthesis
        };
      case SDKComponent.embedding:
        // Embedding models could be language or multimodal
        relevantCategories = {ModelCategory.language, ModelCategory.multimodal};
    }

    final allModels = await RunAnywhere.availableModels();
    for (final model in allModels) {
      if (relevantCategories.contains(model.category)) {
        // Add the model's framework (1:1 mapping)
        frameworks.add(model.framework);
      }
    }

    final result = frameworks.toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  /// Check if a framework is available
  static Future<bool> isFrameworkAvailable(InferenceFramework framework) async {
    final frameworks = await getRegisteredFrameworks();
    return frameworks.contains(framework);
  }

  /// Get models for a specific framework
  static Future<List<ModelInfo>> modelsForFramework(
      InferenceFramework framework) async {
    final allModels = await RunAnywhere.availableModels();
    return allModels.where((model) => model.framework == framework).toList();
  }

  /// Get downloaded models for a specific framework
  static Future<List<ModelInfo>> downloadedModelsForFramework(
      InferenceFramework framework) async {
    final models = await modelsForFramework(framework);
    return models.where((model) => model.isDownloaded).toList();
  }
}
