// SPDX-License-Identifier: Apache-2.0
//
// model_download_adapter.dart — thin FFI shim over
// `rac_download_orchestrate`. The C++ orchestrator owns the whole
// lifecycle (path resolution, HTTP transfer, extraction, archive
// cleanup, registry update). Dart only marshals a `DownloadProgress`
// stream out of the native callbacks.
//
// Public API: `ModelDownloadService.shared.downloadModel(id)` now
// yields the proto-generated `DownloadProgress` type directly. The
// legacy hand-rolled `ModelDownloadProgress` / `ModelDownloadStage`
// are gone — `DownloadProgress` / `DownloadStage` from
// `generated/download_service.pb.dart` are canonical.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fixnum/fixnum.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart';
import 'package:runanywhere/generated/download_service.pbenum.dart';
import 'package:runanywhere/native/dart_bridge_download.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

// ============================================================================
// Service
// ============================================================================

/// Model download service — thin Dart wrapper around the C++
/// `rac_download_orchestrate` lifecycle runner.
class ModelDownloadService {
  ModelDownloadService._();
  static final ModelDownloadService shared = ModelDownloadService._();

  final SDKLogger _logger = SDKLogger('ModelDownloadService');

  /// Active downloads keyed by modelId. Value is the task id returned by
  /// the orchestrator (used to route cancel requests back into C++).
  final Map<String, String> _activeTaskIds = {};

  /// Download a model by ID. Yields `DownloadProgress` as the C++
  /// orchestrator advances through download → extraction → registry
  /// update.
  Stream<DownloadProgress> downloadModel(String modelId) async* {
    _logger.info('Starting orchestrated download for model: $modelId');

    final models = await RunAnywhereModels.shared.available();
    final model = models.where((m) => m.id == modelId).firstOrNull;

    if (model == null) {
      _logger.error('Model not found: $modelId');
      yield _failedProgress(modelId, 'Model not found: $modelId');
      return;
    }

    if (model.downloadURL == null) {
      _logger.error('Model has no download URL: $modelId');
      yield _failedProgress(modelId, 'Model has no download URL: $modelId');
      return;
    }

    EventBus.shared.publish(SDKModelEvent.downloadStarted(modelId: modelId));

    yield* _orchestrate(model);
  }

  /// Cancel an active download. The C++ orchestrator will emit a
  /// terminal FAILED/CANCELLED state through the progress callback.
  void cancelDownload(String modelId) {
    final taskId = _activeTaskIds[modelId];
    if (taskId == null) {
      _logger.debug('Cancel requested for unknown download: $modelId');
      return;
    }
    DartBridgeDownload.cancelOrchestratedDownload(taskId);
    _logger.info('Download cancel requested: $modelId (task=$taskId)');
  }

  /// Download a caller-managed file through the commons HTTP runner.
  ///
  /// Used by backend packages (e.g. ONNX companion-file prefetch) that
  /// manage their own destination layout but still want the shared
  /// native transport.
  ///
  /// When [expectedSha256Hex] is provided, the native runner verifies
  /// the SHA-256 of the written bytes inline on the write path and
  /// fails with `RAC_HTTP_DL_CHECKSUM_FAILED` on mismatch.
  Future<void> downloadFile({
    required String downloadId,
    required Uri url,
    required File destination,
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
    String? expectedSha256Hex,
  }) async {
    await destination.parent.create(recursive: true);

    final bindings = RacNative.bindings;
    final urlPtr = url.toString().toNativeUtf8();
    final destPtr = destination.path.toNativeUtf8();
    final reqPtr = calloc<RacHttpDownloadRequest>();
    final outStatus = calloc<ffi.Int32>();
    final sha256Ptr = expectedSha256Hex != null && expectedSha256Hex.isNotEmpty
        ? expectedSha256Hex.toNativeUtf8()
        : ffi.nullptr.cast<Utf8>();

    reqPtr.ref
      ..url = urlPtr
      ..destinationPath = destPtr
      ..headers = ffi.nullptr.cast()
      ..headerCount = 0
      ..timeoutMs = 0
      ..followRedirects = 1
      ..resumeFromByte = 0
      ..expectedSha256Hex = sha256Ptr;

    int code;
    try {
      code = bindings.rac_http_download_execute(
        reqPtr,
        ffi.nullptr,
        ffi.nullptr,
        outStatus,
      );
    } finally {
      calloc.free(urlPtr);
      calloc.free(destPtr);
      calloc.free(reqPtr);
      calloc.free(outStatus);
      if (sha256Ptr != ffi.nullptr.cast<Utf8>()) {
        calloc.free(sha256Ptr);
      }
    }

    if (code != 0) {
      throw Exception(
        'Download failed for $url (id=$downloadId): status code $code',
      );
    }

    // Best-effort progress ping for callers — the underlying runner is
    // blocking so we only know the final size.
    try {
      final len = await destination.length();
      onProgress?.call(len, len);
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // Internal: drive rac_download_orchestrate and poll progress from Dart.
  //
  // The C++ orchestrator spawns a std::thread for the HTTP transfer. Dart
  // NativeCallable.listener requires the calling thread to be attached to
  // the Dart VM, but std::thread is not. Passing callbacks from Dart to
  // the orchestrator causes "Cannot invoke native callback outside an
  // isolate" + SIGABRT.
  //
  // Fix: pass nullptr for both callbacks and poll
  // rac_download_manager_get_progress() on a 250ms timer from the Dart
  // isolate. Detect completion/failure via the progress state field.
  // --------------------------------------------------------------------------

  Stream<DownloadProgress> _orchestrate(ModelInfo model) async* {
    final taskId = DartBridgeDownload.orchestrateDownload(
      modelId: model.id,
      downloadUrl: model.downloadURL!.toString(),
      framework: _frameworkToCValue(model.framework),
      format: model.format.toC(),
      archiveStructure: 99, // RAC_ARCHIVE_STRUCTURE_UNKNOWN → auto-detect
      progressCallback: ffi.Pointer.fromAddress(0),
      completeCallback: ffi.Pointer.fromAddress(0),
      userData: ffi.nullptr,
    );

    if (taskId == null) {
      yield _failedProgress(model.id, 'Failed to start orchestrated download');
      return;
    }
    _activeTaskIds[model.id] = taskId;
    _logger.info('Orchestrated download started: ${model.id} (task=$taskId)');

    const pollInterval = Duration(milliseconds: 250);
    var settled = false;

    while (!settled) {
      await Future<void>.delayed(pollInterval);

      final snapshot = DartBridgeDownload.getProgress(taskId);
      if (snapshot == null) {
        // Task disappeared — treat as completed (files already on disk).
        settled = true;
        break;
      }

      final proto = _protoFromNative(model.id, snapshot);
      yield proto;

      // Terminal states — 4=COMPLETED, 5=FAILED, 6=CANCELLED (rac_download.h)
      final stateVal = snapshot.state;
      if (stateVal == 4 || stateVal == 5 || stateVal == 6) {
        settled = true;

        if (stateVal == 4) {
          // Resolve final model path from the registry
          final modelPath = _resolveModelPath(model);
          if (modelPath != null) {
            await _updateModelLocalPath(model, modelPath);
          }
          EventBus.shared.publish(
            SDKModelEvent.downloadCompleted(modelId: model.id),
          );
          yield DownloadProgress(
            modelId: model.id,
            stage: DownloadStage.DOWNLOAD_STAGE_COMPLETED,
            state: DownloadState.DOWNLOAD_STATE_COMPLETED,
            stageProgress: 1.0,
          );
        } else {
          final errMsg = snapshot.errorMessage ??
              'Download failed (state=$stateVal)';
          EventBus.shared.publish(
            SDKModelEvent.downloadFailed(modelId: model.id, error: errMsg),
          );
          yield _failedProgress(model.id, errMsg);
        }
      }
    }

    _activeTaskIds.remove(model.id);
  }

  String? _resolveModelPath(ModelInfo model) {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<
          ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32, ffi.Pointer<Utf8>, ffi.Int32),
          int Function(ffi.Pointer<Utf8>, int, ffi.Pointer<Utf8>,
              int)>('rac_model_paths_get_model_folder');

      final modelIdPtr = model.id.toNativeUtf8();
      final buf = calloc<ffi.Uint8>(4096).cast<Utf8>();
      try {
        final rc = fn(modelIdPtr, _frameworkToCValue(model.framework), buf, 4096);
        if (rc != 0) return null;
        return buf.toDartString();
      } finally {
        calloc.free(modelIdPtr);
        calloc.free(buf);
      }
    } catch (_) {
      return null;
    }
  }

  DownloadProgress _protoFromNative(
      String modelId, DownloadProgressSnapshot snapshot) {
    return DownloadProgress(
      modelId: modelId,
      stage: _stageFromC(snapshot.stage),
      state: _stateFromC(snapshot.state),
      bytesDownloaded: Int64(snapshot.bytesDownloaded),
      totalBytes: Int64(snapshot.totalBytes),
      stageProgress: snapshot.stageProgress,
      overallSpeedBps: snapshot.speed,
      etaSeconds: snapshot.estimatedTimeRemaining > 0
          ? Int64(snapshot.estimatedTimeRemaining.toInt())
          : Int64.ZERO,
      retryAttempt: snapshot.retryAttempt,
      errorMessage: snapshot.errorMessage ?? '',
    );
  }

  DownloadProgress _failedProgress(String modelId, String error) =>
      DownloadProgress(
        modelId: modelId,
        stage: DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED,
        state: DownloadState.DOWNLOAD_STATE_FAILED,
        errorMessage: error,
      );

  DownloadStage _stageFromC(int raw) {
    switch (raw) {
      case 0:
        return DownloadStage.DOWNLOAD_STAGE_DOWNLOADING;
      case 1:
        return DownloadStage.DOWNLOAD_STAGE_EXTRACTING;
      case 2:
        return DownloadStage.DOWNLOAD_STAGE_VALIDATING;
      case 3:
        return DownloadStage.DOWNLOAD_STAGE_COMPLETED;
      default:
        return DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED;
    }
  }

  DownloadState _stateFromC(int raw) {
    switch (raw) {
      case 0:
        return DownloadState.DOWNLOAD_STATE_PENDING;
      case 1:
        return DownloadState.DOWNLOAD_STATE_DOWNLOADING;
      case 2:
        return DownloadState.DOWNLOAD_STATE_EXTRACTING;
      case 3:
        return DownloadState.DOWNLOAD_STATE_RETRYING;
      case 4:
        return DownloadState.DOWNLOAD_STATE_COMPLETED;
      case 5:
        return DownloadState.DOWNLOAD_STATE_FAILED;
      case 6:
        return DownloadState.DOWNLOAD_STATE_CANCELLED;
      default:
        return DownloadState.DOWNLOAD_STATE_UNSPECIFIED;
    }
  }

  Future<void> _updateModelLocalPath(ModelInfo model, String path) async {
    model.localPath = Uri.file(path);
    _logger.info('Updated model local path: ${model.id} -> $path');
    try {
      await DartBridgeModelRegistry.instance
          .updateDownloadStatus(model.id, path);
    } catch (e) {
      _logger.debug('Could not update C++ registry: $e');
    }
  }

  int _frameworkToCValue(InferenceFramework framework) {
    switch (framework) {
      case InferenceFramework.onnx:
        return 0;
      case InferenceFramework.llamaCpp:
        return 1;
      case InferenceFramework.foundationModels:
        return 2;
      case InferenceFramework.systemTTS:
        return 3;
      case InferenceFramework.fluidAudio:
        return 4;
      case InferenceFramework.builtIn:
        return 5;
      case InferenceFramework.none:
        return 6;
      case InferenceFramework.genie:
        return 11;
      case InferenceFramework.sherpa:
        return 12;
      case InferenceFramework.unknown:
        return 99;
    }
  }
}
