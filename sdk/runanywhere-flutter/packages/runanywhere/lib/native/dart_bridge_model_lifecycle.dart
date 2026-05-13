// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/sdk_events.pb.dart' as sdk_events_pb;
import 'package:runanywhere/generated/sdk_events.pbenum.dart'
    as sdk_events_enum;
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/types/basic_types.dart';
/// Proto-backed model/component lifecycle bridge.
///
/// This is the Flutter binding for `rac_model_lifecycle_*_proto` and keeps the
/// live model lifecycle truth in commons instead of mirroring component state in
/// Dart maps or DTOs.
class DartBridgeModelLifecycle {
  DartBridgeModelLifecycle._();

  static final _logger = SDKLogger('DartBridge.ModelLifecycle');
  static final DartBridgeModelLifecycle instance = DartBridgeModelLifecycle._();

  Future<model_pb.ModelLoadResult> load(
    model_pb.ModelLoadRequest request,
  ) async {
    final fn = RacNative.bindings.rac_model_lifecycle_load_proto;
    if (fn == null) {
      return model_pb.ModelLoadResult(
        success: false,
        modelId: request.modelId,
        category: request.category,
        framework: request.framework,
        errorMessage: 'Model lifecycle load proto API is unavailable',
      );
    }

    final registry = DartBridgeModelRegistry.instance.nativeHandle;
    if (registry == null || registry == nullptr) {
      return model_pb.ModelLoadResult(
        success: false,
        modelId: request.modelId,
        category: request.category,
        framework: request.framework,
        errorMessage: 'Model registry is not initialized',
      );
    }

    // Loading a model is a blocking C++ call that may take 100ms-30s
    // depending on backend (e.g. Sherpa Piper TTS initializes espeak-ng
    // and large ONNX graphs synchronously). Run it on a helper isolate so
    // the main isolate stays responsive — matches the Swift SDK's
    // DispatchQueue.global() and Kotlin's withContext(Dispatchers.IO).
    // Native pointers are address-stable across isolates in the same
    // process; we marshal them as integers via _LifecycleLoadSpec.
    final spec = _LifecycleLoadSpec(
      registryAddr: registry.address,
      requestBytes: request.writeToBuffer(),
    );
    _LifecycleLoadResult outcome;
    try {
      outcome = await Isolate.run<_LifecycleLoadResult>(
        () => _loadBlocking(spec),
      );
    } catch (e) {
      _logger.debug('rac_model_lifecycle_load_proto isolate error: $e');
      return model_pb.ModelLoadResult(
        success: false,
        modelId: request.modelId,
        category: request.category,
        framework: request.framework,
        errorMessage: 'rac_model_lifecycle_load_proto isolate error: $e',
      );
    }

    if (outcome.resultBytes != null && outcome.resultBytes!.isNotEmpty) {
      try {
        return model_pb.ModelLoadResult.fromBuffer(outcome.resultBytes!);
      } catch (e) {
        _logger.debug('rac_model_lifecycle_load_proto decode error: $e');
      }
    }

    if (outcome.errorMessage != null) {
      _logger.debug(
        'rac_model_lifecycle_load_proto failed: ${outcome.errorMessage}',
      );
    }

    return model_pb.ModelLoadResult(
      success: false,
      modelId: request.modelId,
      category: request.category,
      framework: request.framework,
      errorMessage:
          outcome.errorMessage ?? 'Model lifecycle load returned no result',
    );
  }

  Future<model_pb.ModelUnloadResult> unload(
    model_pb.ModelUnloadRequest request,
  ) async {
    final fn = RacNative.bindings.rac_model_lifecycle_unload_proto;
    if (fn == null) {
      return model_pb.ModelUnloadResult(
        success: false,
        errorMessage: 'Model lifecycle unload proto API is unavailable',
      );
    }

    final result = await _callProto(
      request,
      fn,
      model_pb.ModelUnloadResult.fromBuffer,
      'rac_model_lifecycle_unload_proto',
    );
    return result ??
        model_pb.ModelUnloadResult(
          success: false,
          errorMessage: 'Model lifecycle unload returned no result',
        );
  }

  Future<model_pb.CurrentModelResult> current(
    model_pb.CurrentModelRequest request,
  ) async {
    final fn = RacNative.bindings.rac_model_lifecycle_current_model_proto;
    if (fn == null) return model_pb.CurrentModelResult();

    final result = await _callProto(
      request,
      fn,
      model_pb.CurrentModelResult.fromBuffer,
      'rac_model_lifecycle_current_model_proto',
      logFailures: false,
    );
    return result ?? model_pb.CurrentModelResult();
  }

  sdk_events_pb.ComponentLifecycleSnapshot? componentSnapshot(
    sdk_events_enum.SDKComponent component,
  ) {
    final fn = RacNative.bindings.rac_component_lifecycle_snapshot_proto;
    if (fn == null) return null;

    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;
    try {
      bindings.rac_proto_buffer_init(out);
      final code = fn(component.value, out);
      if (code != RacResultCode.success ||
          out.ref.status != RacResultCode.success) {
        _logger.debug(
          'rac_component_lifecycle_snapshot_proto failed: '
          '${_protoBufferError(out, code)}',
        );
        return null;
      }
      return _decodeBuffer(
        out,
        sdk_events_pb.ComponentLifecycleSnapshot.fromBuffer,
      );
    } catch (e) {
      _logger.debug('rac_component_lifecycle_snapshot_proto error: $e');
      return null;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(out);
    }
  }

  void reset() {
    try {
      RacNative.bindings.rac_model_lifecycle_reset?.call();
    } catch (e) {
      _logger.debug('rac_model_lifecycle_reset error: $e');
    }
  }

  Future<T?> _callProto<T extends GeneratedMessage>(
    GeneratedMessage request,
    int Function(Pointer<Uint8>, int, Pointer<RacProtoBuffer>) fn,
    T Function(List<int>) decode,
    String symbol, {
    bool logFailures = true,
  }) async {
    final bytes = request.writeToBuffer();
    final requestPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      if (bytes.isNotEmpty) {
        requestPtr.asTypedList(bytes.length).setAll(0, bytes);
      }
      bindings.rac_proto_buffer_init(out);
      final code = fn(requestPtr, bytes.length, out);
      if (code != RacResultCode.success ||
          out.ref.status != RacResultCode.success) {
        if (logFailures) {
          _logger.debug('$symbol failed: ${_protoBufferError(out, code)}');
        }
        return null;
      }
      return _decodeBuffer(out, decode);
    } catch (e) {
      _logger.debug('$symbol error: $e');
      return null;
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(requestPtr);
      calloc.free(out);
    }
  }

  T _decodeBuffer<T extends GeneratedMessage>(
    Pointer<RacProtoBuffer> out,
    T Function(List<int>) decode,
  ) {
    if (out.ref.data == nullptr || out.ref.size == 0) {
      return decode(const <int>[]);
    }
    final resultBytes =
        out.ref.data.asTypedList(out.ref.size).toList(growable: false);
    return decode(resultBytes);
  }

  String _protoBufferError(Pointer<RacProtoBuffer> out, int code) {
    if (out.ref.errorMessage != nullptr) {
      return out.ref.errorMessage.toDartString();
    }
    return 'code=$code status=${out.ref.status}';
  }
}

// ============================================================================
// Helper isolate worker for `rac_model_lifecycle_load_proto`.
//
// Model load is a blocking C++ call (e.g. Sherpa Piper TTS initializes
// espeak-ng + large ONNX graphs synchronously, taking hundreds of
// milliseconds to seconds). Running it on the main Dart isolate freezes
// the UI and — on iOS — has been observed to trigger silent termination
// on the iOS simulator when the underlying sherpa-onnx static initializer
// blows the smaller main-isolate stack. Wrapping the FFI call in
// `Isolate.run` mirrors the established SDK pattern (HttpClientAdapter,
// LLM generate, TTS synthesize) and matches Swift's
// DispatchQueue.global() / Kotlin's withContext(Dispatchers.IO).
//
// Native pointers are address-stable across isolates in the same OS
// process; we marshal them as integers. `RacNative.bindings` is a Meyers
// singleton — on the worker isolate it re-resolves against the same
// shared library (DynamicLibrary.process() on iOS,
// DynamicLibrary.open('librac_commons.so') on Android), which is also
// safe because the underlying C++ state is process-global.
// ============================================================================

class _LifecycleLoadSpec {
  const _LifecycleLoadSpec({
    required this.registryAddr,
    required this.requestBytes,
  });

  final int registryAddr;
  final Uint8List requestBytes;
}

class _LifecycleLoadResult {
  const _LifecycleLoadResult({
    required this.code,
    this.resultBytes,
    this.errorMessage,
  });

  final int code;
  final Uint8List? resultBytes;
  final String? errorMessage;
}

_LifecycleLoadResult _loadBlocking(_LifecycleLoadSpec spec) {
  final bindings = RacNative.bindings;
  final fn = bindings.rac_model_lifecycle_load_proto;
  if (fn == null) {
    return const _LifecycleLoadResult(
      code: RacResultCode.errorFeatureNotAvailable,
      errorMessage: 'rac_model_lifecycle_load_proto is unavailable',
    );
  }

  final RacHandle registry = Pointer<Void>.fromAddress(spec.registryAddr);
  final bytes = spec.requestBytes;
  final requestPtr = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  final out = calloc<RacProtoBuffer>();
  try {
    if (bytes.isNotEmpty) {
      requestPtr.asTypedList(bytes.length).setAll(0, bytes);
    }
    bindings.rac_proto_buffer_init(out);
    final code = fn(registry, requestPtr, bytes.length, out);
    final hasBuffer = out.ref.data != nullptr && out.ref.size > 0;
    final bufferBytes = hasBuffer
        ? Uint8List.fromList(out.ref.data.asTypedList(out.ref.size))
        : null;
    if (code != RacResultCode.success ||
        out.ref.status != RacResultCode.success) {
      String? message;
      if (out.ref.errorMessage != nullptr) {
        message = out.ref.errorMessage.toDartString();
      }
      return _LifecycleLoadResult(
        code: code,
        resultBytes: bufferBytes,
        errorMessage: message ?? 'code=$code status=${out.ref.status}',
      );
    }
    return _LifecycleLoadResult(code: code, resultBytes: bufferBytes);
  } catch (e) {
    return _LifecycleLoadResult(
      code: RacResultCode.errorInternal,
      errorMessage: 'rac_model_lifecycle_load_proto threw: $e',
    );
  } finally {
    bindings.rac_proto_buffer_free(out);
    calloc.free(requestPtr);
    calloc.free(out);
  }
}
