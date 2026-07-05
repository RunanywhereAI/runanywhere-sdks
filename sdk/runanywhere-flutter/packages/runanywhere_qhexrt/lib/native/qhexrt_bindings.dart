import 'dart:ffi';
import 'dart:io';

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// FFI bindings for the private QHexRT (Qualcomm Hexagon NPU) backend.
///
/// Registration symbols live in `librac_backend_qhexrt.so`; the pre-flight NPU
/// probe (`rac_npu_probe_proto`) lives in `librac_commons.so` and returns
/// serialized `runanywhere.v1.NpuCapability` proto bytes decoded with the
/// generated [NpuCapability] type. Android/Snapdragon only.
class QhexrtBindings {
  final DynamicLibrary _backend;
  final DynamicLibrary _commons;

  static final _logger = SDKLogger('QHexRT.Bindings');

  late final RacBackendQhexrtRegisterDart? _register;
  late final RacBackendQhexrtUnregisterDart? _unregister;
  late final RacNpuProbeProtoDart? _probeProto;

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
    } catch (e) {
      _logger.warning('Failed to resolve rac_backend_qhexrt_register: $e');
      _register = null;
    }
    try {
      _unregister = _backend.lookupFunction<RacBackendQhexrtUnregisterNative,
          RacBackendQhexrtUnregisterDart>('rac_backend_qhexrt_unregister');
    } catch (e) {
      _logger.warning('Failed to resolve rac_backend_qhexrt_unregister: $e');
      _unregister = null;
    }
    try {
      _probeProto = _commons.lookupFunction<RacNpuProbeProtoNative,
          RacNpuProbeProtoDart>('rac_npu_probe_proto');
    } catch (e) {
      _logger.warning('Failed to resolve rac_npu_probe_proto: $e');
      _probeProto = null;
    }
  }

  bool get isAvailable => _register != null;

  int register() => _register?.call() ?? RacResultCode.errorNotSupported;

  int unregister() => _unregister?.call() ?? RacResultCode.errorNotSupported;

  /// Probe the Hexagon NPU via commons' `rac_npu_probe_proto`, decoding the
  /// serialized `runanywhere.v1.NpuCapability`. Throws when the symbol is
  /// missing or the native call fails; callers map that to the unknown
  /// fallback.
  NpuCapability probeProto() {
    final fn = _probeProto;
    if (fn == null) {
      throw StateError('rac_npu_probe_proto is not available in librac_commons.so');
    }
    return DartBridgeProtoUtils.callOut<NpuCapability>(
      invoke: fn,
      decode: NpuCapability.fromBuffer,
      symbol: 'rac_npu_probe_proto',
    );
  }
}

typedef RacBackendQhexrtRegisterNative = Int32 Function();
typedef RacBackendQhexrtRegisterDart = int Function();
typedef RacBackendQhexrtUnregisterNative = Int32 Function();
typedef RacBackendQhexrtUnregisterDart = int Function();
typedef RacNpuProbeProtoNative = Int32 Function(Pointer<RacProtoBuffer>);
typedef RacNpuProbeProtoDart = int Function(Pointer<RacProtoBuffer>);
