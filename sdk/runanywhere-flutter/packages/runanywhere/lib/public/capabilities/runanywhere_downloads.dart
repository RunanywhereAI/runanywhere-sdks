// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_downloads.dart — v4 Downloads capability. Owns model
// download lifecycle, delete, and storage inspection.

import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/storage_types.pb.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_download.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
// §15 type-discipline: `DownloadStage` + `DownloadProgress` from
// `generated/download_service.pb.dart` are the canonical
// proto-generated types. `ModelDownloadService` now yields
// `DownloadProgress` directly — no mapping needed.

/// Downloads / storage-management capability surface.
///
/// Access via `RunAnywhereSDK.instance.downloads`.
class RunAnywhereDownloads {
  RunAnywhereDownloads._();
  static final RunAnywhereDownloads _instance = RunAnywhereDownloads._();
  static RunAnywhereDownloads get shared => _instance;

  final Map<String, String> _activeTaskIdsByModel = {};

  /// Build a generated download plan in C++.
  Future<DownloadPlanResult> plan(DownloadPlanRequest request) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDownload.instance.planProto(request);
  }

  /// Start a generated download plan in C++.
  Future<DownloadStartResult> startDownload(
    DownloadStartRequest request,
  ) async {
    if (!SdkState.shared.isInitialized) {
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
  Stream<DownloadProgress> start(String modelId) async* {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.Download');
    logger.info('📥 Starting download for model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

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

    final planResult = await plan(DownloadPlanRequest(
      modelId: modelId,
      model: model,
      resumeExisting: true,
      allowMeteredNetwork: true,
    ));
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

    final startResult = await startDownload(DownloadStartRequest(
      modelId: modelId,
      plan: planResult,
      resume: planResult.canResume,
    ));
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

    if (startResult.hasInitialProgress()) {
      yield startResult.initialProgress;
    }

    var terminal = false;
    while (!terminal) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final progress = await pollProgress(DownloadSubscribeRequest(
        modelId: modelId,
        taskId: startResult.taskId,
      ));
      if (progress == null) continue;
      yield progress;

      if (progress.stage == DownloadStage.DOWNLOAD_STAGE_DOWNLOADING) {
        final pct = (progress.stageProgress * 100).toStringAsFixed(1);
        if (progress.bytesDownloaded.toInt() % (1024 * 1024) < 10000) {
          logger.debug('Download progress: $pct%');
        }
      } else if (progress.stage == DownloadStage.DOWNLOAD_STAGE_EXTRACTING) {
        logger.info('Extracting model...');
      } else if (progress.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) {
        final downloadTimeMs =
            DateTime.now().millisecondsSinceEpoch - startTime;
        logger.info('✅ Download completed for model: $modelId');
        TelemetryService.shared.trackModelDownload(
          modelId: modelId,
          success: true,
          downloadTimeMs: downloadTimeMs,
          sizeBytes: progress.totalBytes.toInt(),
        );
      } else if (progress.errorMessage.isNotEmpty) {
        terminal = true;
        logger.error('❌ Download failed: ${progress.errorMessage}');
        TelemetryService.shared.trackModelDownload(
          modelId: modelId,
          success: false,
        );
        TelemetryService.shared.trackError(
          errorCode: 'download_failed',
          errorMessage: progress.errorMessage,
          context: {'model_id': modelId},
        );
      }

      if (progress.state == DownloadState.DOWNLOAD_STATE_COMPLETED ||
          progress.state == DownloadState.DOWNLOAD_STATE_FAILED ||
          progress.state == DownloadState.DOWNLOAD_STATE_CANCELLED) {
        terminal = true;
      }
    }

    _activeTaskIdsByModel.remove(modelId);
  }

  /// Cancel an active model download if the adapter still owns it.
  Future<DownloadCancelResult> cancelDownload(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final result = await cancel(DownloadCancelRequest(
      modelId: modelId,
      taskId: _activeTaskIdsByModel[modelId] ?? '',
    ));
    _activeTaskIdsByModel.remove(modelId);
    return result;
  }

  Future<DownloadCancelResult> cancel(DownloadCancelRequest request) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDownload.instance.cancelProto(request);
  }

  Future<DownloadResumeResult> resume(DownloadResumeRequest request) async {
    if (!SdkState.shared.isInitialized) {
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
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeDownload.instance.pollProgressProto(request);
  }

  /// Delete a stored model from the C++ registry + disk.
  Future<StorageDeleteResult> delete(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    return DartBridgeStorage.instance.deleteProto(StorageDeleteRequest(
      modelIds: [modelId],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
    ));
  }

  /// Delete every downloaded model while keeping registry entries available.
  Future<StorageDeleteResult> deleteAllModels() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final storedModels = await list();
    return DartBridgeStorage.instance.deleteProto(StorageDeleteRequest(
      modelIds: storedModels.map((m) => m.modelId),
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
    ));
  }

  /// Clear cached files managed by the native file manager.
  Future<void> clearCache() async {
    if (!SdkState.shared.isInitialized) {
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
    if (!SdkState.shared.isInitialized) {
      return StorageInfoResult(
          success: false, errorMessage: 'SDK not initialized');
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
  Future<List<StoredModel>> list() async {
    if (!SdkState.shared.isInitialized) {
      return [];
    }

    try {
      final result = await getStorageInfoResult(StorageInfoRequest(
        includeModels: true,
      ));
      if (result.hasInfo() && result.info.models.isNotEmpty) {
        final downloaded =
            await DartBridgeModelRegistry.instance.listDownloadedProtoModels();
        final byId = {for (final model in downloaded) model.id: model};
        return result.info.models.map((metric) {
          final model = byId[metric.modelId];
          return StoredModel(
            modelId: metric.modelId,
            name: model?.name ?? metric.modelId,
            sizeBytes: metric.sizeOnDiskBytes,
            localPath: model?.localPath ?? '',
            downloadedAtMs: metric.lastUsedMs,
          );
        }).toList(growable: false);
      }

      final downloaded =
          await DartBridgeModelRegistry.instance.listDownloadedProtoModels();
      return downloaded
          .map((model) => StoredModel(
                modelId: model.id,
                name: model.name,
                sizeBytes: model.downloadSizeBytes,
                localPath: model.localPath,
              ))
          .toList(growable: false);
    } catch (e) {
      SDKLogger('RunAnywhere.Storage')
          .error('Failed to get downloaded models: $e');
      return [];
    }
  }
}
