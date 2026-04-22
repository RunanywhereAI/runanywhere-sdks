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

import 'package:ffi/ffi.dart' show calloc;
// Wire-via-protoc generated VoiceEvent — see GAP 01 codegen output at
// sdk/runanywhere-flutter/packages/runanywhere/lib/generated/voice_events.pb.dart.
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;

/// Streams [VoiceEvent]s from a C++ voice agent handle.
///
/// One adapter holds one C-side callback registration. Multiple
/// concurrent subscribers should each create their own adapter — the C++
/// dispatcher fans out one event per subscription.
class VoiceAgentStreamAdapter {
  VoiceAgentStreamAdapter(this._handle);

  final ffi.Pointer<ffi.Void> _handle;

  /// Open a new event subscription. The returned broadcast stream emits
  /// one [VoiceEvent] per agent event until cancelled or the agent ends.
  Stream<VoiceEvent> stream() {
    late StreamController<VoiceEvent> controller;
    NativeCallable<_CCallbackNative>? nativeCb;

    void onListen() {
      // Build the C-callable trampoline: receives raw bytes, decodes via
      // protobuf-dart, pushes onto the controller. NativeCallable keeps
      // the Dart side reachable from the C side as long as we hold it.
      nativeCb = NativeCallable<_CCallbackNative>.listener((
        ffi.Pointer<ffi.Uint8> bytesPtr,
        int bytesLen,
        ffi.Pointer<ffi.Void> _,
      ) {
        if (bytesLen <= 0 || bytesPtr == ffi.nullptr) return;
        // Copy off the C buffer (per ABI: only valid for callback duration).
        final copy = Uint8List.fromList(bytesPtr.asTypedList(bytesLen));
        try {
          controller.add(VoiceEvent.fromBuffer(copy));
        } catch (e, st) {
          controller.addError(e, st);
        }
      });

      final rc = RacNative.bindings.rac_voice_agent_set_proto_callback(
        _handle,
        nativeCb!.nativeFunction,
        ffi.nullptr,
      );
      if (rc != 0) {
        nativeCb!.close();
        nativeCb = null;
        controller.addError(StateError(
          'rac_voice_agent_set_proto_callback failed: $rc '
          '(Protobuf may not be linked)',
        ));
        controller.close();
      }
    }

    void onCancel() {
      RacNative.bindings.rac_voice_agent_set_proto_callback(
        _handle, ffi.nullptr, ffi.nullptr,
      );
      nativeCb?.close();
      nativeCb = null;
    }

    controller = StreamController<VoiceEvent>(
      onListen: onListen,
      onCancel: onCancel,
    );
    return controller.stream;
  }
}

/// `void (*)(uint8_t*, size_t, void*)` matching
/// `rac_voice_agent_proto_event_callback_fn`.
typedef _CCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8>,
  ffi.Size,
  ffi.Pointer<ffi.Void>,
);

// Suppress unused-import lint while bindings package shape stabilizes.
// ignore: unused_element
void _silenceUnusedCalloc() => calloc;
