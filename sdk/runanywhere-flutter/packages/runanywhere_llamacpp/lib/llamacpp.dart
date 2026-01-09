/// LlamaCpp backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via llama.cpp
/// through the native runanywhere-core library using Dart FFI.
///
/// ## Quick Start (matches Swift LlamaCPP API exactly)
///
/// ```dart
/// import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
///
/// // Register the module (matches Swift: LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Add models (matches Swift: LlamaCPP.addModel())
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

import 'dart:async';

import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/runanywhere.dart' show RunAnywhere;
import 'package:runanywhere_llamacpp/native/llamacpp_bindings.dart';
import 'package:runanywhere_llamacpp/providers/llamacpp_llm_provider.dart';

export 'llamacpp_error.dart';
export 'llamacpp_template_resolver.dart';
export 'providers/llamacpp_llm_provider.dart';
export 'services/llamacpp_llm_service.dart';

// ============================================================================
// LlamaCpp Module Implementation
// Matches Swift LlamaCPP enum from LlamaCPPRuntime/LlamaCPP.swift
// ============================================================================

/// LlamaCpp module for LLM text generation.
///
/// Provides large language model capabilities using llama.cpp
/// with GGUF/GGML models and Metal/GPU acceleration.
///
/// Matches Swift `LlamaCPP` enum from LlamaCPPRuntime/LlamaCPP.swift.
///
/// ## Registration (matches Swift LlamaCPP pattern exactly)
///
/// ```dart
/// // Register module (matches Swift: LlamaCPP.register())
/// await LlamaCpp.register();
///
/// // Or with custom priority
/// await LlamaCpp.register(priority: 150);
/// ```
class LlamaCpp implements RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches Swift enum pattern)
  // ============================================================================

  /// Singleton instance for module metadata
  static final LlamaCpp _instance = LlamaCpp._internal();

  /// Get the module instance (for use with ModuleRegistry.registerModule)
  static LlamaCpp get module => _instance;

  LlamaCpp._internal();

  // ============================================================================
  // Module State
  // ============================================================================

  static final SDKLogger _logger = SDKLogger('LlamaCpp');
  static bool _isRegistered = false;
  static NativeBackend? _backend;
  static LlamaCppBindings? _bindings;

  // ============================================================================
  // RunAnywhereModule Implementation (matches Swift LlamaCPP enum)
  // ============================================================================

  @override
  String get moduleId => 'llamacpp';

  @override
  String get moduleName => 'LlamaCpp';

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.llamaCpp;

  @override
  Set<SDKComponent> get capabilities => {SDKComponent.llm};

  @override
  int get defaultPriority => 100;

  // ============================================================================
  // Static API (matches Swift LlamaCPP static methods exactly)
  // ============================================================================

  /// Whether the module is registered
  static bool get isRegistered => _isRegistered;

  /// Get native backend (for advanced usage)
  static NativeBackend? get backend => _backend;

  /// Get native bindings (for advanced usage)
  static LlamaCppBindings? get bindings => _bindings;

  /// Check if the native backend is available on this platform.
  static bool get isAvailable {
    try {
      PlatformLoader.loadLlamaCpp();
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
  // Registration (matches Swift LlamaCPP.register() exactly)
  // ============================================================================

  /// Register LlamaCpp module with the SDK.
  ///
  /// Matches Swift `LlamaCPP.register(priority:)` pattern exactly.
  /// Calls the C++ `rac_backend_llamacpp_register()` function via FFI.
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

    // Step 1: Create bindings and register with C++
    try {
      _bindings = LlamaCppBindings();

      // Call C++ registration function via FFI (matches Swift exactly)
      final result = _bindings!.register();

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.warning('C++ backend registration returned: $result');
      } else {
        _logger.debug('C++ backend registered successfully');
      }
    } catch (e) {
      _logger.debug('LlamaCppBindings not available: $e');
      // Continue with Dart-side registration as fallback
    }

    // Step 2: Create native backend for operations (backward compatibility)
    _backend = NativeBackend.llamacpp();
    _backend!.initialize();

    // Step 3: Register module metadata with Dart ModuleRegistry
    ModuleRegistry.shared.registerModuleMetadata(ModuleMetadata(
      moduleId: _instance.moduleId,
      moduleName: _instance.moduleName,
      inferenceFramework: _instance.inferenceFramework,
      capabilities: _instance.capabilities,
      priority: priority,
      registeredAt: DateTime.now(),
    ));

    // Step 4: Register LLM provider
    ModuleRegistry.shared.registerLLM(
      LlamaCppLLMServiceProvider(_backend!),
      priority: priority,
    );

    // Step 5: Register model collector with RunAnywhere
    RunAnywhere.registerModelCollector(() => _registeredModels);

    _isRegistered = true;
    _logger.info('LlamaCpp registered with capabilities: LLM');
  }

  // ============================================================================
  // Model Registration (matches Swift RunAnywhere.registerModel pattern)
  // ============================================================================

  /// Add a model to be used with LlamaCpp.
  ///
  /// This is a convenience method that matches the Swift pattern where modules
  /// own their models. Internally calls [RunAnywhere.registerModel].
  ///
  /// ```dart
  /// LlamaCpp.addModel(
  ///   id: 'smollm2-360m-q8_0',
  ///   name: 'SmolLM2 360M Q8_0',
  ///   url: 'https://huggingface.co/.../model.gguf',
  ///   memoryRequirement: 500000000,
  /// );
  /// ```
  static void addModel({
    String? id,
    required String name,
    required String url,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    // Import and use RunAnywhere to register the model
    _addModelInternal(
      id: id,
      name: name,
      url: url,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  static void _addModelInternal({
    String? id,
    required String name,
    required String url,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _logger.error('Invalid URL for model: $name');
      return;
    }

    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

    // Determine format from URL
    final format = _inferFormat(uri.path);

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: ModelCategory.language,
      format: format,
      framework: InferenceFramework.llamaCpp,
      downloadURL: uri,
      downloadSize: memoryRequirement,
      supportsThinking: supportsThinking,
      source: ModelSource.local,
    );

    // Register with the global model registry
    _registeredModels.add(model);
    _logger.info('Added LlamaCpp model: $name ($modelId)');
  }

  /// Infer model format from URL path
  static ModelFormat _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.gguf')) return ModelFormat.gguf;
    if (lower.endsWith('.bin')) return ModelFormat.bin;
    return ModelFormat.gguf; // Default for LlamaCpp
  }

  /// Internal model registry for models added via addModel
  static final List<ModelInfo> _registeredModels = [];

  /// Get all models registered with this module
  static List<ModelInfo> get registeredModels =>
      List.unmodifiable(_registeredModels);

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources (for cleanup)
  static void dispose() {
    if (_backend != null) {
      _backend!.dispose();
      _backend = null;
    }
    _bindings = null;
    _registeredModels.clear();
    _isRegistered = false;
    _logger.info('LlamaCpp disposed');
  }
}
