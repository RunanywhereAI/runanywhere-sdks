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
/// One adapter holds one C-side callback registration per `stream()`
/// call. Multiple concurrent subscribers should each create their own
/// adapter — the C ABI exposes exactly one proto-callback slot per
/// handle.
class LLMStreamAdapter {
  LLMStreamAdapter(this._handle);

  final ffi.Pointer<ffi.Void> _handle;

  /// Open a new event subscription. The returned stream emits one
  /// [LLMStreamEvent] per generated token plus a terminal event
  /// (`isFinal == true`).
  Stream<LLMStreamEvent> stream() {
    late StreamController<LLMStreamEvent> controller;
    NativeCallable<RacLlmStreamProtoCallbackNative>? nativeCb;

    void onListen() {
      nativeCb = NativeCallable<RacLlmStreamProtoCallbackNative>.listener((
        ffi.Pointer<ffi.Uint8> bytesPtr,
        int bytesLen,
        ffi.Pointer<ffi.Void> _,
      ) {
        if (bytesLen <= 0 || bytesPtr == ffi.nullptr) return;
        final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
        try {
          final event = LLMStreamEvent.fromBuffer(copy);
          controller.add(event);
          if (event.isFinal && !controller.isClosed) {
            // Auto-close on terminal event so collectors exit their
            // `await for` without an explicit cancel.
            unawaited(controller.close());
          }
        } catch (e, st) {
          controller.addError(e, st);
        }
      });

      final rc = RacNative.bindings.rac_llm_set_stream_proto_callback(
        _handle,
        nativeCb!.nativeFunction,
        ffi.nullptr,
      );
      if (rc != 0) {
        nativeCb!.close();
        nativeCb = null;
        controller.addError(StateError(
          'rac_llm_set_stream_proto_callback failed: $rc '
          '(Protobuf may not be linked)',
        ));
        unawaited(controller.close());
      }
    }

    void onCancel() {
      RacNative.bindings.rac_llm_unset_stream_proto_callback(_handle);
      nativeCb?.close();
      nativeCb = null;
    }

    controller = StreamController<LLMStreamEvent>(
      onListen: onListen,
      onCancel: onCancel,
    );
    return controller.stream;
  }
}
