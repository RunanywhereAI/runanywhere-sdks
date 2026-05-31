// SPDX-License-Identifier: Apache-2.0
//
// voice_agent_stream_adapter.dart
//
// Wraps `rac_voice_agent_set_proto_callback` (declared in
// `rac_voice_event_abi.h`) as a Dart `Stream<VoiceEvent>`.
// VoiceEvent is the protoc_plugin-generated type from
// `idl/voice_events.proto`.
//
// Public API:
//     final stream = VoiceAgentStreamAdapter(handle).stream();
//     await for (final event in stream) handleEvent(event);
//
// Cancellation: `StreamSubscription.cancel()` propagates through
// `onCancel` to `Pointer.fromFunction` deregistration.

import 'dart:async';
import 'dart:ffi' as ffi;
// NativeCallable moved from dart:isolate to dart:ffi in Dart 3.1+.
import 'dart:ffi' show NativeCallable;
import 'dart:typed_data' show Uint8List;

// Wire-via-protoc generated VoiceEvent — see codegen output at
// sdk/runanywhere-flutter/packages/runanywhere/lib/generated/voice_events.pb.dart.
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;

/// Streams [VoiceEvent]s from a C++ voice agent handle.
///
/// Multiple concurrent [stream] subscribers for the same native handle
/// share one C callback registration and receive the same decoded events.
class VoiceAgentStreamAdapter {
  VoiceAgentStreamAdapter(this._handle);

  final ffi.Pointer<ffi.Void> _handle;

  /// Open a new event subscription. The returned stream emits one
  /// [VoiceEvent] per agent event until cancelled or the agent ends.
  /// Each call produces a fresh single-subscription stream; multiple
  /// streams attached to the same native handle fan out from one C
  /// callback registration via [_VoiceFanOutRegistry].
  Stream<VoiceEvent> stream() {
    final fanOut = _VoiceFanOutRegistry.fanOutFor(_handle);
    late StreamController<VoiceEvent> controller;

    controller = StreamController<VoiceEvent>(
      onListen: () {
        final attached = fanOut.attach(controller);
        if (!attached) {
          controller.addError(StateError(
            'rac_voice_agent_set_proto_callback failed '
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

class _VoiceFanOutRegistry {
  static final Map<int, _VoiceHandleFanOut> _fanOuts = {};

  static _VoiceHandleFanOut fanOutFor(ffi.Pointer<ffi.Void> handle) {
    return _fanOuts.putIfAbsent(
      handle.address,
      () => _VoiceHandleFanOut(handle, () => _fanOuts.remove(handle.address)),
    );
  }
}

class _VoiceHandleFanOut {
  _VoiceHandleFanOut(this._handle, this._onTornDown);

  final ffi.Pointer<ffi.Void> _handle;
  final void Function() _onTornDown;
  final Set<StreamController<VoiceEvent>> _controllers = {};
  NativeCallable<_CCallbackNative>? _nativeCb;

  bool attach(StreamController<VoiceEvent> controller) {
    // Add the controller BEFORE calling _install() so that a
    // synchronously-fired first event (legal per the commons contract; see
    // HandleStreamAdapter.swift:123-129) is not dropped
    // because _broadcast() snapshots an empty set.  Roll back on failure.
    _controllers.add(controller);
    if (_nativeCb == null && !_install()) {
      _controllers.remove(controller);
      return false;
    }
    return true;
  }

  void detach(StreamController<VoiceEvent> controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) {
      _tearDown();
    }
  }

  bool _install() {
    // NativeCallable.listener dispatches the closure body
    // asynchronously on the Dart isolate event loop — the C trampoline returns
    // immediately and the commons dispatcher is free to overwrite its
    // thread_local scratch buffer before this closure runs. The copy on line
    // below therefore races the scratch buffer on a busy voice pipeline.
    //
    // The correct fix requires commons to expose either a poll-based owned-copy
    // queue (`rac_voice_agent_proto_poll`, analogous to `rac_sdk_event_poll`)
    // or an ABI that heap-allocates the proto bytes and transfers ownership
    // to the caller (rac_proto_buffer_t pattern). Until that commons ABI
    // exists, this listener-based path is the only available mechanism.
    final cb = NativeCallable<_CCallbackNative>.listener((
      ffi.Pointer<ffi.Uint8> bytesPtr,
      int bytesLen,
      ffi.Pointer<ffi.Void> _,
    ) {
      if (bytesLen <= 0 || bytesPtr == ffi.nullptr) return;
      final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
      try {
        _broadcast(VoiceEvent.fromBuffer(copy));
      } catch (e, st) {
        _broadcastError(e, st);
      }
    });

    final rc = RacNative.bindings.rac_voice_agent_set_proto_callback(
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

  void _broadcast(VoiceEvent event) {
    final snapshot = List<StreamController<VoiceEvent>>.from(_controllers);
    for (final controller in snapshot) {
      if (!controller.isClosed) {
        controller.add(event);
      }
    }
  }

  void _broadcastError(Object error, StackTrace stackTrace) {
    final snapshot = List<StreamController<VoiceEvent>>.from(_controllers);
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
    // Teardown ordering: (1) unregister the C callback so no NEW
    // dispatches will fire, (2) `rac_voice_agent_proto_quiesce()` spins
    // until every in-flight dispatch returns, (3) close the NativeCallable
    // whose `user_data` was the dispatcher's argument. Skipping the quiesce
    // step lets the dispatcher invoke the trampoline after the
    // NativeCallable is freed (UAF). Mirrors Swift's
    // `HandleStreamAdapter.tearDown()` lock-release-before-unregister
    // pattern in
    // `sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/HandleStreamAdapter.swift`.
    RacNative.bindings.rac_voice_agent_set_proto_callback(
      _handle,
      ffi.nullptr,
      ffi.nullptr,
    );
    RacNative.bindings.rac_voice_agent_proto_quiesce?.call();
    cb.close();
    _nativeCb = null;
    _onTornDown();
  }
}

/// `void (*)(uint8_t*, size_t, void*)` matching
/// `rac_voice_agent_proto_event_callback_fn`.
typedef _CCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);
