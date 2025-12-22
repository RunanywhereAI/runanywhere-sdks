/// LlamaCpp backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via llama.cpp
/// through the native runanywhere-core library using Dart FFI.
///
/// ## Quick Start (iOS-style API)
///
/// ```dart
/// import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
///
/// // Register the module (matches iOS LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Add models (matches iOS LlamaCPP.addModel())
/// LlamaCpp.addModel(
///   id: 'smollm2-360m-q8_0',
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
///
/// ## Supported Model Formats
///
/// - `.gguf` - GGUF format (recommended)
/// - `.ggml` - GGML format (legacy)
/// - `.bin` - Binary format
///
/// ## Quantization Support
///
/// Supports all common quantization levels:
/// - Q2_K, Q3_K_S/M/L, Q4_0/1, Q4_K_S/M
/// - Q5_0/1, Q5_K_S/M, Q6_K, Q8_0
/// - IQ2_XXS/XS, IQ3_S/XXS, IQ4_NL/XS
library runanywhere_llamacpp;

import 'package:runanywhere/backends/llamacpp/providers/llamacpp_llm_provider.dart';
import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/models/model/model_category.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';

export 'llamacpp_error.dart';
// Utilities
export 'llamacpp_template_resolver.dart';
// Providers
export 'providers/llamacpp_llm_provider.dart';
// Services
export 'services/llamacpp_llm_service.dart';

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
/// import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
///
/// // Register module (matches iOS: LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Add models (matches iOS: LlamaCPP.addModel())
/// LlamaCpp.addModel(
///   id: 'smollm2-360m-q8_0',
///   name: 'SmolLM2 360M Q8_0',
///   url: 'https://huggingface.co/.../model.gguf',
///   memoryRequirement: 500000000,
/// );
/// ```
class LlamaCpp {
  static final _logger = SDKLogger(category: 'LlamaCpp');

  // Module state
  static bool _isRegistered = false;
  static NativeBackend? _backend;

  // Private constructor - use static methods only
  LlamaCpp._();

  // ============================================================================
  // RunAnywhereModule Properties (matches iOS LlamaCPP enum)
  // ============================================================================

  /// Module identifier (matches iOS LlamaCPP.moduleId)
  static const String moduleId = 'llamacpp';

  /// Human-readable module name (matches iOS LlamaCPP.moduleName)
  static const String moduleName = 'LlamaCpp';

  /// Inference framework for this module (matches iOS LlamaCPP.inferenceFramework)
  static LLMFramework get inferenceFramework => LLMFramework.llamaCpp;

  /// Default registration priority (matches iOS LlamaCPP.defaultPriority)
  static const int defaultPriority = 100;

  /// Whether the module is registered
  static bool get isRegistered => _isRegistered;

  /// Get native backend (for advanced usage)
  static NativeBackend? get backend => _backend;

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

  // ============================================================================
  // Backend Info (for compatibility with legacy code)
  // ============================================================================

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
    // Create temporary backend to check
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

  /// Check if a quantization level is supported.
  static bool isQuantizationSupported(String quantization) {
    return supportedQuantizations.contains(quantization);
  }

  // ============================================================================
  // Registration (matches iOS LlamaCPP.register() exactly)
  // ============================================================================

  /// Register LlamaCpp LLM service with the SDK.
  ///
  /// Matches iOS `LlamaCPP.register(priority:)` pattern exactly.
  /// Registers LLM provider with ModuleRegistry directly.
  ///
  /// [priority] - Registration priority (higher = preferred). Default: 100.
  static Future<void> register({int priority = defaultPriority}) async {
    if (_isRegistered) {
      _logger.debug('LlamaCpp already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('LlamaCpp native library not available');
      return;
    }

    // Create native backend (matches iOS: backend is created in service)
    _backend = NativeBackend();
    _backend!.create('llamacpp');

    // Register LLM provider with ModuleRegistry
    // Matches iOS: ServiceRegistry.shared.registerLLM(name:priority:canHandle:factory:)
    ModuleRegistry.shared.registerLLM(
      LlamaCppLLMServiceProvider(_backend!),
      priority: priority,
    );

    _isRegistered = true;
    _logger.info('LlamaCpp LLM registered');
  }

  // ============================================================================
  // Model Registration (matches iOS LlamaCPP.addModel() exactly)
  // ============================================================================

  /// Add a model to this module.
  ///
  /// Matches iOS `LlamaCPP.addModel()` pattern exactly.
  /// Uses the module's inferenceFramework automatically.
  ///
  /// [id] - Explicit model ID. If null, a stable ID is generated from the URL filename.
  /// [name] - Display name for the model.
  /// [url] - Download URL string for the model.
  /// [modality] - Model category (defaults to .language for LLM).
  /// [memoryRequirement] - Estimated memory usage in bytes.
  /// [supportsThinking] - Whether the model supports reasoning/thinking.
  ///
  /// Returns the created ModelInfo, or null if URL is invalid.
  static ModelInfo? addModel({
    String? id,
    required String name,
    required String url,
    ModelCategory modality = ModelCategory.language,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final downloadURL = Uri.tryParse(url);
    if (downloadURL == null) {
      _logger.error("Invalid URL for model '$name': $url");
      return null;
    }

    // Register the model with this module's framework
    final modelInfo = ServiceContainer.shared.modelRegistry.addModelFromURL(
      id: id,
      name: name,
      url: downloadURL,
      framework: inferenceFramework,
      category: modality,
      estimatedSize: memoryRequirement,
      supportsThinking: supportsThinking,
    );

    _logger.info("Added model '$name' (id: ${modelInfo.id})");
    return modelInfo;
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
