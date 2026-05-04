// SPDX-License-Identifier: Apache-2.0
//
// Generated-proto diffusion service bridge.

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionCapabilities,
        DiffusionGenerationOptions,
        DiffusionProgress,
        DiffusionResult;
import 'package:runanywhere/generated/diffusion_options.pbenum.dart'
    show DiffusionMode;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';

const _capTextToImage = 1 << 0;
const _capImageToImage = 1 << 1;
const _capInpainting = 1 << 2;
const _capIntermediateImages = 1 << 3;
const _capSafetyChecker = 1 << 4;

/// FFI bridge to the generated-proto `rac_diffusion_*` service ABI.
class DartBridgeDiffusion {
  DartBridgeDiffusion._();

  static RacHandle? _handle;
  static String? _modelId;

  /// Whether the bridge currently holds a diffusion service handle.
  static bool get hasHandle => _handle != null;

  /// True when a diffusion model service is currently initialized.
  static bool isLoaded() => _handle != null;

  static String? get currentModelId => _modelId;

  /// Load and initialize a diffusion service for [modelId].
  static void loadModel(
    String modelId,
    String modelPath, {
    ffi.Pointer<ffi.Void>? config,
  }) {
    unload();

    final create = config == null
        ? RacNative.bindings.rac_diffusion_create
        : RacNative.bindings.rac_diffusion_create_with_config;
    final initialize = RacNative.bindings.rac_diffusion_initialize;
    if (create == null || initialize == null) {
      throw UnsupportedError('Diffusion service proto ABI is unavailable');
    }

    final modelIdPtr = modelId.toNativeUtf8();
    final modelPathPtr = modelPath.toNativeUtf8();
    final out = calloc<RacHandle>();

    try {
      final rc = config == null
          ? RacNative.bindings.rac_diffusion_create!(modelIdPtr, out)
          : RacNative.bindings.rac_diffusion_create_with_config!(
              modelIdPtr,
              config,
              out,
            );
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_diffusion_create failed: ${RacResultCode.getMessage(rc)}',
        );
      }

      final initRc = initialize(out.value, modelPathPtr, config ?? ffi.nullptr);
      if (initRc != RAC_SUCCESS) {
        RacNative.bindings.rac_diffusion_destroy?.call(out.value);
        throw StateError(
          'rac_diffusion_initialize failed: '
          '${RacResultCode.getMessage(initRc)}',
        );
      }

      _handle = out.value;
      _modelId = modelId;
    } finally {
      calloc.free(modelIdPtr);
      calloc.free(modelPathPtr);
      calloc.free(out);
    }
  }

  /// Destroy the active diffusion service.
  static int unload() {
    final handle = _handle;
    if (handle == null) return RAC_SUCCESS;
    RacNative.bindings.rac_diffusion_destroy?.call(handle);
    _handle = null;
    _modelId = null;
    return RAC_SUCCESS;
  }

  /// Generate an image from canonical proto options.
  static DiffusionResult generateProto(DiffusionGenerationOptions options) {
    final handle = _requireHandle();
    final fn = RacNative.bindings.rac_diffusion_generate_proto;
    if (fn == null) {
      throw UnsupportedError('rac_diffusion_generate_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<DiffusionResult>(
      handle: handle,
      request: options,
      invoke: fn,
      decode: DiffusionResult.fromBuffer,
      symbol: 'rac_diffusion_generate_proto',
    );
  }

  /// Generate with native progress callbacks.
  static Stream<DiffusionProgress> generateWithProgressProto(
    DiffusionGenerationOptions options,
  ) {
    final handle = _requireHandle();
    final fn = RacNative.bindings.rac_diffusion_generate_with_progress_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_diffusion_generate_with_progress_proto is unavailable',
      );
    }

    final controller = StreamController<DiffusionProgress>();
    ffi.NativeCallable<RacDiffusionProgressProtoCallbackNative>? callback;

    unawaited(Future<void>(() {
      final requestBytes = options.writeToBuffer();
      final requestPtr = DartBridgeProtoUtils.copyBytes(requestBytes);
      final out = calloc<RacProtoBuffer>();
      final bindings = RacNative.bindings;

      try {
        bindings.rac_proto_buffer_init(out);
        callback = ffi.NativeCallable<
            RacDiffusionProgressProtoCallbackNative>.isolateLocal(
          (
            ffi.Pointer<ffi.Uint8> data,
            int size,
            ffi.Pointer<ffi.Void> userData,
          ) {
            try {
              if (!controller.isClosed) {
                controller.add(
                  DiffusionProgress.fromBuffer(data.asTypedList(size)),
                );
              }
              return RAC_TRUE;
            } catch (e, st) {
              if (!controller.isClosed) {
                controller.addError(e, st);
              }
              return RAC_FALSE;
            }
          },
          exceptionalReturn: RAC_FALSE,
        );

        final code = fn(
          handle,
          requestPtr,
          requestBytes.length,
          callback!.nativeFunction,
          ffi.nullptr,
          out,
        );
        DartBridgeProtoUtils.ensureSuccess(
          out,
          code,
          'rac_diffusion_generate_with_progress_proto',
        );
        final result =
            DartBridgeProtoUtils.decodeBuffer(out, DiffusionResult.fromBuffer);
        if (!controller.isClosed) {
          controller.add(
            DiffusionProgress(
              progressPercent: 1.0,
              stage: 'completed',
              intermediateImageData: result.imageData,
              intermediateImageWidth: result.width,
              intermediateImageHeight: result.height,
            ),
          );
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      } finally {
        bindings.rac_proto_buffer_free(out);
        calloc.free(requestPtr);
        calloc.free(out);
        callback?.close();
        callback = null;
        if (!controller.isClosed) {
          unawaited(controller.close());
        }
      }
    }));

    controller.onCancel = () {
      cancel();
      callback?.close();
      callback = null;
    };
    return controller.stream;
  }

  /// Cancel any in-flight generation.
  static int cancel() {
    final handle = _handle;
    if (handle == null) return RAC_SUCCESS;
    final fn = RacNative.bindings.rac_diffusion_cancel_proto;
    if (fn == null) {
      throw UnsupportedError('rac_diffusion_cancel_proto is unavailable');
    }
    return fn(handle);
  }

  /// Adapter for the service capability bitmask. There is no capability
  /// proto C ABI yet, so this keeps the public return type generated.
  static DiffusionCapabilities capabilitiesProto() {
    final handle = _requireHandle();
    final fn = RacNative.bindings.rac_diffusion_get_capabilities;
    if (fn == null) {
      throw UnsupportedError('rac_diffusion_get_capabilities is unavailable');
    }
    final caps = fn(handle);
    return DiffusionCapabilities(
      supportedModes: [
        if ((caps & _capTextToImage) != 0)
          DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
        if ((caps & _capImageToImage) != 0)
          DiffusionMode.DIFFUSION_MODE_IMAGE_TO_IMAGE,
        if ((caps & _capInpainting) != 0)
          DiffusionMode.DIFFUSION_MODE_INPAINTING,
      ],
      supportsIntermediateImages: (caps & _capIntermediateImages) != 0,
      supportsSafetyChecker: (caps & _capSafetyChecker) != 0,
      isReady: true,
      currentModel: _modelId ?? '',
    );
  }

  static RacHandle _requireHandle() {
    final handle = _handle;
    if (handle == null) {
      throw StateError('No diffusion model loaded. Call load() first.');
    }
    return handle;
  }
}
