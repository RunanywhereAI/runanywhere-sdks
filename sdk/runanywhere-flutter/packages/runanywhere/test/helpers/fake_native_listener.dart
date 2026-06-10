// SPDX-License-Identifier: Apache-2.0
//
// Test-only helper that mirrors the listener-backed `StreamController<T>`
// pattern used by every Flutter streaming bridge (STT `transcribeStream`,
// TTS `synthesizeStreamLifecycleProto`, VLM `processImageStreamProto`).
//
// Production code wires up a single-subscription `StreamController<T>`,
// installs a `NativeCallable.listener` callback that pushes decoded protos
// into `controller.add(event)`, and tears the callback down in
// `controller.onCancel`. The unit-test harness can't actually invoke the
// native FFI, but it can exercise the *exact same* subscription contract
// by replacing the listener with a `dispatch(event)` call from the test.
//
// Keep this file tiny: it only models the stream-control pattern, not any
// ABI specifics.

import 'dart:async';

/// Test double for the `NativeCallable.listener` + `StreamController<T>`
/// pattern shared by `transcribeStream`, `synthesizeStream`, and
/// `processImageStream`.
class FakeNativeListenerStream<T> {
  FakeNativeListenerStream({
    bool autoCloseOnFinal = false,
    bool Function(T event)? isFinal,
  })  : _autoCloseOnFinal = autoCloseOnFinal,
        _isFinal = isFinal {
    _controller = StreamController<T>(
      onListen: () {
        _onListenInvocations++;
      },
      onCancel: () {
        _onCancelInvocations++;
        _cancelCleanup?.call();
      },
    );
  }

  late final StreamController<T> _controller;
  final bool _autoCloseOnFinal;
  final bool Function(T event)? _isFinal;

  int _onListenInvocations = 0;
  int _onCancelInvocations = 0;
  void Function()? _cancelCleanup;

  /// Stream visible to consumers — always single-subscription, mirroring
  /// the production bridges.
  Stream<T> get stream => _controller.stream;

  /// True when at least one consumer has subscribed.
  bool get listened => _onListenInvocations > 0;

  /// True when `onCancel` fired (i.e. the consumer cancelled or the stream
  /// closed). Mirrors the bridge cleanup hook that closes the
  /// `NativeCallable`.
  bool get cancelled => _onCancelInvocations > 0;

  /// True once the controller is closed.
  bool get isClosed => _controller.isClosed;

  /// Register a teardown callback that fires the first time `onCancel` runs.
  /// Production bridges use this to call `nativeCallable.close()` and
  /// best-effort `stopLifecycleProto()` / `cancel()` symmetrically; the
  /// test reuses it to assert cleanup ordering.
  set cancelCleanup(void Function()? callback) {
    _cancelCleanup = callback;
  }

  /// Mirror of the listener body in the production bridges. The real
  /// `NativeCallable.listener` invokes a closure that decodes proto bytes
  /// and forwards via `controller.add(...)`. Tests skip the proto decode
  /// and dispatch the already-typed event directly. Guards against a
  /// closed controller exactly like the bridge implementations.
  void dispatch(T event) {
    if (_controller.isClosed) return;
    _controller.add(event);
    if (_autoCloseOnFinal && (_isFinal?.call(event) ?? false)) {
      unawaited(_controller.close());
    }
  }

  /// Mirror of the controller close that runs after the FFI call returns
  /// and the terminal event has been seen.
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
