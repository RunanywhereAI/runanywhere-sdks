import 'dart:async';

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/providers/native_llm_provider.dart';
import 'package:runanywhere/native/providers/native_stt_provider.dart';
import 'package:runanywhere/native/providers/native_tts_provider.dart';
import 'package:runanywhere/native/providers/native_vad_provider.dart';

/// Helper class to register native providers with the SDK.
///
/// This is the Flutter equivalent of iOS's ONNXAdapter.onRegistration().
///
/// ## Usage
///
/// ```dart
/// // Register all native providers with the SDK
/// await NativeProviderRegistration.registerAll();
///
/// // Or register with a specific backend
/// final backend = NativeBackend();
/// backend.create('onnx');
/// await NativeProviderRegistration.registerWithBackend(backend);
/// ```
class NativeProviderRegistration {
  static NativeBackend? _sharedBackend;
  static bool _isRegistered = false;

  /// Get the shared native backend instance.
  ///
  /// Creates and initializes the backend on first access.
  static NativeBackend get sharedBackend {
    if (_sharedBackend == null) {
      _sharedBackend = NativeBackend();
      _sharedBackend!.create('onnx');
    }
    return _sharedBackend!;
  }

  /// Check if native providers are registered.
  static bool get isRegistered => _isRegistered;

  /// Check if native library is available on this platform.
  static bool get isAvailable {
    try {
      PlatformLoader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Register all native providers with the SDK's ModuleRegistry.
  ///
  /// This should be called during app initialization before using
  /// native AI capabilities.
  ///
  /// [priority] - Provider priority (higher = preferred). Default: 100.
  ///
  /// Returns true if registration succeeded, false otherwise.
  static Future<bool> registerAll({int priority = 100}) async {
    if (_isRegistered) {
      return true;
    }

    if (!isAvailable) {
      // Using logger would be better, but keeping it simple
      return false;
    }

    try {
      final backend = sharedBackend;
      await registerWithBackend(backend, priority: priority);
      _isRegistered = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Register native providers using a specific backend instance.
  ///
  /// Use this if you need to manage the backend lifecycle yourself.
  static Future<void> registerWithBackend(
    NativeBackend backend, {
    int priority = 100,
  }) async {
    final registry = ModuleRegistry.shared;

    // Register STT provider
    registry.registerSTT(
      NativeSTTServiceProvider(backend),
      priority: priority,
    );

    // Register TTS provider
    registry.registerTTS(
      NativeTTSServiceProvider(backend),
      priority: priority,
    );

    // Register VAD provider
    registry.registerVAD(
      NativeVADServiceProvider(backend),
      priority: priority,
    );

    // Register LLM provider
    registry.registerLLM(
      NativeLLMServiceProvider(backend),
      priority: priority,
    );
  }

  /// Unregister and cleanup native providers.
  ///
  /// Call this when the app is shutting down or no longer needs
  /// native AI capabilities.
  static void dispose() {
    if (_sharedBackend != null) {
      _sharedBackend!.dispose();
      _sharedBackend = null;
    }
    _isRegistered = false;
  }

  /// Get backend info as a map.
  static Map<String, dynamic> getBackendInfo() {
    if (_sharedBackend == null) {
      return {};
    }
    return _sharedBackend!.getBackendInfo();
  }

  /// Get available backend names.
  static List<String> getAvailableBackends() {
    try {
      final backend = NativeBackend();
      return backend.getAvailableBackends();
    } catch (_) {
      return [];
    }
  }

  /// Get the native library version.
  static String get version {
    try {
      final backend = NativeBackend();
      return backend.version;
    } catch (_) {
      return 'unknown';
    }
  }
}
