import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/hardware_profile.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// FFI bindings for the private QHexRT (Qualcomm Hexagon NPU) backend.
///
/// Capability, chip-selection, model-catalog, and registration symbols live in
/// `librac_backend_qhexrt.so`. Backend-neutral HTTP/download/extraction and
/// registry work is composed internally with commons. Android/Snapdragon only.
class QhexrtBindings {
  final DynamicLibrary _backend;

  static final _logger = SDKLogger('QHexRT.Bindings');

  late final RacBackendQhexrtRegisterDart? _register;
  late final RacBackendQhexrtUnregisterDart? _unregister;
  late final RacQhexrtProbeProtoDart? _probeProto;
  late final RacQhexrtArchIsSupportedDart? _archIsSupported;
  late final RacQhexrtModelSupportsArchDart? _modelSupportsArch;
  late final RacQhexrtRegisterModelForDeviceProtoDart?
  _registerModelForDeviceProto;

  QhexrtBindings() : this.fromDynamicLibrary(_loadBackend());

  /// Bind an explicitly loaded QHexRT library.
  ///
  /// This keeps host-side FFI contract tests on the same wrapper path used by
  /// Android while production callers continue to use [QhexrtBindings].
  QhexrtBindings.fromDynamicLibrary(this._backend) {
    _bindFunctions();
  }

  static DynamicLibrary _loadBackend() {
    if (Platform.isAndroid) {
      try {
        PlatformLoader.loadCommons();
      } catch (_) {
        // continue — backend load may still resolve
      }
      final names = [
        'librac_backend_qhexrt.so',
        'librac_backend_qhexrt_jni.so',
      ];
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
      lib.lookup<NativeFunction<Int32 Function()>>(
        'rac_backend_qhexrt_register',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _bindFunctions() {
    try {
      _register = _backend
          .lookupFunction<
            RacBackendQhexrtRegisterNative,
            RacBackendQhexrtRegisterDart
          >('rac_backend_qhexrt_register');
    } catch (e) {
      _logger.warning('Failed to resolve rac_backend_qhexrt_register: $e');
      _register = null;
    }
    try {
      _unregister = _backend
          .lookupFunction<
            RacBackendQhexrtUnregisterNative,
            RacBackendQhexrtUnregisterDart
          >('rac_backend_qhexrt_unregister');
    } catch (e) {
      _logger.warning('Failed to resolve rac_backend_qhexrt_unregister: $e');
      _unregister = null;
    }
    try {
      _probeProto = _backend
          .lookupFunction<RacQhexrtProbeProtoNative, RacQhexrtProbeProtoDart>(
            'rac_qhexrt_probe_proto',
          );
    } catch (e) {
      _logger.warning('Failed to resolve rac_qhexrt_probe_proto: $e');
      _probeProto = null;
    }
    try {
      _archIsSupported = _backend
          .lookupFunction<
            RacQhexrtArchIsSupportedNative,
            RacQhexrtArchIsSupportedDart
          >('rac_qhexrt_arch_is_supported');
    } catch (e) {
      _logger.warning('Failed to resolve rac_qhexrt_arch_is_supported: $e');
      _archIsSupported = null;
    }
    try {
      _modelSupportsArch = _backend
          .lookupFunction<
            RacQhexrtModelSupportsArchNative,
            RacQhexrtModelSupportsArchDart
          >('rac_qhexrt_model_supports_arch');
    } catch (e) {
      _logger.warning('Failed to resolve rac_qhexrt_model_supports_arch: $e');
      _modelSupportsArch = null;
    }
    try {
      _registerModelForDeviceProto = _backend
          .lookupFunction<
            RacQhexrtRegisterModelForDeviceProtoNative,
            RacQhexrtRegisterModelForDeviceProtoDart
          >('rac_qhexrt_register_model_for_device_proto');
    } catch (e) {
      _logger.warning(
        'Failed to resolve rac_qhexrt_register_model_for_device_proto: $e',
      );
      _registerModelForDeviceProto = null;
    }
  }

  bool get isAvailable => _register != null;

  int register() => _register?.call() ?? RacResultCode.errorNotSupported;

  int unregister() => _unregister?.call() ?? RacResultCode.errorNotSupported;

  /// Probe the Hexagon NPU via `rac_qhexrt_probe_proto`, decoding the
  /// serialized `runanywhere.v1.NpuCapability`. Throws when the symbol is
  /// missing or the native call fails; callers map that to the unknown
  /// fallback.
  NpuCapability probeProto() {
    final fn = _probeProto;
    if (fn == null) {
      throw StateError(
        'rac_qhexrt_probe_proto is not available in librac_backend_qhexrt.so',
      );
    }
    return DartBridgeProtoUtils.callOut<NpuCapability>(
      invoke: fn,
      decode: NpuCapability.fromBuffer,
      symbol: 'rac_qhexrt_probe_proto',
    );
  }

  bool isArchitectureSupported(HexagonArch arch) =>
      _archIsSupported?.call(arch.value) == RAC_TRUE;

  bool modelSupportsArchitecture(
    Iterable<HexagonArch> supportedArches,
    HexagonArch arch,
  ) {
    final fn = _modelSupportsArch;
    if (fn == null) return false;
    final values = QhexrtCatalogWire.archValues(supportedArches);
    final ptr = calloc<Int32>(values.isEmpty ? 1 : values.length);
    try {
      for (var index = 0; index < values.length; index++) {
        ptr[index] = values[index];
      }
      return fn(ptr, values.length, arch.value) == RAC_TRUE;
    } finally {
      calloc.free(ptr);
    }
  }

  ModelInfo? registerModelForDevice(
    RegisterModelFromUrlRequest request,
    Iterable<HexagonArch> supportedArches,
  ) {
    final fn = _registerModelForDeviceProto;
    if (fn == null) {
      throw StateError(
        'rac_qhexrt_register_model_for_device_proto is unavailable',
      );
    }

    final requestBytes = QhexrtCatalogWire.encodeRequest(request);
    final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
    final archValues = QhexrtCatalogWire.archValues(supportedArches);
    final archesPtr = calloc<Int32>(archValues.isEmpty ? 1 : archValues.length);
    final registered = calloc<Int32>();
    final out = calloc<RacProtoBuffer>();

    try {
      for (var index = 0; index < archValues.length; index++) {
        archesPtr[index] = archValues[index];
      }
      RacNative.bindings.rac_proto_buffer_init(out);
      final code = fn(
        requestPtr,
        requestBytes.length,
        archesPtr,
        archValues.length,
        registered,
        out,
      );
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_qhexrt_register_model_for_device_proto',
      );
      if (registered.value != RAC_TRUE) return null;
      if (out.ref.data == nullptr || out.ref.size == 0) {
        throw StateError(
          'QHexRT registration returned an empty ModelInfo payload',
        );
      }
      return DartBridgeProtoUtils.decodeBuffer<ModelInfo>(
        out,
        ModelInfo.fromBuffer,
      );
    } finally {
      RacNative.bindings.rac_proto_buffer_free(out);
      calloc.free(requestPtr);
      calloc.free(archesPtr);
      calloc.free(registered);
      calloc.free(out);
    }
  }
}

/// Generated-enum/protobuf transport only; QHexRT policy stays native.
class QhexrtCatalogWire {
  QhexrtCatalogWire._();

  static List<int> archValues(Iterable<HexagonArch> arches) =>
      arches.map((arch) => arch.value).toList(growable: false);

  static List<int> encodeRequest(RegisterModelFromUrlRequest request) =>
      request.writeToBuffer();
}

typedef RacBackendQhexrtRegisterNative = Int32 Function();
typedef RacBackendQhexrtRegisterDart = int Function();
typedef RacBackendQhexrtUnregisterNative = Int32 Function();
typedef RacBackendQhexrtUnregisterDart = int Function();
typedef RacQhexrtProbeProtoNative = Int32 Function(Pointer<RacProtoBuffer>);
typedef RacQhexrtProbeProtoDart = int Function(Pointer<RacProtoBuffer>);
typedef RacQhexrtArchIsSupportedNative = Int32 Function(Int32);
typedef RacQhexrtArchIsSupportedDart = int Function(int);
typedef RacQhexrtModelSupportsArchNative =
    Int32 Function(Pointer<Int32>, Size, Int32);
typedef RacQhexrtModelSupportsArchDart = int Function(Pointer<Int32>, int, int);
typedef RacQhexrtRegisterModelForDeviceProtoNative =
    Int32 Function(
      Pointer<Uint8>,
      Size,
      Pointer<Int32>,
      Size,
      Pointer<Int32>,
      Pointer<RacProtoBuffer>,
    );
typedef RacQhexrtRegisterModelForDeviceProtoDart =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Int32>,
      int,
      Pointer<Int32>,
      Pointer<RacProtoBuffer>,
    );
