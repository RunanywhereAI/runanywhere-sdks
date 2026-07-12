/// DartBridge+VLM
///
/// Thin generated-proto VLM bridge. Commons lifecycle owns the loaded VLM
/// service; Dart passes app-owned image request bytes and receives generated
/// VLM result/stream protos.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart'
    show RacNative, RacProtoBuffer;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/sdk_events.pb.dart' show SDKEvent;
import 'package:runanywhere/generated/vlm_options.pb.dart'
    show VLMGenerationRequest, VLMResult, VLMStreamEvent;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

typedef _RacVlmGenerateProtoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Uint8>,
      ffi.Size,
      ffi.Pointer<RacProtoBuffer>,
    );
typedef _RacVlmGenerateProtoDart =
    int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<RacProtoBuffer>);

typedef _RacVlmCancelLifecycleProtoNative =
    ffi.Int32 Function(ffi.Pointer<RacProtoBuffer>);
typedef _RacVlmCancelLifecycleProtoDart =
    int Function(ffi.Pointer<RacProtoBuffer>);

/// VLM generated-proto bridge for C++ interop.
class DartBridgeVLM {
  static final DartBridgeVLM shared = DartBridgeVLM._();

  DartBridgeVLM._();

  final _logger = SDKLogger('DartBridge.VLM');

  Future<VLMResult> processImageProto(VLMGenerationRequest request) async {
    final fn = _lookupGenerateProto();
    return DartBridgeProtoUtils.callRequest<VLMResult>(
      request: request,
      invoke: fn,
      decode: VLMResult.fromBuffer,
      symbol: 'rac_vlm_generate_proto',
    );
  }

  Stream<VLMStreamEvent> processImageStreamProto(VLMGenerationRequest request) {
    if (RacNative.bindings.ra_flutter_vlm_stream_proto_native_port == null) {
      return Stream<VLMStreamEvent>.error(
        UnsupportedError(
          'ra_flutter_vlm_stream_proto_native_port is unavailable',
        ),
      );
    }

    final controller = StreamController<VLMStreamEvent>(sync: false);
    final receivePort = ReceivePort();
    var sawTerminalEvent = false;
    var tornDown = false;

    void teardown() {
      if (tornDown) return;
      tornDown = true;
      receivePort.close();
    }

    receivePort.listen((Object? message) {
      if (message is Uint8List) {
        // One serialized VLMStreamEvent, already copied in the worker's
        // synchronous callback, delivered over the port in emission order.
        if (controller.isClosed) return;
        try {
          final event = VLMStreamEvent.fromBuffer(message);
          sawTerminalEvent = sawTerminalEvent || event.isFinal;
          controller.add(event);
          if (event.isFinal) {
            unawaited(controller.close());
          }
        } catch (e, st) {
          controller.addError(e, st);
          unawaited(controller.close());
        }
      } else if (message is int) {
        // rc sentinel — always the LAST message on this port (FIFO after every
        // event). Early-return rcs (parse / no-model errors) produce no
        // terminal event, so surface them.
        if (message != RacResultCode.success &&
            !sawTerminalEvent &&
            !controller.isClosed) {
          controller.addError(
            StateError(
              'rac_vlm_stream_proto failed: ${RacResultCode.getMessage(message)}',
            ),
          );
        }
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
        teardown();
      }
    });

    final requestBytes = request.writeToBuffer();
    final worker = _runVlmStreamNativePortWorker(
      requestBytes,
      receivePort.sendPort.nativePort,
    );
    unawaited(
      worker.catchError((Object e, StackTrace st) {
        // Worker isolate crashed (RemoteError) before the rc sentinel.
        if (!controller.isClosed) {
          controller.addError(e, st);
          unawaited(controller.close());
        }
        teardown();
        return RacResultCode.success;
      }),
    );

    // Cancel sets the lifecycle cancel flag; the worker's blocking call returns
    // shortly after and the rc sentinel closes the port.
    controller.onCancel = cancel;

    return controller.stream;
  }

  /// Cancel lifecycle-owned VLM generation.
  void cancel() {
    final fn = _lookupCancelLifecycleProtoOrNull();
    if (fn == null) {
      _logger.debug('rac_vlm_cancel_lifecycle_proto is unavailable');
      return;
    }

    try {
      DartBridgeProtoUtils.callOut<SDKEvent>(
        invoke: fn,
        decode: SDKEvent.fromBuffer,
        symbol: 'rac_vlm_cancel_lifecycle_proto',
      );
      _logger.debug('VLM lifecycle processing cancelled');
    } catch (e) {
      _logger.error('Failed to cancel lifecycle-owned VLM processing: $e');
    }
  }

  _RacVlmGenerateProtoDart _lookupGenerateProto() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_RacVlmGenerateProtoNative, _RacVlmGenerateProtoDart>(
            'rac_vlm_generate_proto',
          );
    } catch (_) {
      throw UnsupportedError('rac_vlm_generate_proto is unavailable');
    }
  }

  _RacVlmCancelLifecycleProtoDart? _lookupCancelLifecycleProtoOrNull() {
    try {
      return PlatformLoader.loadCommons().lookupFunction<
        _RacVlmCancelLifecycleProtoNative,
        _RacVlmCancelLifecycleProtoDart
      >('rac_vlm_cancel_lifecycle_proto');
    } catch (_) {
      return null;
    }
  }

  // MARK: - Cleanup

  /// Best-effort VLM teardown for `DartBridge.shutdown()`. Mirrors Swift
  /// `CppBridge+VLM.destroy()` so the Flutter shutdown path is shape-symmetric
  /// with the other modalities (LLM, STT, TTS, VAD, VoiceAgent). The current
  /// Dart VLM bridge does not pin a level-3 handle — VLM generate/stream/cancel
  /// route through the lifecycle-owned proto ABIs, so the commons unload path
  /// already releases that state. We still cancel any in-flight lifecycle
  /// generation so workers don't keep burning CPU after shutdown, mirroring
  /// what Swift's `ComponentActor.destroy()` does internally before tearing
  /// down its retained handle.
  void destroy() {
    try {
      cancel();
      _logger.debug('VLM lifecycle cancelled on shutdown');
    } catch (e) {
      _logger.debug('VLM cancel-on-destroy failed: $e');
    }
  }
}

// MARK: - Worker-isolate entry points
//
// VLM inference (image encode + prefill + decode) is a long synchronous block.
// Run on the calling isolate — the Flutter UI isolate — it freezes the UI for
// the whole generation (unlike token-by-token LLM, a single VLM frame is one
// uninterrupted FFI call). The blocking `rac_vlm_stream_proto` therefore runs
// in a short-lived worker isolate (`Isolate.run`). On iOS and Android, the
// Flutter plugin exports a native-port helper that copies proto bytes inside
// the C callback and posts owned `Uint8List` messages to the main isolate. That
// path is safe for MLX and any backend that invokes VLM callbacks from native
// worker threads.
//
// Top-level so the `Isolate.run` closure captures ONLY its two sendable
// parameters (`Uint8List` + `SendPort`) — never the method's unsendable
// `ReceivePort`/`StreamController`. `RacNative.bindings` and
// `PlatformLoader.loadCommons()` are per-isolate and re-resolve the dylib
// symbols on first access in the worker (idempotent).

/// Runs the Flutter native-port stream helper in a worker isolate. The helper
/// itself posts copied stream bytes to [nativePort] and posts the return code
/// as the final sentinel.
Future<int> _runVlmStreamNativePortWorker(
  Uint8List requestBytes,
  int nativePort,
) => Isolate.run(() => _vlmStreamNativePortWorker(requestBytes, nativePort));

int _vlmStreamNativePortWorker(Uint8List requestBytes, int nativePort) {
  final fn = RacNative.bindings.ra_flutter_vlm_stream_proto_native_port;
  if (fn == null) {
    throw UnsupportedError(
      'ra_flutter_vlm_stream_proto_native_port is unavailable',
    );
  }

  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  try {
    return fn(
      requestPtr,
      requestBytes.length,
      nativePort,
      ffi.NativeApi.postCObject,
    );
  } finally {
    calloc.free(requestPtr);
  }
}
