import '../../native/native_backend.dart';
import '../../native/platform_loader.dart';
import 'onnx_adapter.dart';

/// Main entry point for the ONNX Runtime backend.
///
/// This class manages the lifecycle of the ONNX backend and provides
/// methods to initialize and access ONNX-based AI services.
///
/// ## Usage
///
/// ```dart
/// import 'package:runanywhere/backends/onnx/onnx.dart';
///
/// void main() async {
///   // Initialize with default priority
///   final success = await OnnxBackend.initialize();
///
///   if (success) {
///     // ONNX providers are now registered with ModuleRegistry
///     // Use standard RunAnywhere API to access services
///   }
/// }
/// ```
///
/// ## Priority System
///
/// The priority parameter determines which backend is preferred when
/// multiple backends support the same capability:
///
/// - Priority 100 (default): ONNX is preferred
/// - Priority 90: ONNX is secondary to a priority-100 backend
/// - Priority 50: ONNX is a fallback option
class OnnxBackend {
  static bool _initialized = false;
  static OnnxAdapter? _adapter;

  /// Private constructor - use static methods.
  OnnxBackend._();

  /// Check if the ONNX backend is initialized.
  static bool get isInitialized => _initialized;

  /// Check if the ONNX backend is available on this platform.
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

  /// Get the ONNX adapter instance.
  ///
  /// Returns null if not initialized.
  static OnnxAdapter? get adapter => _adapter;

  /// Initialize the ONNX backend and register providers.
  ///
  /// This should be called during app initialization before using
  /// any ONNX-based AI capabilities.
  ///
  /// [priority] - Provider priority (higher = preferred). Default: 100.
  ///
  /// Returns true if initialization succeeded, false otherwise.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Initialize with default priority
  /// await OnnxBackend.initialize();
  ///
  /// // Initialize with lower priority (for fallback)
  /// await OnnxBackend.initialize(priority: 50);
  /// ```
  static Future<bool> initialize({int priority = 100}) async {
    if (_initialized) {
      return true;
    }

    if (!isAvailable) {
      return false;
    }

    try {
      _adapter = OnnxAdapter();
      _adapter!.onRegistration(priority: priority);
      _initialized = true;
      return true;
    } catch (e) {
      _adapter = null;
      return false;
    }
  }

  /// Dispose of the ONNX backend and release resources.
  ///
  /// Call this when the app is shutting down or no longer needs
  /// ONNX-based AI capabilities.
  static void dispose() {
    if (_adapter != null) {
      _adapter!.dispose();
      _adapter = null;
    }
    _initialized = false;
  }

  /// Get information about the ONNX backend.
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
    try {
      final backend = NativeBackend();
      return backend.getAvailableBackends();
    } catch (_) {
      return [];
    }
  }
}
