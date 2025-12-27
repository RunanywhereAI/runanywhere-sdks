//
// runanywhere_module.dart
// RunAnywhere Flutter SDK
//
// Protocol for external modules that extend SDK capabilities.
// Matches iOS RunAnywhereModule from Core/Module/RunAnywhereModule.swift
//

import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/models/framework/model_artifact_type.dart';
import 'package:runanywhere/core/models/model/model_category.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/module/capability_type.dart';
import 'package:runanywhere/core/module/inference_framework.dart';
import 'package:runanywhere/core/module/model_storage_strategy.dart';
import 'package:runanywhere/core/protocols/downloading/download_strategy.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Protocol for RunAnywhere modules that provide AI services.
///
/// External modules (ONNX, LlamaCPP, WhisperKit, etc.) implement this abstract class
/// to provide metadata about their services. The actual service registration is
/// handled by the module's static `register()` method.
///
/// Matches iOS `RunAnywhereModule` from Core/Module/RunAnywhereModule.swift
///
/// ## Implementing a Module (matches iOS pattern)
///
/// ```dart
/// class LlamaCpp implements RunAnywhereModule {
///   static final LlamaCpp module = LlamaCpp._();
///   LlamaCpp._();
///
///   @override
///   String get moduleId => 'llamacpp';
///
///   @override
///   String get moduleName => 'LlamaCpp';
///
///   @override
///   InferenceFramework get inferenceFramework => InferenceFramework.llamaCpp;
///
///   @override
///   Set<CapabilityType> get capabilities => {CapabilityType.llm};
///
///   // Static registration method (matches iOS static register)
///   static Future<void> register({int priority = 100}) async {
///     ModuleRegistry.shared.registerModule(module, priority: priority);
///     // Register service providers...
///   }
///
///   // Static addModel method (matches iOS static addModel)
///   static ModelInfo? addModel({...}) => module.addModelInternal(...);
/// }
/// ```
abstract class RunAnywhereModule {
  /// Unique identifier for this module (e.g., "onnx", "llamacpp", "whisperkit")
  String get moduleId;

  /// Human-readable display name (e.g., "ONNX Runtime", "LlamaCPP")
  String get moduleName;

  /// The inference framework this module provides (required)
  InferenceFramework get inferenceFramework;

  /// Get the LLMFramework equivalent for this module's inference framework.
  /// Used for model registration with the registry service.
  LLMFramework get llmFramework => _inferenceToLLMFramework(inferenceFramework);

  /// Set of capabilities this module provides
  Set<CapabilityType> get capabilities;

  /// Default priority for service registration (higher = preferred).
  /// Override to customize priority. Default is 100.
  int get defaultPriority => 100;

  /// Optional storage strategy for detecting downloaded models.
  /// Modules with directory-based models (like ONNX) should provide this.
  ModelStorageStrategy? get storageStrategy => null;

  /// Optional download strategy for custom download handling.
  /// Modules with special download requirements (like WhisperKit) should provide this.
  DownloadStrategy? get downloadStrategy => null;

  // ============================================================================
  // Model Registration (matches iOS RunAnywhereModule.addModel() exactly)
  // ============================================================================

  /// Add a model to this module.
  ///
  /// Matches iOS `RunAnywhereModule.addModel()` pattern exactly.
  /// Uses the module's inferenceFramework automatically.
  ///
  /// [id] - Explicit model ID. If null, a stable ID is generated from the URL filename.
  /// [name] - Display name for the model.
  /// [url] - Download URL string for the model.
  /// [modality] - Model category (inferred from module capabilities if not specified).
  /// [artifactType] - How the model is packaged (inferred from URL if not specified).
  /// [memoryRequirement] - Estimated memory usage in bytes.
  /// [supportsThinking] - Whether the model supports reasoning/thinking.
  ///
  /// Returns the created ModelInfo, or null if URL is invalid.
  ModelInfo? addModelInternal({
    String? id,
    required String name,
    required String url,
    ModelCategory? modality,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final downloadURL = Uri.tryParse(url);
    if (downloadURL == null) {
      SDKLogger(category: 'Module.$moduleId')
          .error("Invalid URL for model '$name': $url");
      return null;
    }

    // Determine modality from parameter or infer from module capabilities
    final category = modality ?? _inferModalityFromCapabilities();

    // Register the model with this module's framework
    final modelInfo = ServiceContainer.shared.modelRegistry.addModelFromURL(
      id: id,
      name: name,
      url: downloadURL,
      framework: llmFramework,
      category: category,
      artifactType: artifactType,
      estimatedSize: memoryRequirement,
      supportsThinking: supportsThinking,
    );

    SDKLogger(category: 'Module.$moduleId')
        .info("Added model '$name' (id: ${modelInfo.id})");
    return modelInfo;
  }

  /// Infer the primary modality from module capabilities.
  /// Matches iOS RunAnywhereModule.inferModalityFromCapabilities()
  ModelCategory _inferModalityFromCapabilities() {
    if (capabilities.contains(CapabilityType.llm)) {
      return ModelCategory.language;
    } else if (capabilities.contains(CapabilityType.stt)) {
      return ModelCategory.speechRecognition;
    } else if (capabilities.contains(CapabilityType.tts)) {
      return ModelCategory.speechSynthesis;
    } else if (capabilities.contains(CapabilityType.vad) ||
        capabilities.contains(CapabilityType.speakerDiarization)) {
      return ModelCategory.audio;
    }
    return ModelCategory.language; // Default
  }

  /// Convert InferenceFramework to LLMFramework
  static LLMFramework _inferenceToLLMFramework(InferenceFramework framework) {
    switch (framework) {
      case InferenceFramework.coreML:
        return LLMFramework.coreML;
      case InferenceFramework.tensorFlowLite:
        return LLMFramework.tensorFlowLite;
      case InferenceFramework.mlx:
        return LLMFramework.mlx;
      case InferenceFramework.swiftTransformers:
        return LLMFramework.swiftTransformers;
      case InferenceFramework.onnx:
        return LLMFramework.onnx;
      case InferenceFramework.execuTorch:
        return LLMFramework.execuTorch;
      case InferenceFramework.llamaCpp:
        return LLMFramework.llamaCpp;
      case InferenceFramework.foundationModels:
        return LLMFramework.foundationModels;
      case InferenceFramework.picoLLM:
        return LLMFramework.picoLLM;
      case InferenceFramework.mlc:
        return LLMFramework.mlc;
      case InferenceFramework.mediaPipe:
        return LLMFramework.mediaPipe;
      case InferenceFramework.whisperKit:
        return LLMFramework.whisperKit;
      case InferenceFramework.openAIWhisper:
        return LLMFramework.openAIWhisper;
      case InferenceFramework.systemTTS:
        return LLMFramework.systemTTS;
      case InferenceFramework.fluidAudio:
        // FluidAudio doesn't have a direct mapping, use ONNX as default
        return LLMFramework.onnx;
    }
  }
}

// ============================================================================
// Module Metadata
// ============================================================================

/// Metadata about a registered module.
///
/// This is a read-only snapshot of module information stored in the registry.
/// Matches iOS ModuleMetadata from Core/Module/RunAnywhereModule.swift
class ModuleMetadata {
  /// Module identifier
  final String moduleId;

  /// Display name
  final String moduleName;

  /// The inference framework
  final InferenceFramework inferenceFramework;

  /// Capabilities provided
  final Set<CapabilityType> capabilities;

  /// Registration priority used
  final int priority;

  /// When the module was registered
  final DateTime registeredAt;

  const ModuleMetadata({
    required this.moduleId,
    required this.moduleName,
    required this.inferenceFramework,
    required this.capabilities,
    required this.priority,
    required this.registeredAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleMetadata &&
          runtimeType == other.runtimeType &&
          moduleId == other.moduleId;

  @override
  int get hashCode => moduleId.hashCode;

  @override
  String toString() =>
      'ModuleMetadata(moduleId: $moduleId, moduleName: $moduleName, '
      'capabilities: ${capabilities.map((c) => c.rawValue).join(", ")})';
}
