import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// FFI bindings for the private QHexRT (Qualcomm Hexagon NPU) backend.
///
/// Registration symbols live in `librac_backend_qhexrt.so`; the pre-flight NPU
/// probe (`rac_npu_probe`) lives in `librac_commons.so`. Android/Snapdragon only.
class QhexrtBindings {
  final DynamicLibrary _backend;
  final DynamicLibrary _commons;

  late final RacBackendQhexrtRegisterDart? _register;
  late final RacBackendQhexrtUnregisterDart? _unregister;
  late final RacNpuProbeDart? _probe;

  QhexrtBindings()
      : _backend = _loadBackend(),
        _commons = PlatformLoader.loadCommons() {
    _bindFunctions();
  }

  static DynamicLibrary _loadBackend() {
    if (Platform.isAndroid) {
      try {
        PlatformLoader.loadCommons();
      } catch (_) {
        // continue — backend load may still resolve
      }
      final names = ['librac_backend_qhexrt.so', 'librac_backend_qhexrt_jni.so'];
      for (final name in names) {
        try {
          return DynamicLibrary.open(name);
        } catch (_) {
          // try next
        }
      }
      throw ArgumentError(
        'Could not load QHexRT backend library on Android. Tried: ${names.join(", ")}',
      );
    }
    return PlatformLoader.loadCommons();
  }

  /// True on Android when the backend registration symbol resolves.
  static bool checkAvailability() {
    if (!Platform.isAndroid) return false;
    try {
      final lib = _loadBackend();
      lib.lookup<NativeFunction<Int32 Function()>>('rac_backend_qhexrt_register');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _bindFunctions() {
    try {
      _register = _backend.lookupFunction<RacBackendQhexrtRegisterNative,
          RacBackendQhexrtRegisterDart>('rac_backend_qhexrt_register');
    } catch (_) {
      _register = null;
    }
    try {
      _unregister = _backend.lookupFunction<RacBackendQhexrtUnregisterNative,
          RacBackendQhexrtUnregisterDart>('rac_backend_qhexrt_unregister');
    } catch (_) {
      _unregister = null;
    }
    try {
      _probe = _commons.lookupFunction<RacNpuProbeNative, RacNpuProbeDart>('rac_npu_probe');
    } catch (_) {
      _probe = null;
    }
  }

  bool get isAvailable => _register != null;

  int register() => _register?.call() ?? RacResultCode.errorNotSupported;

  int unregister() => _unregister?.call() ?? RacResultCode.errorNotSupported;

  /// Probe the Hexagon NPU. Returns a record the public API maps to NpuInfo.
  ({String socModel, int socId, int arch, bool supported}) probe() {
    final fn = _probe;
    if (fn == null) return (socModel: '', socId: -1, arch: 0, supported: false);
    final ptr = calloc<RacNpuInfo>();
    try {
      final rc = fn(ptr);
      if (rc != 0) return (socModel: '', socId: -1, arch: 0, supported: false);
      final ref = ptr.ref;
      final bytes = <int>[];
      for (var i = 0; i < 64; i++) {
        final b = ref.socModel[i];
        if (b == 0) break;
        bytes.add(b);
      }
      return (
        socModel: String.fromCharCodes(bytes),
        socId: ref.socId,
        arch: ref.hexagonArch,
        supported: ref.qhexrtSupported != 0,
      );
    } finally {
      calloc.free(ptr);
    }
  }
}

// rac_npu_info_t — fixed 76-byte POD (rac_bool_t == int32_t).
final class RacNpuInfo extends Struct {
  @Array(64)
  external Array<Uint8> socModel;
  @Int32()
  external int socId;
  @Int32()
  external int hexagonArch;
  @Int32()
  external int qhexrtSupported;
}

typedef RacBackendQhexrtRegisterNative = Int32 Function();
typedef RacBackendQhexrtRegisterDart = int Function();
typedef RacBackendQhexrtUnregisterNative = Int32 Function();
typedef RacBackendQhexrtUnregisterDart = int Function();
typedef RacNpuProbeNative = Int32 Function(Pointer<RacNpuInfo>);
typedef RacNpuProbeDart = int Function(Pointer<RacNpuInfo>);
