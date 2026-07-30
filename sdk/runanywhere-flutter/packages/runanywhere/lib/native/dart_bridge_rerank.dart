// SPDX-License-Identifier: Apache-2.0
//
// Thin generated-proto rerank bridge. Unlike diarization and segmentation, the
// rerank primitive ships only handle-scoped verbs, so this bridge owns a
// component handle and loads the lifecycle-resolved model into it before
// scoring — mirroring Kotlin's `CppBridgeRerank`.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/ra_result_codes.dart';
import 'package:runanywhere/generated/rerank.pb.dart'
    show RerankRequest, RerankResult;
import 'package:runanywhere/generated/sdk_events.pb.dart'
    show ComponentLifecycleSnapshot;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';
import 'package:runanywhere/native/types/basic_types.dart';

/// Bridge over the `rac_rerank_component_*` C ABI.
class DartBridgeRerank {
  DartBridgeRerank._();

  /// Process-wide bridge instance.
  static final DartBridgeRerank shared = DartBridgeRerank._();

  RacHandle? _handle;
  String? _loadedModelId;

  /// Score [request] with the model described by [snapshot].
  ///
  /// Throws [SDKException] when the snapshot carries no resolved path, and
  /// [UnsupportedError] when the commons binary predates the rerank ABI.
  RerankResult rerank(
    RerankRequest request,
    ComponentLifecycleSnapshot snapshot,
  ) {
    final fn = RacNative.bindings.rac_rerank_component_rerank_proto;
    if (fn == null) {
      throw UnsupportedError(
        'rac_rerank_component_rerank_proto is unavailable',
      );
    }
    _prepareHandle(snapshot);
    return DartBridgeProtoUtils.callRequestWithHandle<RerankResult>(
      handle: _handle!,
      request: request,
      invoke: fn,
      decode: RerankResult.fromBuffer,
      symbol: 'rac_rerank_component_rerank_proto',
    );
  }

  void _prepareHandle(ComponentLifecycleSnapshot snapshot) {
    final modelId = snapshot.modelId.isNotEmpty
        ? snapshot.modelId
        : snapshot.model.id;
    final modelPath = snapshot.resolvedPath.isNotEmpty
        ? snapshot.resolvedPath
        : snapshot.model.localPath;
    if (modelId.isEmpty || modelPath.isEmpty) {
      throw SDKException.modelLoadFailed(
        modelId,
        'Loaded rerank model is missing a resolved path',
      );
    }
    if (_loadedModelId == modelId && _handle != null) {
      return;
    }
    final handle = _ensureHandle();
    final loadModel = RacNative.bindings.rac_rerank_component_load_model;
    if (loadModel == null) {
      throw UnsupportedError('rac_rerank_component_load_model is unavailable');
    }
    final pathPtr = modelPath.toNativeUtf8();
    final idPtr = modelId.toNativeUtf8();
    final namePtr = (snapshot.model.name.isNotEmpty
            ? snapshot.model.name
            : modelId)
        .toNativeUtf8();
    try {
      final code = loadModel(handle, pathPtr, idPtr, namePtr);
      if (code != RacResultCodes.success) {
        throw SDKException.modelLoadFailed(
          modelId,
          'rac_rerank_component_load_model failed: '
          '${RacResultCodes.message(code)}',
        );
      }
      _loadedModelId = modelId;
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  RacHandle _ensureHandle() {
    final existing = _handle;
    if (existing != null) return existing;
    final create = RacNative.bindings.rac_rerank_component_create;
    if (create == null) {
      throw UnsupportedError('rac_rerank_component_create is unavailable');
    }
    final out = calloc<Pointer<Void>>();
    try {
      final code = create(out);
      if (code != RacResultCodes.success) {
        throw SDKException.componentNotInitialized(
          'rerank (${RacResultCodes.message(code)})',
        );
      }
      final handle = out.value;
      _handle = handle;
      return handle;
    } finally {
      calloc.free(out);
    }
  }
}
