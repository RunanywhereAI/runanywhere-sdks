// SPDX-License-Identifier: Apache-2.0
//
// Shared helpers for generated-proto C ABI calls. This file owns only byte
// transport across FFI; modality behavior stays in commons.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:protobuf/protobuf.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/native/ffi_types.dart';

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
    throw StateError('$symbol failed: ${protoBufferError(out, code)}');
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
