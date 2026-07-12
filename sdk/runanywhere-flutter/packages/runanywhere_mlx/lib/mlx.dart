import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_mlx/src/native/mlx_bindings.dart';

/// Apple MLX backend module.
///
/// The implementation lives in the canonical Swift `RunAnywhereMLX` runtime.
/// This class installs that runtime's callback table into the C++ commons
/// registry. Models and inference are managed through the core `RunAnywhere`
/// APIs after registration succeeds.
abstract final class MLX {
  /// Version of the canonical Swift MLX runtime API.
  static const String version = '1.0.0';

  static bool _isRegistered = false;
  static MLXBindings? _bindings;
  static final SDKLogger _logger = SDKLogger('MLX');

  /// Registers the Apple MLX runtime with the shared backend registry.
  ///
  /// Returns `false` off iOS, in the iOS Simulator, or when the native runtime
  /// was not linked into the application. Calling this method more than once
  /// is safe.
  static Future<bool> register({int priority = 100}) async {
    if (isRegistered) {
      _logger.debug('MLX already registered');
      return true;
    }

    if (!isAvailable) {
      _logger.warning('MLX runtime is unavailable on this target');
      return false;
    }

    try {
      final bindings = _bindings ??= MLXBindings();
      final result = bindings.register(priority);
      if (result != RacResultCode.success &&
          result != RacResultCode.errorModuleAlreadyRegistered) {
        _logger.warning('MLX backend registration returned: $result');
        return false;
      }

      _isRegistered = true;
      _logger.info('MLX backend registered');
      return true;
    } catch (error) {
      _logger.warning('MLX registration failed: $error');
      return false;
    }
  }

  /// Unregisters the Apple MLX runtime.
  static Future<bool> unregister() async {
    if (!isRegistered) return true;

    final bindings = _bindings;
    if (bindings == null) return true;

    final result = bindings.unregister();
    if (result != RacResultCode.success) {
      _logger.warning('MLX backend unregistration returned: $result');
      return false;
    }

    _isRegistered = false;
    _logger.info('MLX backend unregistered');
    return true;
  }

  /// Whether the native runtime is registered with the shared registry.
  static bool get isRegistered {
    final bindings = _bindings;
    if (bindings == null) return _isRegistered;
    _isRegistered = bindings.isRegistered;
    return _isRegistered;
  }

  /// Whether a linked MLX runtime can execute on this target.
  ///
  /// MLX execution requires a physical iOS device. An arm64 simulator slice is
  /// packaged only so consumers can validate compilation and linkage.
  static bool get isAvailable => MLXBindings.checkAvailability();

  /// Starts registration without awaiting it.
  static void autoRegister() {
    unawaited(register());
  }

  /// Releases Dart-side binding state after unregistering the runtime.
  static Future<void> dispose() async {
    await unregister();
    _bindings = null;
    _isRegistered = false;
  }
}
