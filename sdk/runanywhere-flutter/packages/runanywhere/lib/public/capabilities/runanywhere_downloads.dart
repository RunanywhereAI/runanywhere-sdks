// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_downloads.dart — v4 Downloads capability. Owns model
// download lifecycle, delete, and storage inspection.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/storage_types.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_download.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
// §15 type-discipline: `DownloadStage` + `DownloadProgress` from
// `generated/download_service.pb.dart` are the canonical
// proto-generated types. Downloads now yield `DownloadProgress` directly
// from `DownloadManager`; no mapping layer is needed.

/// Downloads / storage-management capability surface.
///
/// Access via `RunAnywhere.downloads`.
class RunAnywhereDownloads {
  RunAnywhereDownloads._();
  static final RunAnywhereDownloads _instance = RunAnywhereDownloads._();
  static RunAnywhereDownloads get shared => _instance;

  final Map<String, String> _activeTaskIdsByModel = {};

  /// Build a generated download plan in C++.
  Future<DownloadPlanResult> plan(DownloadPlanRequest request) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDownload.instance.planProto(request);
  }

  /// Start a generated download plan in C++.
  Future<DownloadStartResult> startDownload(
    DownloadStartRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = await DartBridgeDownload.instance.startProto(request);
    if (result.accepted &&
        result.modelId.isNotEmpty &&
        result.taskId.isNotEmpty) {
      _activeTaskIdsByModel[result.modelId] = result.taskId;
    }
    return result;
  }

  /// Start a model download. Emits per-chunk progress until COMPLETED
  /// or FAILED; telemetry is recorded at each terminal state.
  ///
  /// Progress events are delivered via the commons-owned proto callback
  /// (`rac_download_set_progress_proto_callback`). No Dart-side polling.
  Stream<DownloadProgress> start(String modelId) async* {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();

    final logger = SDKLogger('RunAnywhere.Download');
    logger.info('Starting download for model: $modelId');

    final models = await RunAnywhereModels.shared.available();
    final model = models.cast<ModelInfo?>().firstWhere(
      (m) => m?.id == modelId,
      orElse: () => null,
    );
    if (model == null) {
      yield DownloadProgress(
        modelId: modelId,
        state: DownloadState.DOWNLOAD_STATE_FAILED,
        errorMessage: 'Model not found: $modelId',
      );
      return;
    }

    final planResult = await plan(
      DownloadPlanRequest(
        modelId: modelId,
        model: model,
        resumeExisting: true,
        // Commons self-heals oversize partials at plan time and verifies
        // declared checksums during transfer (Swift parity).
        validateExistingBytes: true,
        verifyChecksums: model.checksumSha256.isNotEmpty,
        allowMeteredNetwork: true,
      ),
    );
    if (!planResult.canStart) {
      yield DownloadProgress(
        modelId: modelId,
        state: DownloadState.DOWNLOAD_STATE_FAILED,
        errorMessage: planResult.errorMessage.isNotEmpty
            ? planResult.errorMessage
            : 'Download cannot start for model: $modelId',
      );
      return;
    }

    // Subscribe BEFORE starting so we don't lose early native callbacks.
    // Filter the process-wide stream down to this model id.
    final progressStream = DartBridgeDownload.instance.progressStream.where(
      (p) => p.modelId == modelId,
    );

    final startResult = await startDownload(
      DownloadStartRequest(
        modelId: modelId,
        plan: planResult,
        resume: planResult.canResume,
        // Commons owns the completion registry mutation: the orchestrator's
        // self-heal calls rac_model_registry_update_download_status, which
        // also persists the durable .rac-manifest.binpb sidecar restored on
        // the next cold launch.
        updateRegistryOnCompletion: true,
      ),
    );
    if (!startResult.accepted) {
      yield DownloadProgress(
        modelId: modelId,
        state: DownloadState.DOWNLOAD_STATE_FAILED,
        errorMessage: startResult.errorMessage.isNotEmpty
            ? startResult.errorMessage
            : 'Download start was rejected for model: $modelId',
      );
      return;
    }

    logger.info('Download accepted for $modelId (task=${startResult.taskId})');

    if (startResult.hasInitialProgress()) {
      yield startResult.initialProgress;
      if (_isTerminalState(startResult.initialProgress.state)) {
        _activeTaskIdsByModel.remove(modelId);
        return;
      }
    }

    // Track whether the native download reached a terminal state. When the
    // Stream subscription is cancelled before a terminal event, the finally
    // block sends rac_download_cancel_proto so the detached native worker stops
    // instead of leaking bandwidth, battery, and file handles.
    // Mirrors Kotlin's NonCancellable finally and Swift's CancellationError catch.
    // delete_partial_bytes=false preserves resume bytes for a later retry.
    var reachedTerminal = false;
    try {
      await for (final progress in progressStream) {
        yield progress;

        if (progress.stage == DownloadStage.DOWNLOAD_STAGE_DOWNLOADING) {
          final pct = (progress.stageProgress * 100).toStringAsFixed(1);
          if (progress.bytesDownloaded.toInt() % (1024 * 1024) < 10000) {
            logger.debug('Download progress: $pct%');
          }
        } else if (progress.stage == DownloadStage.DOWNLOAD_STAGE_EXTRACTING) {
          logger.info('Extracting model...');
        } else if (progress.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) {
          logger.info('Download completed for model: $modelId');
        } else if (progress.errorMessage.isNotEmpty) {
          logger.error('Download failed: ${progress.errorMessage}');
        }

        if (_isTerminalState(progress.state)) {
          reachedTerminal = true;
          break;
        }
      }
    } finally {
      if (!reachedTerminal) {
        try {
          await DartBridgeDownload.instance.cancelProto(
            DownloadCancelRequest(
              modelId: modelId,
              taskId: startResult.taskId,
              deletePartialBytes: false,
            ),
          );
          logger.info(
            'Download cancelled for $modelId (task=${startResult.taskId})',
          );
        } catch (e) {
          logger.warning(
            'Failed to cancel native download for $modelId '
            '(task=${startResult.taskId}): $e',
          );
        }
      }
      _activeTaskIdsByModel.remove(modelId);
    }
  }

  static bool _isTerminalState(DownloadState state) {
    return state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
        state == DownloadState.DOWNLOAD_STATE_FAILED ||
        state == DownloadState.DOWNLOAD_STATE_CANCELLED;
  }

  /// Cancel an active model download if the adapter still owns it.
  Future<DownloadCancelResult> cancelDownload(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = await cancel(
      DownloadCancelRequest(
        modelId: modelId,
        taskId: _activeTaskIdsByModel[modelId] ?? '',
      ),
    );
    _activeTaskIdsByModel.remove(modelId);
    return result;
  }

  Future<DownloadCancelResult> cancel(DownloadCancelRequest request) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDownload.instance.cancelProto(request);
  }

  Future<DownloadResumeResult> resume(DownloadResumeRequest request) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = await DartBridgeDownload.instance.resumeProto(request);
    if (result.accepted &&
        result.modelId.isNotEmpty &&
        result.taskId.isNotEmpty) {
      _activeTaskIdsByModel[result.modelId] = result.taskId;
    }
    return result;
  }

  Future<DownloadProgress?> pollProgress(
    DownloadSubscribeRequest request,
  ) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDownload.instance.pollProgressProto(request);
  }

  /// Delete a stored model from the C++ registry + disk.
  Future<StorageDeleteResult> delete(String modelId) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    return DartBridgeStorage.instance.deleteProto(
      StorageDeleteRequest(
        modelIds: [modelId],
        deleteFiles: true,
        clearRegistryPaths: true,
        unloadIfLoaded: true,
        allowPlatformDelete: true,
      ),
    );
  }

  /// Delete every downloaded model while keeping registry entries available.
  Future<StorageDeleteResult> deleteAllModels() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    final metrics = await list();
    return DartBridgeStorage.instance.deleteProto(
      StorageDeleteRequest(
        modelIds: metrics.map((m) => m.modelId),
        deleteFiles: true,
        clearRegistryPaths: true,
        unloadIfLoaded: true,
        allowPlatformDelete: true,
      ),
    );
  }

  /// Clear cached files managed by the native file manager.
  Future<void> clearCache() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    if (!DartBridgeFileManager.clearCache()) {
      throw SDKException.storageError('Failed to clear cache directory');
    }
  }

  /// Aggregated storage info: device totals, per-app usage, and every
  /// downloaded model with its on-disk size.
  Future<StorageInfoResult> getStorageInfoResult([
    StorageInfoRequest? request,
  ]) async {
    if (!DartBridge.isInitialized) {
      return StorageInfoResult(
        success: false,
        errorMessage: 'SDK not initialized',
      );
    }

    return DartBridgeStorage.instance.infoProto(
      request ??
          StorageInfoRequest(
            includeApp: true,
            includeDevice: true,
            includeModels: true,
          ),
    );
  }

  Future<StorageInfo> getStorageInfo() async {
    final result = await getStorageInfoResult();
    return result.hasInfo() ? result.info : StorageInfo();
  }

  /// List downloaded models with per-model on-disk size.
  Future<List<ModelStorageMetrics>> list() async {
    if (!DartBridge.isInitialized) {
      return [];
    }

    try {
      final result = await getStorageInfoResult(
        StorageInfoRequest(includeModels: true),
      );
      return result.hasInfo()
          ? List<ModelStorageMetrics>.unmodifiable(result.info.models)
          : const <ModelStorageMetrics>[];
    } catch (e) {
      SDKLogger(
        'RunAnywhere.Storage',
      ).error('Failed to get downloaded models: $e');
      return [];
    }
  }
}
