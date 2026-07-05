/// LlamaCPP backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via llama.cpp.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend (RABackendLlamaCPP) handles all business logic:
/// - Service provider registration
/// - Model loading and inference
/// - Streaming generation
///
/// This Dart module just:
/// 1. Calls `rac_backend_llamacpp_register()` to register the backend
/// 2. The core SDK handles all LLM operations via `rac_llm_component_*`
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
///
/// // Register the module (matches Swift: LlamaCPP.register())
/// LlamaCpp.register();
///
/// // Register models through RunAnywhere.models.
/// // The commons registry/router owns framework selection and routing.
/// ```
library;

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_llamacpp/native/llamacpp_bindings.dart';

/// LlamaCPP module for LLM text generation.
///
/// Provides large language model capabilities using llama.cpp
/// with GGUF models and Metal/GPU acceleration.
///
/// Matches Swift `LlamaCPP` enum from LlamaCPPRuntime/LlamaCPP.swift.
class LlamaCpp {
  LlamaCpp._();

  // ============================================================================
  // Module Info (matches Swift exactly)
  // ============================================================================

  /// Current version of the LlamaCPP Runtime module
  static const String version = '2.0.0';

  /// LlamaCPP library version (underlying C++ library)
  static const String llamaCppVersion = 'b7199';

  // ============================================================================
  // Registration State
  // ============================================================================

  static bool _isRegistered = false;
  static LlamaCppBindings? _bindings;
  static final _logger = SDKLogger('LlamaCpp');

  // ============================================================================
  // Registration (matches Swift LlamaCPP.register() exactly)
  // ============================================================================

  /// Register LlamaCPP backend with the C++ service registry.
  ///
  /// This calls `rac_backend_llamacpp_register()` to register the
  /// LlamaCPP service provider with the C++ commons layer.
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  static void register({int priority = 100}) {
    if (_isRegistered) {
      _logger.debug('LlamaCpp already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('LlamaCpp native library not available');
      return;
    }

    _logger.info('Registering LlamaCpp backend with C++ registry...');

    try {
      _bindings = LlamaCppBindings();
      _logger.debug(
          'LlamaCppBindings created, isAvailable: ${_bindings!.isAvailable}');

      final result = _bindings!.register();
      _logger.info(
          'rac_backend_llamacpp_register() returned: $result (${RacResultCode.getMessage(result)})');

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.error('C++ backend registration FAILED with code: $result');
        return;
      }

      // No Dart-level provider needed - all LLM operations go through
      // DartBridgeLLM -> rac_llm_component_* (just like Swift CppBridge.LLM)

      _isRegistered = true;
      _logger.info('LlamaCpp LLM backend registered successfully');
    } catch (e) {
      _logger.error('LlamaCppBindings not available: $e');
    }
  }

  /// Unregister the LlamaCPP backend from C++ registry.
  static void unregister() {
    if (_isRegistered) {
      _bindings?.unregister();
      _isRegistered = false;
      _logger.info('LlamaCpp LLM backend unregistered');
    }
  }

  /// Check if the native backend is available on this platform.
  ///
  /// On iOS: Checks DynamicLibrary.process() for statically linked symbols
  /// On Android: Checks if librac_backend_llamacpp_jni.so can be loaded
  static bool get isAvailable => LlamaCppBindings.checkAvailability();

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources
  static void dispose() {
    _bindings = null;
    _isRegistered = false;
    _logger.info('LlamaCpp disposed');
  }

  // ============================================================================
  // Auto-Registration (matches Swift exactly)
  // ============================================================================

  /// Enable auto-registration for this module.
  /// Call this method to trigger C++ backend registration.
  static void autoRegister() {
    register();
  }
}
