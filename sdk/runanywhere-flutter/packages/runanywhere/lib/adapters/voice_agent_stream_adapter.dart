// SPDX-License-Identifier: Apache-2.0
//
// voice_agent_stream_adapter.dart
//
// GAP 09 Phase 18 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
//
// Wraps `rac_voice_agent_set_proto_callback` (declared in
// `rac_voice_event_abi.h`, GAP 09 Phase 15) as a Dart `Stream<VoiceEvent>`.
// VoiceEvent is the protoc_plugin-generated type from
// `idl/voice_events.proto` (GAP 01).
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

// Wire-via-protoc generated VoiceEvent — see GAP 01 codegen output at
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

  /// Open a new event subscription. The returned broadcast stream emits
  /// one [VoiceEvent] per agent event until cancelled or the agent ends.
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
    if (_nativeCb == null && !_install()) {
      return false;
    }
    _controllers.add(controller);
    return true;
  }

  void detach(StreamController<VoiceEvent> controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) {
      _tearDown();
    }
  }

  bool _install() {
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
    RacNative.bindings.rac_voice_agent_set_proto_callback(
      _handle, ffi.nullptr, ffi.nullptr,
    );
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
