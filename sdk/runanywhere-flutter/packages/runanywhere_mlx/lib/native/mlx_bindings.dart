import 'dart:ffi';
import 'dart:io';

import 'package:runanywhere/native/types/basic_types.dart';

typedef _RegisterNative = Int32 Function(Int32 priority);
typedef _RegisterDart = int Function(int priority);
typedef _NoArgNative = Int32 Function();
typedef _NoArgDart = int Function();

/// FFI bindings for the Swift MLX runtime C entrypoints.
class MLXBindings {
  final DynamicLibrary _lib;

  late final _RegisterDart? _register;
  late final _NoArgDart? _unregister;
  late final _NoArgDart? _isRegistered;
  late final _NoArgDart? _isAvailable;

  MLXBindings() : _lib = _loadLibrary() {
    _bindFunctions();
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('MLX is only available on iOS and macOS');
  }

  static bool checkAvailability() {
    try {
      final lib = _loadLibrary();
      final isAvailable = lib.lookupFunction<_NoArgNative, _NoArgDart>(
        'ra_mlx_runtime_is_available',
      )();
      lib.lookup<NativeFunction<_RegisterNative>>('ra_mlx_register_runtime');
      return isAvailable != 0;
    } catch (_) {
      return false;
    }
  }

  void _bindFunctions() {
    try {
      _register = _lib.lookupFunction<_RegisterNative, _RegisterDart>(
        'ra_mlx_register_runtime',
      );
    } catch (_) {
      _register = null;
    }

    try {
      _unregister = _lib.lookupFunction<_NoArgNative, _NoArgDart>(
        'ra_mlx_unregister_runtime',
      );
    } catch (_) {
      _unregister = null;
    }

    try {
      _isRegistered = _lib.lookupFunction<_NoArgNative, _NoArgDart>(
        'ra_mlx_runtime_is_registered',
      );
    } catch (_) {
      _isRegistered = null;
    }

    try {
      _isAvailable = _lib.lookupFunction<_NoArgNative, _NoArgDart>(
        'ra_mlx_runtime_is_available',
      );
    } catch (_) {
      _isAvailable = null;
    }
  }

  int register(int priority) {
    return _register?.call(priority) ?? RacResultCode.errorNotSupported;
  }

  int unregister() {
    return _unregister?.call() ?? RacResultCode.errorNotSupported;
  }

  bool get isRegistered => (_isRegistered?.call() ?? 0) != 0;

  bool get isAvailable => (_isAvailable?.call() ?? 0) != 0;
}
