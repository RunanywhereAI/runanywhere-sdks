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
// NativeCallable moved from dart:isolate to dart:ffi in Dart 3.1+.
import 'dart:ffi' show NativeCallable;
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
  NativeCallable<_CCallbackNative>? _nativeCb;
  ReceivePort? _receivePort;
  bool _usingNativePort = false;

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

  bool get _isInstalled => _usingNativePort || _nativeCb != null;

  void detach(StreamController<VoiceEvent> controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) {
      _tearDown();
    }
  }

  bool _install() {
    final bindings = RacNative.bindings;
    if (bindings.ra_flutter_voice_agent_set_proto_callback_native_port !=
            null &&
        bindings.ra_flutter_voice_agent_unset_proto_callback_native_port !=
            null) {
      return _installNativePort();
    }
    return _installNativeCallable();
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
    _usingNativePort = true;
    return true;
  }

  bool _installNativeCallable() {
    // Fallback for older or unsupported binaries that do not export the Flutter
    // native-port helper. `NativeCallable.listener` is cross-thread safe, but
    // it runs later on the Dart event loop. Commons only keeps `event_bytes`
    // alive for the callback invocation and reuses a thread-local scratch
    // buffer immediately after it returns, so a listener can read corrupted
    // bytes. Use `isolateLocal` here so bytes are copied before returning to
    // commons. This fallback remains valid only for callbacks invoked on the
    // registering Dart isolate.
    final cb = NativeCallable<_CCallbackNative>.isolateLocal((
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
    if (_usingNativePort) {
      final bindings = RacNative.bindings;
      final unsetFn =
          bindings.ra_flutter_voice_agent_unset_proto_callback_native_port;
      if (unsetFn != null) {
        unsetFn(_handle);
      } else {
        bindings.rac_voice_agent_set_proto_callback(
          _handle,
          ffi.nullptr,
          ffi.nullptr,
        );
        bindings.rac_voice_agent_proto_quiesce?.call();
      }
      _receivePort?.close();
      _receivePort = null;
      _usingNativePort = false;
      _onTornDown();
      return;
    }

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
typedef _CCallbackNative =
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Size, ffi.Pointer<ffi.Void>);
