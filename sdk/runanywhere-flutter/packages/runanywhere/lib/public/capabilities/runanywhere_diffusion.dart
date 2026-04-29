// SPDX-License-Identifier: Apache-2.0
//
// Wave 2: Diffusion namespace extension. Mirrors Swift's
// `RunAnywhere+Diffusion.swift`. Each public method now calls the
// `rac_diffusion_*` C ABI directly. If commons returns
// `RAC_ERROR_FEATURE_NOT_AVAILABLE` (Apple-only engine), the
// SDKException naturally propagates — we no longer pre-empt the call.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionResult,
        DiffusionCapabilities,
        DiffusionProgress;
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Diffusion (image generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.diffusion`. Mirrors Swift
/// `RunAnywhere.Diffusion`. Wired to the `rac_diffusion_*` C ABI; if
/// the underlying engine isn't available the C layer returns
/// `RAC_ERROR_FEATURE_NOT_AVAILABLE` and we surface that as
/// `SDKException.featureNotAvailable`.
class RunAnywhereDiffusion {
  RunAnywhereDiffusion._();
  static final RunAnywhereDiffusion _instance = RunAnywhereDiffusion._();
  static RunAnywhereDiffusion get shared => _instance;

  RacHandle? _handle;
  String? _currentModelId;

  // -- state ---------------------------------------------------------------

  /// True when a diffusion model is currently loaded.
  bool get isLoaded {
    final h = _handle;
    if (h == null) return false;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(RacHandle),
        int Function(RacHandle)>('rac_diffusion_component_is_loaded');
    return fn(h) == RAC_TRUE;
  }

  /// Currently-loaded diffusion model id, or null.
  String? get currentModelId => _currentModelId;

  // -- internal helpers ----------------------------------------------------

  static Never _throwForCode(String op, int code) {
    if (code == RacResultCode.errorFeatureNotAvailable ||
        code == RacResultCode.errorNotImplemented ||
        code == RacResultCode.errorBackendNotFound ||
        code == RacResultCode.errorBackendUnavailable) {
      throw SDKException.featureNotAvailable('Diffusion: $op');
    }
    throw SDKException.generationFailed(
      '$op failed: ${RacResultCode.getMessage(code)}',
    );
  }

  RacHandle _ensureHandle() {
    var h = _handle;
    if (h != null) return h;
    final lib = PlatformLoader.loadCommons();
    final create = lib.lookupFunction<Int32 Function(Pointer<RacHandle>),
        int Function(Pointer<RacHandle>)>('rac_diffusion_component_create');
    final outPtr = calloc<RacHandle>();
    try {
      final rc = create(outPtr);
      if (rc != RAC_SUCCESS) {
        _throwForCode('rac_diffusion_component_create', rc);
      }
      h = outPtr.value;
      _handle = h;
      return h;
    } finally {
      calloc.free(outPtr);
    }
  }

  /// Load a diffusion model by ID.
  Future<void> load(String modelId, [DiffusionConfiguration? config]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final handle = _ensureHandle();
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<
        Int32 Function(RacHandle, Pointer<Utf8>),
        int Function(RacHandle, Pointer<Utf8>)>(
      'rac_diffusion_component_load_model',
    );
    final idPtr = modelId.toNativeUtf8();
    try {
      final rc = fn(handle, idPtr);
      if (rc != RAC_SUCCESS) {
        _throwForCode('rac_diffusion_component_load_model', rc);
      }
      _currentModelId = modelId;
    } finally {
      calloc.free(idPtr);
    }
  }

  /// Unload the currently-loaded diffusion model.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final h = _handle;
    if (h == null) return;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(RacHandle),
        int Function(RacHandle)>('rac_diffusion_component_unload');
    final rc = fn(h);
    if (rc != RAC_SUCCESS) {
      _throwForCode('rac_diffusion_component_unload', rc);
    }
    _currentModelId = null;
  }

  /// Generate an image from a text prompt.
  Future<DiffusionResult> generate(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final handle = _ensureHandle();
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
    final optsBytes = options?.writeToBuffer() ?? Uint8List(0);
    final optsPtr = optsBytes.isEmpty
        ? nullptr
        : (calloc<Uint8>(optsBytes.length)
          ..asTypedList(optsBytes.length).setAll(0, optsBytes));
    final outBytesPtr = calloc<Pointer<Uint8>>();
    final outLenPtr = calloc<IntPtr>();
    try {
      final rc = fn(
        handle,
        promptPtr,
        optsPtr,
        optsBytes.length,
        outBytesPtr,
        outLenPtr,
      );
      if (rc != RAC_SUCCESS) {
        _throwForCode('rac_diffusion_component_generate', rc);
      }
      final len = outLenPtr.value;
      final bytes = outBytesPtr.value.asTypedList(len);
      return DiffusionResult.fromBuffer(bytes);
    } finally {
      calloc.free(promptPtr);
      if (optsPtr != nullptr) calloc.free(optsPtr);
      calloc.free(outBytesPtr);
      calloc.free(outLenPtr);
    }
  }

  /// Stream generation progress.
  ///
  /// Subscribes to the `rac_diffusion_component_set_progress_callback`
  /// proto-byte stream. If the engine has no streaming support the C
  /// ABI returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` which propagates.
  Stream<DiffusionProgress> generateStream(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) async* {
    // Streaming variant is implemented in commons via a proto-byte
    // callback (mirrors the LLM/voice agent pattern). The callback wiring
    // is non-trivial; we emit the final result as a single progress event
    // until the streaming bridge lands. The blocking call still executes
    // through the C ABI so the SDKException semantics are preserved.
    final result = await generate(prompt, options);
    yield DiffusionProgress(
      progressPercent: 100.0,
      stage: 'completed',
      intermediateImageData: result.imageData,
    );
  }

  /// Cancel any in-flight generation.
  Future<void> cancel() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final h = _handle;
    if (h == null) return;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<Int32 Function(RacHandle),
        int Function(RacHandle)>('rac_diffusion_component_cancel');
    final rc = fn(h);
    if (rc != RAC_SUCCESS) {
      _throwForCode('rac_diffusion_component_cancel', rc);
    }
  }

  /// Backend capability discovery.
  DiffusionCapabilities capabilities() {
    if (!SdkState.shared.isInitialized) return DiffusionCapabilities();
    final handle = _ensureHandle();
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
      final rc = fn(handle, outBytesPtr, outLenPtr);
      if (rc != RAC_SUCCESS) {
        _throwForCode('rac_diffusion_component_get_capabilities', rc);
      }
      final len = outLenPtr.value;
      final bytes = outBytesPtr.value.asTypedList(len);
      return DiffusionCapabilities.fromBuffer(bytes);
    } finally {
      calloc.free(outBytesPtr);
      calloc.free(outLenPtr);
    }
  }
}
