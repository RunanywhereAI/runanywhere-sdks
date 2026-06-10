/// DartBridge+VLM
///
/// Thin generated-proto VLM bridge. Commons lifecycle owns the loaded VLM
/// service; Dart passes app-owned image request bytes and receives generated
/// VLM result/stream protos.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
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
/// The underlying C type returns `rac_bool_t`, but the callback fires
/// synchronously on the Dart isolate that invoked `rac_vlm_stream_proto`, so
/// no value is returned — matching the canonical Flutter stream bridge (LLM,
/// voice-agent).
typedef _RacVlmStreamEventProtoCallbackNative = ffi.Void Function(
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
    ffi.NativeCallable<_RacVlmStreamEventProtoCallbackNative>? callback;

    var sawTerminalEvent = false;

    Future<void> run() async {
      final bytes = request.writeToBuffer();
      final requestPtr = DartBridgeProtoUtils.copyBytes(bytes);

      try {
        // Mirrors dart_bridge_llm.dart: use `isolateLocal`
        // (not `.listener`) so the callback fires SYNCHRONOUSLY on the Dart
        // isolate that invokes `rac_vlm_stream_proto`. Commons serializes each
        // VLMStreamEvent into a thread-local scratch vector and calls the
        // callback with `scratch.data()` inline; under `.listener` the callback
        // is queued onto the event loop and runs after a later token has
        // already resized/overwritten that scratch slot, so the captured
        // pointer decodes partially-overwritten bytes (use-after-free). The
        // engine vtable iterates tokens on this same calling thread, so the
        // callback always fires on the isolate that created it — the exact
        // precondition `isolateLocal` requires.
        callback = ffi.NativeCallable<
            _RacVlmStreamEventProtoCallbackNative>.isolateLocal(
          (
            ffi.Pointer<ffi.Uint8> bytesPtr,
            int bytesLen,
            ffi.Pointer<ffi.Void> _,
          ) {
            if (controller.isClosed ||
                bytesPtr == ffi.nullptr ||
                bytesLen <= 0) {
              return;
            }
            try {
              final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
              final event = VLMStreamEvent.fromBuffer(copy);
              sawTerminalEvent = sawTerminalEvent || event.isFinal;
              controller.add(event);
              if (event.isFinal) {
                unawaited(controller.close());
              }
            } catch (e, st) {
              controller.addError(e, st);
              unawaited(controller.close());
            }
          },
        );

        final fn = _lookupStreamProto();
        final code = fn(
          requestPtr,
          bytes.length,
          callback!.nativeFunction,
          ffi.nullptr,
        );
        if (code != RacResultCode.success && !controller.isClosed) {
          controller.addError(StateError(
            'rac_vlm_stream_proto failed: ${RacResultCode.getMessage(code)}',
          ));
          await controller.close();
        } else if (!sawTerminalEvent && !controller.isClosed) {
          await controller.close();
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      } finally {
        calloc.free(requestPtr);
        // Teardown: with `isolateLocal` every event
        // has already drained by the time `fn` returns, but
        // `rac_vlm_proto_quiesce()` is still invoked as a defensive barrier in
        // case a future commons revision posts a late callback from a worker
        // thread (see `rac/features/vlm/rac_vlm_service.h`) — closing the
        // NativeCallable while that worker is mid-dispatch would be a UAF.
        RacNative.bindings.rac_vlm_proto_quiesce?.call();
        callback?.close();
        callback = null;
      }
    }

    controller.onListen = () {
      unawaited(run());
    };
    controller.onCancel = () {
      cancel();
      RacNative.bindings.rac_vlm_proto_quiesce?.call();
      callback?.close();
      callback = null;
    };

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
