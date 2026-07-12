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
  late final RacQhexrtModelRequiresHfAuthDart? _modelRequiresHfAuth;
  late final RacQhexrtCatalogRegisterModelProtoDart? _catalogRegisterModelProto;
  late final RacQhexrtSetSkelDirectoryDart? _setSkelDirectory;

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
          >('rac_qhexrt_catalog_model_supports_arch');
    } catch (e) {
      _logger.warning(
        'Failed to resolve rac_qhexrt_catalog_model_supports_arch: $e',
      );
      _modelSupportsArch = null;
    }
    try {
      _modelRequiresHfAuth = _backend
          .lookupFunction<
            RacQhexrtModelRequiresHfAuthNative,
            RacQhexrtModelRequiresHfAuthDart
          >('rac_qhexrt_catalog_model_requires_hf_auth');
    } catch (e) {
      _logger.warning(
        'Failed to resolve rac_qhexrt_catalog_model_requires_hf_auth: $e',
      );
      _modelRequiresHfAuth = null;
    }
    try {
      _catalogRegisterModelProto = _backend
          .lookupFunction<
            RacQhexrtCatalogRegisterModelProtoNative,
            RacQhexrtCatalogRegisterModelProtoDart
          >('rac_qhexrt_catalog_register_model_proto');
    } catch (e) {
      _logger.warning(
        'Failed to resolve rac_qhexrt_catalog_register_model_proto: $e',
      );
      _catalogRegisterModelProto = null;
    }
    try {
      _setSkelDirectory = _backend
          .lookupFunction<
            RacQhexrtSetSkelDirectoryNative,
            RacQhexrtSetSkelDirectoryDart
          >('rac_qhexrt_set_skel_directory');
    } catch (e) {
      _logger.warning('Failed to resolve rac_qhexrt_set_skel_directory: $e');
      _setSkelDirectory = null;
    }
  }

  bool get isAvailable => _register != null;

  int register() => _register?.call() ?? RacResultCode.errorNotSupported;

  int unregister() => _unregister?.call() ?? RacResultCode.errorNotSupported;

  /// Configure the app-private directory containing extracted FastRPC skels.
  /// Must be called before backend registration can create a QNN runtime.
  void setSkelDirectory(String? path) {
    final fn = _setSkelDirectory;
    if (fn == null) {
      throw StateError(
        'rac_qhexrt_set_skel_directory is unavailable in the QHexRT backend',
      );
    }
    if (path == null || path.isEmpty) {
      fn(nullptr.cast<Utf8>());
      return;
    }

    final nativePath = path.toNativeUtf8();
    try {
      fn(nativePath);
    } finally {
      calloc.free(nativePath);
    }
  }

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

  bool modelSupportsArchitecture(String modelId, HexagonArch arch) {
    final fn = _modelSupportsArch;
    if (fn == null) return false;
    final id = modelId.toNativeUtf8();
    try {
      return fn(id, arch.value) == RAC_TRUE;
    } finally {
      calloc.free(id);
    }
  }

  bool modelRequiresHfAuth(String modelId) {
    final fn = _modelRequiresHfAuth;
    if (fn == null) return false;
    final id = modelId.toNativeUtf8();
    try {
      return fn(id) == RAC_TRUE;
    } finally {
      calloc.free(id);
    }
  }

  ModelInfo? registerModelForDevice(RegisterModelFromUrlRequest request) {
    final fn = _catalogRegisterModelProto;
    if (fn == null) {
      throw StateError(
        'rac_qhexrt_catalog_register_model_proto is unavailable',
      );
    }

    final requestBytes = QhexrtCatalogWire.encodeRequest(request);
    final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
    final registered = calloc<Int32>();
    final out = calloc<RacProtoBuffer>();

    try {
      RacNative.bindings.rac_proto_buffer_init(out);
      final code = fn(requestPtr, requestBytes.length, registered, out);
      DartBridgeProtoUtils.ensureSuccess(
        out,
        code,
        'rac_qhexrt_catalog_register_model_proto',
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
      calloc.free(registered);
      calloc.free(out);
    }
  }
}

/// Generated-enum/protobuf transport only; QHexRT policy stays native.
class QhexrtCatalogWire {
  QhexrtCatalogWire._();

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
typedef RacQhexrtModelSupportsArchNative = Int32 Function(Pointer<Utf8>, Int32);
typedef RacQhexrtModelSupportsArchDart = int Function(Pointer<Utf8>, int);
typedef RacQhexrtModelRequiresHfAuthNative = Int32 Function(Pointer<Utf8>);
typedef RacQhexrtModelRequiresHfAuthDart = int Function(Pointer<Utf8>);
typedef RacQhexrtCatalogRegisterModelProtoNative =
    Int32 Function(
      Pointer<Uint8>,
      Size,
      Pointer<Int32>,
      Pointer<RacProtoBuffer>,
    );
typedef RacQhexrtCatalogRegisterModelProtoDart =
    int Function(Pointer<Uint8>, int, Pointer<Int32>, Pointer<RacProtoBuffer>);
typedef RacQhexrtSetSkelDirectoryNative = Void Function(Pointer<Utf8>);
typedef RacQhexrtSetSkelDirectoryDart = void Function(Pointer<Utf8>);
