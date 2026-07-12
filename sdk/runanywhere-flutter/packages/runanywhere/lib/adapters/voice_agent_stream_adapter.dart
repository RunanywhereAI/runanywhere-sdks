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
// `onCancel` to native callback deregistration.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
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
          controller.addError(
            StateError(
              'rac_voice_agent_set_proto_callback failed '
              '(Protobuf may not be linked)',
            ),
          );
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
  ReceivePort? _receivePort;

  bool attach(StreamController<VoiceEvent> controller) {
    // Add the controller BEFORE calling _install() so that a
    // synchronously-fired first event (legal per the commons contract; see
    // HandleStreamAdapter.swift:123-129) is not dropped
    // because _broadcast() snapshots an empty set.  Roll back on failure.
    _controllers.add(controller);
    if (!_isInstalled && !_install()) {
      _controllers.remove(controller);
      return false;
    }
    return true;
  }

  bool get _isInstalled => _receivePort != null;

  void detach(StreamController<VoiceEvent> controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) {
      _tearDown();
    }
  }

  bool _install() {
    final bindings = RacNative.bindings;
    if (bindings.ra_flutter_voice_agent_set_proto_callback_native_port ==
            null ||
        bindings.ra_flutter_voice_agent_unset_proto_callback_native_port ==
            null) {
      return false;
    }
    return _installNativePort();
  }

  bool _installNativePort() {
    final bindings = RacNative.bindings;
    final setFn =
        bindings.ra_flutter_voice_agent_set_proto_callback_native_port;
    if (setFn == null) return false;

    final port = ReceivePort();
    port.listen((Object? message) {
      if (message is! Uint8List) return;
      try {
        _broadcast(VoiceEvent.fromBuffer(message));
      } catch (e, st) {
        _broadcastError(e, st);
      }
    });

    final rc = setFn(
      _handle,
      port.sendPort.nativePort,
      ffi.NativeApi.postCObject,
    );
    if (rc != 0) {
      port.close();
      return false;
    }

    _receivePort = port;
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
    if (_receivePort == null) return;
    final unsetFn = RacNative
        .bindings
        .ra_flutter_voice_agent_unset_proto_callback_native_port;
    if (unsetFn == null) {
      throw UnsupportedError(
        'ra_flutter_voice_agent_unset_proto_callback_native_port is unavailable',
      );
    }
    unsetFn(_handle);
    _receivePort?.close();
    _receivePort = null;
    _onTornDown();
  }
}
