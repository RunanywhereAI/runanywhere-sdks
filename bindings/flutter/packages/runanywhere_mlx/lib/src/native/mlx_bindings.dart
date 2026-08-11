import 'dart:ffi';
import 'dart:io';

typedef _RegisterNative = Int32 Function(Int32 priority);
typedef _RegisterDart = int Function(int priority);
typedef _NoArgNative = Int32 Function();
typedef _NoArgDart = int Function();

/// FFI bindings for the canonical Swift MLX runtime C entrypoints.
final class MLXBindings {
  MLXBindings() : _library = _loadLibrary() {
    _register = _library.lookupFunction<_RegisterNative, _RegisterDart>(
      'ra_mlx_register_runtime',
    );
    _unregister = _library.lookupFunction<_NoArgNative, _NoArgDart>(
      'ra_mlx_unregister_runtime',
    );
    _isRegistered = _library.lookupFunction<_NoArgNative, _NoArgDart>(
      'ra_mlx_runtime_is_registered',
    );
    _isAvailable = _library.lookupFunction<_NoArgNative, _NoArgDart>(
      'ra_mlx_runtime_is_available',
    );
  }

  final DynamicLibrary _library;
  late final _RegisterDart _register;
  late final _NoArgDart _unregister;
  late final _NoArgDart _isRegistered;
  late final _NoArgDart _isAvailable;

  static DynamicLibrary _loadLibrary() {
    if (!Platform.isIOS) {
      throw UnsupportedError(
        'MLX runtime entrypoints are available only on iOS',
      );
    }
    return DynamicLibrary.process();
  }

  /// Returns true only when all lifecycle symbols are linked and the Swift
  /// runtime reports itself available.
  static bool checkAvailability() {
    try {
      final library = _loadLibrary();
      library.lookup<NativeFunction<_RegisterNative>>(
        'ra_mlx_register_runtime',
      );
      library.lookup<NativeFunction<_NoArgNative>>('ra_mlx_unregister_runtime');
      library.lookup<NativeFunction<_NoArgNative>>(
        'ra_mlx_runtime_is_registered',
      );
      final isAvailable = library.lookupFunction<_NoArgNative, _NoArgDart>(
        'ra_mlx_runtime_is_available',
      )();
      return isAvailable != 0;
    } catch (_) {
      return false;
    }
  }

  int register(int priority) => _register(priority);

  int unregister() => _unregister();

  bool get isRegistered => _isRegistered() != 0;

  bool get isAvailable => _isAvailable() != 0;
}
