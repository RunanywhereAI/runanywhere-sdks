// SPDX-License-Identifier: Apache-2.0
//
// llm_stream_adapter.dart
//
// v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
//
// Wraps `rac_llm_set_stream_proto_callback` (declared in
// `rac_llm_stream.h`) as a Dart `Stream<LLMStreamEvent>`.
// LLMStreamEvent is the protoc_plugin-generated type from
// `idl/llm_service.proto`.
//
// This is the unified LLM streaming path — the hand-rolled
// StreamController + DartBridge.llm.generateStream shim in
// `runanywhere_llm.dart` was migrated to delegate through this adapter
// in the same change, so there is ONE C-callback registration path per
// handle (no parallel hand-rolled streaming shim).
//
// Public API:
//     final stream = LLMStreamAdapter(handle).stream();
//     await for (final event in stream) {
//       if (event.isFinal) break;
//       // use event.token, event.tokenId, event.logprob, etc.
//     }
//
// Cancellation: `StreamSubscription.cancel()` propagates through
// `onCancel` to the callback deregistration.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ffi' show NativeCallable;
import 'dart:typed_data' show Uint8List;

import 'package:runanywhere/core/native/rac_native.dart'
    show RacNative, RacLlmStreamProtoCallbackNative;
import 'package:runanywhere/generated/llm_service.pb.dart' show LLMStreamEvent;

/// Streams [LLMStreamEvent]s from a C++ LLM component handle.
///
/// Multiple concurrent [stream] subscribers for the same native handle
/// share one C callback registration and receive the same decoded events.
class LLMStreamAdapter {
  LLMStreamAdapter(this._handle);

  final ffi.Pointer<ffi.Void> _handle;

  /// Open a new event subscription. The returned stream emits one
  /// [LLMStreamEvent] per generated token plus a terminal event
  /// (`isFinal == true`).
  Stream<LLMStreamEvent> stream() {
    final fanOut = _LLMFanOutRegistry.fanOutFor(_handle);
    late StreamController<LLMStreamEvent> controller;

    controller = StreamController<LLMStreamEvent>(
      onListen: () {
        final attached = fanOut.attach(controller);
        if (!attached) {
          controller.addError(StateError(
            'rac_llm_set_stream_proto_callback failed '
            '(Protobuf may not be linked)',
          ));
          unawaited(controller.close());
        }
      },
      onCancel: () => fanOut.detach(controller),
    );
    return controller.stream;
  }
}

class _LLMFanOutRegistry {
  static final Map<int, _LLMHandleFanOut> _fanOuts = {};

  static _LLMHandleFanOut fanOutFor(ffi.Pointer<ffi.Void> handle) {
    return _fanOuts.putIfAbsent(
      handle.address,
      () => _LLMHandleFanOut(handle, () => _fanOuts.remove(handle.address)),
    );
  }
}

class _LLMHandleFanOut {
  _LLMHandleFanOut(this._handle, this._onTornDown);

  final ffi.Pointer<ffi.Void> _handle;
  final void Function() _onTornDown;
  final Set<StreamController<LLMStreamEvent>> _controllers = {};
  NativeCallable<RacLlmStreamProtoCallbackNative>? _nativeCb;

  bool attach(StreamController<LLMStreamEvent> controller) {
    if (_nativeCb == null && !_install()) {
      return false;
    }
    _controllers.add(controller);
    return true;
  }

  void detach(StreamController<LLMStreamEvent> controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) {
      _tearDown();
    }
  }

  bool _install() {
    final cb = NativeCallable<RacLlmStreamProtoCallbackNative>.listener((
      ffi.Pointer<ffi.Uint8> bytesPtr,
      int bytesLen,
      ffi.Pointer<ffi.Void> _,
    ) {
      if (bytesLen <= 0 || bytesPtr == ffi.nullptr) return;
      final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
      try {
        _broadcast(LLMStreamEvent.fromBuffer(copy));
      } catch (e, st) {
        _broadcastError(e, st);
      }
    });

    final rc = RacNative.bindings.rac_llm_set_stream_proto_callback(
      _handle,
      cb.nativeFunction,
      ffi.nullptr,
    );
    if (rc != 0) {
      cb.close();
      return false;
    }

    _nativeCb = cb;
    return true;
  }

  void _broadcast(LLMStreamEvent event) {
    final snapshot = List<StreamController<LLMStreamEvent>>.from(_controllers);
    for (final controller in snapshot) {
      if (!controller.isClosed) {
        controller.add(event);
        if (event.isFinal) {
          unawaited(controller.close());
        }
      }
    }
    if (event.isFinal) {
      _controllers.clear();
      _tearDown();
    }
  }

  void _broadcastError(Object error, StackTrace stackTrace) {
    final snapshot = List<StreamController<LLMStreamEvent>>.from(_controllers);
    _controllers.clear();
    for (final controller in snapshot) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        unawaited(controller.close());
      }
    }
    _tearDown();
  }

  void _tearDown() {
    final cb = _nativeCb;
    if (cb == null) return;
    RacNative.bindings.rac_llm_unset_stream_proto_callback(_handle);
    cb.close();
    _nativeCb = null;
    _onTornDown();
  }
}
