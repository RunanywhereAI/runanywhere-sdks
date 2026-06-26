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

typedef _RacVlmGenerateProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<RacProtoBuffer>,
);
typedef _RacVlmGenerateProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<RacProtoBuffer>,
);

/// Stream-event callback signature used with `NativeCallable.isolateLocal`.
///
/// Returns `rac_bool_t` (RAC_TRUE = keep streaming, RAC_FALSE = stop). The VLM
/// engine consults this return value on EVERY token and breaks its decode loop
/// on RAC_FALSE (rac_vlm_llamacpp.cpp — "Callback requested stop"). This is
/// UNLIKE the LLM stream callback, whose C type is `void` (rac_llm_stream.h:54)
/// and whose engine ignores any return — so the LLM bridge can use a `Void`
/// trampoline, but VLM CANNOT. A `Void` trampoline leaves a garbage/zero value
/// in the return register; the engine reads it as RAC_FALSE and truncates
/// generation after the first token. Declare the real rac_bool_t (int32) return
/// and emit RAC_TRUE so the engine keeps decoding. Cancellation flows through
/// the lifecycle cancel flag the engine also checks each iteration, not here.
typedef _RacVlmStreamEventProtoCallbackNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

typedef _RacVlmStreamProtoNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.NativeFunction<_RacVlmStreamEventProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef _RacVlmStreamProtoDart = int Function(
  ffi.Pointer<ffi.Uint8>,
  int,
  ffi.Pointer<ffi.NativeFunction<_RacVlmStreamEventProtoCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

typedef _RacVlmCancelLifecycleProtoNative = ffi.Int32 Function(
  ffi.Pointer<RacProtoBuffer>,
);
typedef _RacVlmCancelLifecycleProtoDart = int Function(
  ffi.Pointer<RacProtoBuffer>,
);

/// VLM generated-proto bridge for C++ interop.
class DartBridgeVLM {
  static final DartBridgeVLM shared = DartBridgeVLM._();

  DartBridgeVLM._();

  final _logger = SDKLogger('DartBridge.VLM');

  Future<VLMResult> processImageProto(
    VLMGenerationRequest request,
  ) async {
    final fn = _lookupGenerateProto();
    return DartBridgeProtoUtils.callRequest<VLMResult>(
      request: request,
      invoke: fn,
      decode: VLMResult.fromBuffer,
      symbol: 'rac_vlm_generate_proto',
    );
  }

  Stream<VLMStreamEvent> processImageStreamProto(
    VLMGenerationRequest request,
  ) {
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
          controller.addError(StateError(
            'rac_vlm_stream_proto failed: ${RacResultCode.getMessage(message)}',
          ));
        }
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
        teardown();
      }
    });

    final requestBytes = request.writeToBuffer();
    final sendPort = receivePort.sendPort;
    unawaited(
      _runVlmStreamWorker(requestBytes, sendPort)
          .catchError((Object e, StackTrace st) {
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
              'rac_vlm_generate_proto');
    } catch (_) {
      throw UnsupportedError('rac_vlm_generate_proto is unavailable');
    }
  }

  _RacVlmStreamProtoDart _lookupStreamProto() {
    try {
      return PlatformLoader.loadCommons()
          .lookupFunction<_RacVlmStreamProtoNative, _RacVlmStreamProtoDart>(
              'rac_vlm_stream_proto');
    } catch (_) {
      throw UnsupportedError('rac_vlm_stream_proto is unavailable');
    }
  }

  _RacVlmCancelLifecycleProtoDart? _lookupCancelLifecycleProtoOrNull() {
    try {
      return PlatformLoader.loadCommons().lookupFunction<
          _RacVlmCancelLifecycleProtoNative,
          _RacVlmCancelLifecycleProtoDart>('rac_vlm_cancel_lifecycle_proto');
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
// in a short-lived worker isolate (`Isolate.run`), exactly like
// `dart_bridge_llm.dart`'s streaming path; the worker-owned `isolateLocal`
// callback fires synchronously per event, copies the proto bytes eagerly
// (commons reuses a `thread_local` scratch buffer on the next emission) and
// forwards the copy over a `SendPort`. Now that telemetry HTTP is drained via a
// cross-isolate-safe wakeup poll-queue, the VLM completion event published from
// the worker no longer trips the previous cross-isolate telemetry SIGABRT.
//
// Top-level so the `Isolate.run` closure captures ONLY its two sendable
// parameters (`Uint8List` + `SendPort`) — never the method's unsendable
// `ReceivePort`/`StreamController`. `RacNative.bindings` and
// `PlatformLoader.loadCommons()` are per-isolate and re-resolve the dylib
// symbols on first access in the worker (idempotent).

/// Runs [_vlmStreamWorker] in a worker isolate. Hoisted to top level so the
/// `Isolate.run` closure captures only its sendable parameters.
Future<int> _runVlmStreamWorker(Uint8List requestBytes, SendPort port) =>
    Isolate.run(() => _vlmStreamWorker(requestBytes, port));

/// Blocking body of [DartBridgeVLM.processImageStreamProto]. Runs the
/// single-call streaming ABI on the worker isolate; the worker-owned
/// `isolateLocal` callback fires synchronously per event (commons requires a
/// synchronous same-thread callback because it passes a pointer into a
/// `thread_local` scratch buffer), copies the bytes eagerly, and forwards the
/// copy to the main isolate. The rc is sent LAST on the same port so it is
/// FIFO-ordered after every event.
int _vlmStreamWorker(Uint8List requestBytes, SendPort port) {
  final fn = DartBridgeVLM.shared._lookupStreamProto();
  final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
  ffi.NativeCallable<_RacVlmStreamEventProtoCallbackNative>? callback;
  try {
    callback =
        ffi.NativeCallable<_RacVlmStreamEventProtoCallbackNative>.isolateLocal(
      (
        ffi.Pointer<ffi.Uint8> bytesPtr,
        int bytesLen,
        ffi.Pointer<ffi.Void> _,
      ) {
        if (bytesPtr == ffi.nullptr || bytesLen <= 0) return RAC_TRUE;
        // Copy INSIDE the synchronous callback — commons reuses the scratch
        // buffer the moment we return. The copy is what crosses isolates.
        port.send(Uint8List.fromList(bytesPtr.asTypedList(bytesLen)));
        // RAC_TRUE = keep decoding. The VLM engine breaks its loop on RAC_FALSE,
        // so a void/zero return truncates generation after the first token.
        return RAC_TRUE;
      },
      // Value returned to C if the Dart callback throws: stop the stream.
      exceptionalReturn: RAC_FALSE,
    );

    final rc = fn(
      requestPtr,
      requestBytes.length,
      callback.nativeFunction,
      ffi.nullptr,
    );
    port.send(rc);
    return rc;
  } finally {
    // Defensive quiesce, then close the callable on its owning isolate AFTER
    // the blocking call has returned — no emission can occur past this point.
    RacNative.bindings.rac_vlm_proto_quiesce?.call();
    callback?.close();
    calloc.free(requestPtr);
  }
}
