// SPDX-License-Identifier: Apache-2.0
//
// Shared helpers for generated-proto C ABI calls. This file owns only byte
// transport across FFI; modality behavior stays in commons.

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/errors.pbenum.dart' as pb_enum;
import 'package:runanywhere/native/types/basic_types.dart';

/// Maximum number of microtask yields the synchronous-FFI streaming wrappers
/// use to drain queued `NativeCallable.listener` callbacks before deciding
/// whether to force-close the controller (FLUTTER-IOS-001).
///
/// Rationale: `rac_*_stream*_proto` are synchronous FFI calls — they block the
/// main isolate, so every `NativeCallable.listener` invocation made during the
/// call queues onto the event loop instead of running. After the FFI returns,
/// we must yield a bounded number of times to let those queued callbacks
/// (including the terminal one) drain before closing the controller; otherwise
/// subscribers receive an empty stream even though native emitted events.
///
/// The bound is intentionally small (we exit early as soon as a terminal event
/// has been observed via `sawTerminalEvent`). 4 ticks is empirically enough
/// for the bursty TTS/STT/VLM/LLM callback patterns we ship today. Bumping
/// this only adds latency on misbehaving backends that never send a terminal
/// event — increase if you observe tail-event loss in tests.
const int kStreamDrainMaxMicrotasks = 4;

/// Helper that yields up to [kStreamDrainMaxMicrotasks] microtask ticks,
/// bailing out as soon as [terminalObserved] returns true. Centralizes the
/// FLUTTER-IOS-001 drain loop used by every synchronous-FFI streaming
/// wrapper (`DartBridgeTTS.synthesizeStreamLifecycleProto`,
/// `DartBridgeVLM.processImageStreamProto`, `RunAnywhereSTT.transcribeStream`,
/// `RunAnywhereLLM._generateStreamProto`).
Future<void> drainPendingStreamCallbacks(
  bool Function() terminalObserved,
) async {
  for (var i = 0; i < kStreamDrainMaxMicrotasks; i++) {
    if (terminalObserved()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

class DartBridgeProtoUtils {
  DartBridgeProtoUtils._();

  static T callRequest<T extends GeneratedMessage>({
    required GeneratedMessage request,
    required int Function(
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    ) invoke,
    required T Function(List<int>) decode,
    required String symbol,
  }) {
    final bytes = request.writeToBuffer();
    final requestPtr = copyBytes(bytes);
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = invoke(requestPtr, bytes.length, out);
      ensureSuccess(out, code, symbol);
      return decodeBuffer(out, decode);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(requestPtr);
      calloc.free(out);
    }
  }

  static T callRequestWithHandle<T extends GeneratedMessage>({
    required ffi.Pointer<ffi.Void> handle,
    required GeneratedMessage request,
    required int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<RacProtoBuffer>,
    ) invoke,
    required T Function(List<int>) decode,
    required String symbol,
  }) {
    return callRequest<T>(
      request: request,
      invoke: (bytes, size, out) => invoke(handle, bytes, size, out),
      decode: decode,
      symbol: symbol,
    );
  }

  static T callOut<T extends GeneratedMessage>({
    required int Function(ffi.Pointer<RacProtoBuffer>) invoke,
    required T Function(List<int>) decode,
    required String symbol,
  }) {
    final out = calloc<RacProtoBuffer>();
    final bindings = RacNative.bindings;

    try {
      bindings.rac_proto_buffer_init(out);
      final code = invoke(out);
      ensureSuccess(out, code, symbol);
      return decodeBuffer(out, decode);
    } finally {
      bindings.rac_proto_buffer_free(out);
      calloc.free(out);
    }
  }

  static T decodeBuffer<T extends GeneratedMessage>(
    ffi.Pointer<RacProtoBuffer> out,
    T Function(List<int>) decode,
  ) {
    if (out.ref.data == ffi.nullptr || out.ref.size == 0) {
      return decode(const <int>[]);
    }
    final bytes =
        out.ref.data.asTypedList(out.ref.size).toList(growable: false);
    return decode(bytes);
  }

  static void ensureSuccess(
    ffi.Pointer<RacProtoBuffer> out,
    int code,
    String symbol,
  ) {
    if (code == RacResultCode.success &&
        out.ref.status == RacResultCode.success) {
      return;
    }
    throw SDKException.make(
      code: pb_enum.ErrorCode.ERROR_CODE_PROCESSING_FAILED,
      message: '$symbol failed: ${protoBufferError(out, code)}',
      category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
    );
  }

  static String protoBufferError(ffi.Pointer<RacProtoBuffer> out, int code) {
    if (out.ref.errorMessage != ffi.nullptr) {
      return out.ref.errorMessage.toDartString();
    }
    return 'code=$code status=${out.ref.status}';
  }

  static ffi.Pointer<ffi.Uint8> copyBytes(List<int> bytes) {
    final ptr = calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    if (bytes.isNotEmpty) {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
    }
    return ptr;
  }
}
