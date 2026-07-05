/// Experimental Qualcomm Genie NPU backend shell for RunAnywhere Flutter SDK.
///
/// Functional LLM routing is Android/Snapdragon-only and requires native
/// binaries built with the Qualcomm Genie SDK. Without those binaries, the
/// backend remains unavailable and is not selected by the native router.
/// It is a **thin wrapper** around the native plugin shell.
///
/// ## Architecture (matches Swift/Kotlin)
///
/// The C++ backend shell handles registration. Model loading, inference, and
/// streaming require a future SDK-backed implementation built with the
/// Qualcomm Genie SDK; the public shell returns backend-unavailable.
///
/// This Dart module just:
/// 1. Calls `rac_backend_genie_register()` to register the backend
/// 2. Lets the core SDK route LLM calls only if native registration succeeds
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere_genie/runanywhere_genie.dart';
///
/// // Register the module (matches Swift: Genie.register())
/// await Genie.register();
///
/// // Register models through RunAnywhere.models after register()
/// // succeeds. The commons registry/router owns framework selection and routing.
/// ```
library;

import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_genie/native/genie_bindings.dart';

/// Experimental Qualcomm Genie NPU module for LLM text generation.
///
/// Provides large language model capability only after SDK-backed native
/// registration succeeds on Android/Snapdragon hardware.
///
/// Matches the Swift/Kotlin Genie module pattern.
class Genie {
  Genie._();

  // Module Info (matches Swift exactly)

  /// Current version of the Genie Runtime Dart module.
  ///
  /// Matches the version convention used by `LlamaCpp.version` and
  /// `Onnx.version` ('2.0.0' per AGENTS.md Flutter SDK rules).
  static const String version = '2.0.0';

  /// Qualcomm Genie native backend version (single source of truth).
  ///
  /// Used by Android `binary_config.gradle` (`genieVersion = '0.3.0'`) for
  /// release URL resolution.
  static const String genieNativeVersion = '0.3.0';

  // Registration State

  static bool _isRegistered = false;
  static GenieBindings? _bindings;
  static final _logger = SDKLogger('Genie');

  // Registration (matches Swift Genie.register() exactly)

  /// Register Genie backend with the C++ service registry.
  ///
  /// This calls `rac_backend_genie_register()` to register the Genie plugin
  /// with the C++ commons layer. SDK-absent shells are rejected by the native
  /// capability check and remain unavailable to the router.
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  static Future<void> register({int priority = 200}) async {
    if (_isRegistered) {
      _logger.debug('Genie already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('Genie native library not available');
      return;
    }

    _logger.info('Registering Genie backend with C++ registry...');

    try {
      _bindings = GenieBindings();
      _logger.debug(
          'GenieBindings created, isAvailable: ${_bindings!.isAvailable}');

      final result = _bindings!.register();
      _logger.info(
          'rac_backend_genie_register() returned: $result (${RacResultCode.getMessage(result)})');

      if (result == RacResultCode.errorBackendUnavailable ||
          result == RacResultCode.errorCapabilityUnsupported) {
        _logger.error(
            'Genie backend unavailable; Qualcomm Genie SDK-backed native ops are required.');
        return;
      }

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.error('C++ backend registration FAILED with code: $result');
        return;
      }

      // No Dart-level provider needed - all LLM operations go through
      // DartBridgeLLM -> rac_llm_component_* (just like Swift CppBridge.LLM)

      _isRegistered = true;
      _logger.info('Genie LLM backend registered successfully');
    } catch (e) {
      _logger.error('GenieBindings not available: $e');
    }
  }

  /// Unregister the Genie backend from C++ registry.
  static void unregister() {
    if (_isRegistered) {
      _bindings?.unregister();
      _isRegistered = false;
      _logger.info('Genie LLM backend unregistered');
    }
  }

  /// Check if the native backend library can be loaded on this platform.
  ///
  /// Genie is experimental and Android/Snapdragon only:
  /// - On Android: Checks only whether the native registration symbol exists.
  ///   Successful [register] is still required before this module advertises LLM.
  /// - On iOS/other: Always returns false
  static bool get isAvailable => GenieBindings.checkAvailability();

  // Cleanup

  /// Dispose of resources
  static void dispose() {
    _bindings = null;
    _isRegistered = false;
    _logger.info('Genie disposed');
  }

  // Auto-Registration (matches Swift exactly)

  /// Enable auto-registration for this module.
  /// Call this method to trigger C++ backend registration.
  static void autoRegister() {
    unawaited(register());
  }
}
