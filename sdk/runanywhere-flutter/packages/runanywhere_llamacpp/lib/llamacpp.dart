/// LlamaCpp backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via llama.cpp
/// through the native runanywhere-core library using Dart FFI.
///
/// ## Quick Start (matches iOS LlamaCPP API exactly)
///
/// ```dart
/// import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
///
/// // Register the module (matches iOS LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Add models (matches iOS LlamaCPP.addModel())
/// LlamaCpp.addModel(
///   name: 'SmolLM2 360M Q8_0',
///   url: 'https://huggingface.co/.../model.gguf',
///   memoryRequirement: 500000000,
/// );
/// ```
///
/// ## What This Provides
///
/// - **LLM (Language Model)**: Text generation using GGUF/GGML models
/// - **Streaming**: Token-by-token streaming generation
/// - **Template Support**: Auto-detection of model templates (ChatML, Llama, etc.)
library runanywhere_llamacpp;

import 'package:runanywhere/core/models/framework/model_artifact_type.dart';
import 'package:runanywhere/core/models/model/model_category.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere_llamacpp/providers/llamacpp_llm_provider.dart';

export 'llamacpp_error.dart';
export 'llamacpp_template_resolver.dart';
export 'providers/llamacpp_llm_provider.dart';
export 'services/llamacpp_llm_service.dart';

// ============================================================================
// LlamaCpp Module Implementation
// Matches iOS LlamaCPP enum from LlamaCPPRuntime/LlamaCPPServiceProvider.swift
// ============================================================================

/// LlamaCpp module for LLM text generation.
///
/// Provides large language model capabilities using llama.cpp
/// with GGUF/GGML models and Metal/GPU acceleration.
///
/// Matches iOS `LlamaCPP` enum from LlamaCPPRuntime/LlamaCPPServiceProvider.swift.
///
/// ## Registration (matches iOS LlamaCPP pattern exactly)
///
/// ```dart
/// // Register module (matches iOS: LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Or with custom priority
/// await LlamaCpp.register(priority: 150);
///
/// // Add models (matches iOS: LlamaCPP.addModel())
/// LlamaCpp.addModel(
///   name: 'SmolLM2 360M Q8_0',
///   url: 'https://huggingface.co/.../model.gguf',
///   memoryRequirement: 500000000,
/// );
/// ```
class LlamaCpp extends RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches iOS enum pattern)
  // ============================================================================

  /// Singleton instance for module metadata
  static final LlamaCpp _instance = LlamaCpp._internal();

  /// Get the module instance (for use with ModuleRegistry.registerModule)
  static LlamaCpp get module => _instance;

  LlamaCpp._internal();

  // ============================================================================
  // Module State
  // ============================================================================

  static final SDKLogger _logger = SDKLogger(category: 'LlamaCpp');
  static bool _isRegistered = false;
  static NativeBackend? _backend;

  // ============================================================================
  // RunAnywhereModule Implementation (matches iOS LlamaCPP enum)
  // ============================================================================

  @override
  String get moduleId => 'llamacpp';

  @override
  String get moduleName => 'LlamaCpp';

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.llamaCpp;

  @override
  Set<CapabilityType> get capabilities => {CapabilityType.llm};

  @override
  int get defaultPriority => 100;

  @override
  ModelStorageStrategy? get storageStrategy => null;

  @override
  DownloadStrategy? get downloadStrategy => null;

  // ============================================================================
  // Static API (matches iOS LlamaCPP static methods exactly)
  // ============================================================================

  /// Whether the module is registered
  static bool get isRegistered => _isRegistered;

  /// Get native backend (for advanced usage)
  static NativeBackend? get backend => _backend;

  /// Check if the native backend is available on this platform.
  static bool get isAvailable {
    try {
      PlatformLoader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get the native library version.
  static String get version => _backend?.version ?? 'not initialized';

  /// Supported quantization levels for GGUF models.
  static const List<String> supportedQuantizations = [
    'Q2_K',
    'Q3_K_S',
    'Q3_K_M',
    'Q3_K_L',
    'Q4_0',
    'Q4_1',
    'Q4_K_S',
    'Q4_K_M',
    'Q5_0',
    'Q5_1',
    'Q5_K_S',
    'Q5_K_M',
    'Q6_K',
    'Q8_0',
    'IQ2_XXS',
    'IQ2_XS',
    'IQ3_S',
    'IQ3_XXS',
    'IQ4_NL',
    'IQ4_XS',
  ];

  /// Check if a quantization level is supported.
  static bool isQuantizationSupported(String quantization) {
    return supportedQuantizations.contains(quantization);
  }

  /// Get backend info as a map.
  static Map<String, dynamic> getBackendInfo() {
    if (_backend == null) return {};
    return _backend!.getBackendInfo();
  }

  /// List of available backend names from the native library.
  static List<String> get availableBackends {
    if (_backend != null) {
      try {
        return _backend!.getAvailableBackends();
      } catch (_) {
        return [];
      }
    }
    if (!isAvailable) return [];
    NativeBackend? tempBackend;
    try {
      tempBackend = NativeBackend();
      return tempBackend.getAvailableBackends();
    } catch (_) {
      return [];
    } finally {
      tempBackend?.dispose();
    }
  }

  // ============================================================================
  // Registration (matches iOS LlamaCPP.register() exactly)
  // ============================================================================

  /// Register LlamaCpp module with the SDK.
  ///
  /// Matches iOS `LlamaCPP.register(priority:)` pattern exactly.
  ///
  /// [priority] - Registration priority (higher = preferred). Default: 100.
  static Future<void> register({int priority = 100}) async {
    if (_isRegistered) {
      _logger.debug('LlamaCpp already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('LlamaCpp native library not available');
      return;
    }

    // Create native backend
    _backend = NativeBackend();
    _backend!.create('llamacpp');

    // Register as a module with ModuleRegistry (matches iOS pattern)
    ModuleRegistry.shared.registerModule(_instance, priority: priority);

    // Register LLM provider
    ModuleRegistry.shared.registerLLM(
      LlamaCppLLMServiceProvider(_backend!),
      priority: priority,
    );

    _isRegistered = true;
    _logger.info('LlamaCpp registered with capabilities: LLM');
  }

  // ============================================================================
  // Model Registration (matches iOS LlamaCPP.addModel() exactly)
  // ============================================================================

  /// Add a model to this module.
  ///
  /// Matches iOS `LlamaCPP.addModel()` pattern exactly.
  /// Uses the module's inferenceFramework automatically.
  ///
  /// [id] - Explicit model ID. If null, generated from URL filename.
  /// [name] - Display name for the model.
  /// [url] - Download URL string for the model.
  /// [modality] - Model category (defaults to language for LLM).
  /// [artifactType] - How the model is packaged.
  /// [memoryRequirement] - Estimated memory usage in bytes.
  /// [supportsThinking] - Whether the model supports reasoning/thinking.
  ///
  /// Returns the created ModelInfo, or null if URL is invalid.
  static ModelInfo? addModel({
    String? id,
    required String name,
    required String url,
    ModelCategory? modality,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    return _instance.addModelInternal(
      id: id,
      name: name,
      url: url,
      modality: modality,
      artifactType: artifactType,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources (for cleanup)
  static void dispose() {
    if (_backend != null) {
      _backend!.dispose();
      _backend = null;
    }
    _isRegistered = false;
    _logger.info('LlamaCpp disposed');
  }
}
