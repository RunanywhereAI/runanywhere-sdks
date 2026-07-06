import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere_mlx/native/mlx_bindings.dart';

/// Apple MLX backend module.
///
/// Models are registered through `RunAnywhere.models`; this module only
/// installs the Swift MLX callback table into the C++ commons backend.
class MLX {
  MLX._();

  static const String version = '1.0.0';

  static bool _isRegistered = false;
  static MLXBindings? _bindings;
  static final _logger = SDKLogger('MLX');

  static Future<bool> register({int priority = 100}) async {
    if (_isRegistered) {
      _logger.debug('MLX already registered');
      return true;
    }

    if (!isAvailable) {
      _logger.warning(
        'MLX Swift runtime not linked. Add the RunAnywhereMLX Swift package product on iOS/macOS.',
      );
      return false;
    }

    try {
      _bindings = MLXBindings();
      final result = _bindings!.register(priority);
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

  static Future<bool> unregister() async {
    if (!_isRegistered) return true;

    final result = _bindings?.unregister() ?? RacResultCode.errorNotSupported;
    if (result != RacResultCode.success) {
      _logger.warning('MLX backend unregistration returned: $result');
      return false;
    }

    _isRegistered = false;
    _logger.info('MLX backend unregistered');
    return true;
  }

  static bool get isRegistered {
    final bindings = _bindings;
    if (bindings == null) return _isRegistered;
    _isRegistered = bindings.isRegistered;
    return _isRegistered;
  }

  static bool get isAvailable => MLXBindings.checkAvailability();

  static void autoRegister() {
    unawaited(register());
  }
}
