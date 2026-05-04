// SPDX-License-Identifier: Apache-2.0
//
// Generated-proto embeddings service bridge.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/generated/embeddings_options.pb.dart'
    show EmbeddingsRequest, EmbeddingsResult;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/ffi_types.dart';

class DartBridgeEmbeddings {
  DartBridgeEmbeddings._();
  static final DartBridgeEmbeddings shared = DartBridgeEmbeddings._();

  ffi.Pointer<ffi.Void>? _handle;
  String? _modelId;

  bool get isLoaded => _handle != null;
  String? get currentModelId => _modelId;

  void load(String modelId, String modelPath, {String? configJson}) {
    unload();

    final create = configJson != null
        ? RacNative.bindings.rac_embeddings_create_with_config
        : RacNative.bindings.rac_embeddings_create;
    final initialize = RacNative.bindings.rac_embeddings_initialize;
    if (create == null || initialize == null) {
      throw UnsupportedError('Embeddings service proto ABI is unavailable');
    }

    final modelIdPtr = modelId.toNativeUtf8();
    final modelPathPtr = modelPath.toNativeUtf8();
    final configPtr = configJson?.toNativeUtf8();
    final out = calloc<ffi.Pointer<ffi.Void>>();

    try {
      final rc = configJson != null
          ? RacNative.bindings.rac_embeddings_create_with_config!(
              modelIdPtr,
              configPtr!,
              out,
            )
          : RacNative.bindings.rac_embeddings_create!(modelIdPtr, out);
      if (rc != RAC_SUCCESS) {
        throw StateError(
          'rac_embeddings_create failed: ${RacResultCode.getMessage(rc)}',
        );
      }

      final initRc = initialize(out.value, modelPathPtr);
      if (initRc != RAC_SUCCESS) {
        RacNative.bindings.rac_embeddings_destroy?.call(out.value);
        throw StateError(
          'rac_embeddings_initialize failed: '
          '${RacResultCode.getMessage(initRc)}',
        );
      }

      _handle = out.value;
      _modelId = modelId;
    } finally {
      calloc.free(modelIdPtr);
      calloc.free(modelPathPtr);
      if (configPtr != null) {
        calloc.free(configPtr);
      }
      calloc.free(out);
    }
  }

  EmbeddingsResult embedBatch(EmbeddingsRequest request) {
    final handle = _handle;
    if (handle == null) {
      throw StateError('No embeddings model loaded. Call load() first.');
    }
    final fn = RacNative.bindings.rac_embeddings_embed_batch_proto;
    if (fn == null) {
      throw UnsupportedError('rac_embeddings_embed_batch_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequestWithHandle<EmbeddingsResult>(
      handle: handle,
      request: request,
      invoke: fn,
      decode: EmbeddingsResult.fromBuffer,
      symbol: 'rac_embeddings_embed_batch_proto',
    );
  }

  void unload() {
    final handle = _handle;
    if (handle != null) {
      RacNative.bindings.rac_embeddings_destroy?.call(handle);
      _handle = null;
      _modelId = null;
    }
  }
}
