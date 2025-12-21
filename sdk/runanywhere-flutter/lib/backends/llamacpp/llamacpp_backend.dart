import 'dart:async';

import '../../native/native_backend.dart';
import '../../native/platform_loader.dart';
import 'llamacpp_adapter.dart';

/// Main entry point for the LlamaCpp (llama.cpp) backend.
///
/// This class manages the lifecycle of the LlamaCpp backend and provides
/// methods to initialize and access LLM services.
///
/// ## Usage
///
/// ```dart
/// import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
///
/// void main() async {
///   // Initialize with default priority
///   final success = await LlamaCppBackend.initialize();
///
///   if (success) {
///     // LlamaCpp providers are now registered with ModuleRegistry
///     // Use standard RunAnywhere API to access services
///     final llm = ModuleRegistry.shared.llmProvider();
///   }
/// }
/// ```
///
/// ## Priority System
///
/// The priority parameter determines which backend is preferred when
/// multiple backends support the same capability:
///
/// - Priority 100: LlamaCpp is the primary LLM backend
/// - Priority 90 (default): LlamaCpp is preferred after ONNX
/// - Priority 50: LlamaCpp is a fallback option
class LlamaCppBackend {
  static bool _initialized = false;
  static LlamaCppAdapter? _adapter;

  /// Private constructor - use static methods.
  LlamaCppBackend._();

  /// Check if the LlamaCpp backend is initialized.
  static bool get isInitialized => _initialized;

  /// Check if the LlamaCpp backend is available on this platform.
  ///
  /// This checks if the native library can be loaded.
  static bool get isAvailable {
    try {
      PlatformLoader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get the LlamaCpp adapter instance.
  ///
  /// Returns null if not initialized.
  static LlamaCppAdapter? get adapter => _adapter;

  /// Initialize the LlamaCpp backend and register providers.
  ///
  /// This should be called during app initialization before using
  /// any LlamaCpp-based AI capabilities.
  ///
  /// [priority] - Provider priority (higher = preferred). Default: 90.
  ///
  /// Returns true if initialization succeeded, false otherwise.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Initialize with default priority (90)
  /// await LlamaCppBackend.initialize();
  ///
  /// // Initialize with higher priority
  /// await LlamaCppBackend.initialize(priority: 100);
  /// ```
  static Future<bool> initialize({int priority = 90}) async {
    if (_initialized) {
      return true;
    }

    if (!isAvailable) {
      return false;
    }

    try {
      _adapter = LlamaCppAdapter();
      _adapter!.onRegistration(priority: priority);
      _initialized = true;
      return true;
    } catch (e) {
      _adapter = null;
      return false;
    }
  }

  /// Dispose of the LlamaCpp backend and release resources.
  ///
  /// Call this when the app is shutting down or no longer needs
  /// LlamaCpp-based AI capabilities.
  static void dispose() {
    if (_adapter != null) {
      _adapter!.dispose();
      _adapter = null;
    }
    _initialized = false;
  }

  /// Get information about the LlamaCpp backend.
  ///
  /// Returns a map with backend information, or empty map if not initialized.
  static Map<String, dynamic> getBackendInfo() {
    if (_adapter == null) {
      return {};
    }
    return _adapter!.getBackendInfo();
  }

  /// Get the native backend instance.
  ///
  /// Returns null if not initialized.
  static NativeBackend? getNativeBackend() {
    return _adapter?.nativeBackend;
  }

  /// Get the native library version.
  static String get version {
    if (_adapter == null) {
      return 'not initialized';
    }
    return _adapter!.version;
  }

  /// List of available backend names from the native library.
  static List<String> get availableBackends {
    if (!isAvailable) {
      return [];
    }

    // Reuse existing adapter's backend if available
    final existingBackend = _adapter?.nativeBackend;
    if (existingBackend != null) {
      try {
        return existingBackend.getAvailableBackends();
      } catch (_) {
        return [];
      }
    }

    // Otherwise create a temporary backend and dispose it
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
    return LlamaCppAdapter.supportedQuantizations.contains(quantization);
  }

  /// Get list of supported quantization levels.
  static List<String> get supportedQuantizations =>
      LlamaCppAdapter.supportedQuantizations;
}
