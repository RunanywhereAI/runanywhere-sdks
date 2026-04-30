// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_diffusion.dart — FFI helpers for the `rac_diffusion_*`
// C ABI. Public capability code calls into this bridge so
// `lib/public/capabilities/runanywhere_diffusion.dart` stays free of
// `dart:ffi` imports (canonical §15 type-discipline).

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Result of a diffusion FFI call: payload bytes (proto-encoded) +
/// return code (0 ok, non-zero RAC error).
class DiffusionFfiResult {
  DiffusionFfiResult({this.payload, required this.resultCode});
  final Uint8List? payload;
  final int resultCode;
  bool get success => resultCode == RAC_SUCCESS;
}

/// FFI bridge to the `rac_diffusion_*` C ABI. Owns the diffusion
/// component handle so the public capability layer never has to
/// touch `dart:ffi`.
class DartBridgeDiffusion {
  DartBridgeDiffusion._();

  static RacHandle? _handle;

  /// Whether the bridge currently holds a created component handle.
  static bool get hasHandle => _handle != null;

  /// True when a diffusion model is currently loaded.
  static bool isLoaded() {
    final h = _handle;
    if (h == null) return false;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(RacHandle),
        int Function(RacHandle)>('rac_diffusion_component_is_loaded');
    return fn(h) == RAC_TRUE;
  }

  /// Lazily create the diffusion component handle. Returns the
  /// resulting RAC code; 0 on success.
  static int ensureHandle() {
    if (_handle != null) return RAC_SUCCESS;
    final lib = PlatformLoader.loadCommons();
    final create = lib.lookupFunction<Int32 Function(Pointer<RacHandle>),
        int Function(Pointer<RacHandle>)>('rac_diffusion_component_create');
    final outPtr = calloc<RacHandle>();
    try {
      final rc = create(outPtr);
      if (rc != RAC_SUCCESS) return rc;
      _handle = outPtr.value;
      return RAC_SUCCESS;
    } finally {
      calloc.free(outPtr);
    }
  }

  /// Load a diffusion model by ID.
  static int loadModel(String modelId) {
    final h = _handle;
    if (h == null) return RacResultCode.errorInvalidParameter;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(RacHandle, Pointer<Utf8>),
        int Function(RacHandle, Pointer<Utf8>)>(
      'rac_diffusion_component_load_model',
    );
    final idPtr = modelId.toNativeUtf8();
    try {
      return fn(h, idPtr);
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Unload the currently-loaded diffusion model.
  static int unload() {
    final h = _handle;
    if (h == null) return RAC_SUCCESS;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(RacHandle),
        int Function(RacHandle)>('rac_diffusion_component_unload');
    return fn(h);
  }

  /// Generate an image. Returns proto-encoded `DiffusionResult` bytes.
  static DiffusionFfiResult generate(
    String prompt,
    Uint8List optionsBytes,
  ) {
    final h = _handle;
    if (h == null) {
      return DiffusionFfiResult(resultCode: RacResultCode.errorInvalidParameter);
    }
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(
          RacHandle,
          Pointer<Utf8>,
          Pointer<Uint8>,
          IntPtr,
          Pointer<Pointer<Uint8>>,
          Pointer<IntPtr>,
        ),
        int Function(
          RacHandle,
          Pointer<Utf8>,
          Pointer<Uint8>,
          int,
          Pointer<Pointer<Uint8>>,
          Pointer<IntPtr>,
        )>('rac_diffusion_component_generate');

    final promptPtr = prompt.toNativeUtf8();
    final optsPtr = optionsBytes.isEmpty
        ? nullptr
        : (calloc<Uint8>(optionsBytes.length)
          ..asTypedList(optionsBytes.length).setAll(0, optionsBytes));
    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outLenPtr = calloc<IntPtr>();
    try {
      final rc = fn(
        h,
        promptPtr,
        optsPtr,
        optionsBytes.length,
        outBytesPtr,
        outLenPtr,
      );
      if (rc != RAC_SUCCESS) {
        return DiffusionFfiResult(resultCode: rc);
      }
      final len = outLenPtr.value;
      final bytes = Uint8List.fromList(outBytesPtr.value.asTypedList(len));
      return DiffusionFfiResult(payload: bytes, resultCode: rc);
    } finally {
      calloc.free(promptPtr);
      if (optsPtr != nullptr) calloc.free(optsPtr);
      calloc.free(outBytesPtr);
      calloc.free(outLenPtr);
    }
  }

  /// Cancel any in-flight generation.
  static int cancel() {
    final h = _handle;
    if (h == null) return RAC_SUCCESS;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(RacHandle),
        int Function(RacHandle)>('rac_diffusion_component_cancel');
    return fn(h);
  }

  /// Backend capability discovery. Returns proto-encoded bytes.
  static DiffusionFfiResult capabilities() {
    final h = _handle;
    if (h == null) {
      return DiffusionFfiResult(resultCode: RacResultCode.errorInvalidParameter);
    }
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(
          RacHandle,
          Pointer<Pointer<Uint8>>,
          Pointer<IntPtr>,
        ),
        int Function(
          RacHandle,
          Pointer<Pointer<Uint8>>,
          Pointer<IntPtr>,
        )>('rac_diffusion_component_get_capabilities');

    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outLenPtr = calloc<IntPtr>();
    try {
      final rc = fn(h, outBytesPtr, outLenPtr);
      if (rc != RAC_SUCCESS) {
        return DiffusionFfiResult(resultCode: rc);
      }
      final len = outLenPtr.value;
      final bytes = Uint8List.fromList(outBytesPtr.value.asTypedList(len));
      return DiffusionFfiResult(payload: bytes, resultCode: rc);
    } finally {
      calloc.free(outBytesPtr);
      calloc.free(outLenPtr);
    }
  }
}
