// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_downloads.dart — v4 Downloads capability. Owns model
// download lifecycle, delete, and storage inspection.

import 'dart:io';

import 'package:runanywhere/adapters/model_download_adapter.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/storage_types.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/download_types.dart';

/// Downloads / storage-management capability surface.
///
/// Access via `RunAnywhereSDK.instance.downloads`.
class RunAnywhereDownloads {
  RunAnywhereDownloads._();
  static final RunAnywhereDownloads _instance = RunAnywhereDownloads._();
  static RunAnywhereDownloads get shared => _instance;

  /// Start a model download. Emits per-chunk progress until COMPLETED
  /// or FAILED; telemetry is recorded at each terminal state.
  Stream<DownloadProgress> start(String modelId) async* {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.Download');
    logger.info('📥 Starting download for model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    await for (final progress
        in ModelDownloadService.shared.downloadModel(modelId)) {
      yield DownloadProgress(
        bytesDownloaded: progress.bytesDownloaded,
        totalBytes: progress.totalBytes,
        state: _mapDownloadStage(progress.stage),
      );

      if (progress.stage == ModelDownloadStage.downloading) {
        final pct = (progress.overallProgress * 100).toStringAsFixed(1);
        if (progress.bytesDownloaded % (1024 * 1024) < 10000) {
          logger.debug('Download progress: $pct%');
        }
      } else if (progress.stage == ModelDownloadStage.extracting) {
        logger.info('Extracting model...');
      } else if (progress.stage == ModelDownloadStage.completed) {
        final downloadTimeMs =
            DateTime.now().millisecondsSinceEpoch - startTime;
        logger.info('✅ Download completed for model: $modelId');
        TelemetryService.shared.trackModelDownload(
          modelId: modelId,
          success: true,
          downloadTimeMs: downloadTimeMs,
          sizeBytes: progress.totalBytes,
        );
      } else if (progress.stage == ModelDownloadStage.failed) {
        logger.error('❌ Download failed: ${progress.error}');
        TelemetryService.shared.trackModelDownload(
          modelId: modelId,
          success: false,
        );
        TelemetryService.shared.trackError(
          errorCode: 'download_failed',
          errorMessage: progress.error ?? 'Unknown error',
          context: {'model_id': modelId},
        );
      }
    }
  }

  /// Delete a stored model from the C++ registry + disk.
  Future<void> delete(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.Download');
    final models = await RunAnywhereModels.shared.available();
    final model = models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );

    if (model != null) {
      final deleted = DartBridgeFileManager.deleteModel(
        model.id,
        _frameworkToCValue(model.framework),
      );
      if (!deleted && model.localPath != null) {
        throw SDKError.storageError(
          'Failed to delete stored files for model: ${model.id}',
        );
      }
    } else {
      logger.warning('Delete requested for unknown model: $modelId');
    }

    await DartBridgeModelRegistry.instance.updateDownloadStatus(modelId, null);
    EventBus.shared.publish(SDKModelEvent.deleted(modelId: modelId));
  }

  /// Clear cached files managed by the native file manager.
  Future<void> clearCache() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!DartBridgeFileManager.clearCache()) {
      throw SDKError.storageError('Failed to clear cache directory');
    }
  }

  /// Aggregated storage info: device totals, per-app usage, and every
  /// downloaded model with its on-disk size.
  Future<StorageInfo> getStorageInfo() async {
    if (!SdkState.shared.isInitialized) {
      return StorageInfo.empty;
    }

    try {
      final deviceStorage = await _getDeviceStorageInfo();
      final appStorage = await _getAppStorageInfo();
      final storedModels = await list();
      final modelMetrics = storedModels
          .map((m) =>
              ModelStorageMetrics(model: m.modelInfo, sizeOnDisk: m.size))
          .toList();

      return StorageInfo(
        appStorage: appStorage,
        deviceStorage: deviceStorage,
        models: modelMetrics,
      );
    } catch (e) {
      SDKLogger('RunAnywhere.Storage').error('Failed to get storage info: $e');
      return StorageInfo.empty;
    }
  }

  /// List downloaded models with per-model on-disk size.
  Future<List<StoredModel>> list() async {
    if (!SdkState.shared.isInitialized) {
      return [];
    }

    try {
      final allModels = await RunAnywhereModels.shared.available();
      final downloadedModels =
          allModels.where((m) => m.localPath != null).toList();
      final storedModels = <StoredModel>[];

      for (final model in downloadedModels) {
        final localPath = model.localPath!.toFilePath();
        int fileSize = 0;
        try {
          final file = File(localPath);
          final dir = Directory(localPath);
          if (await file.exists()) {
            fileSize = await file.length();
          } else if (await dir.exists()) {
            fileSize = await _getDirectorySize(localPath);
          }
        } catch (e) {
          SDKLogger('RunAnywhere.Storage')
              .debug('Could not get size for ${model.id}: $e');
        }

        storedModels.add(StoredModel(modelInfo: model, size: fileSize));
      }

      return storedModels;
    } catch (e) {
      SDKLogger('RunAnywhere.Storage')
          .error('Failed to get downloaded models: $e');
      return [];
    }
  }

  // -- private helpers ------------------------------------------------------

  DownloadProgressState _mapDownloadStage(ModelDownloadStage stage) {
    switch (stage) {
      case ModelDownloadStage.downloading:
      case ModelDownloadStage.extracting:
      case ModelDownloadStage.verifying:
        return DownloadProgressState.downloading;
      case ModelDownloadStage.completed:
        return DownloadProgressState.completed;
      case ModelDownloadStage.failed:
        return DownloadProgressState.failed;
      case ModelDownloadStage.cancelled:
        return DownloadProgressState.cancelled;
    }
  }

  Future<DeviceStorageInfo> _getDeviceStorageInfo() async {
    try {
      final modelsDir = DartBridgeModelPaths.instance.getModelsDirectory();
      if (modelsDir == null) {
        return const DeviceStorageInfo(
            totalSpace: 0, freeSpace: 0, usedSpace: 0);
      }
      final modelsDirSize = await _getDirectorySize(modelsDir);
      return DeviceStorageInfo(
        totalSpace: modelsDirSize,
        freeSpace: 0,
        usedSpace: modelsDirSize,
      );
    } catch (e) {
      return const DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0);
    }
  }

  Future<AppStorageInfo> _getAppStorageInfo() async {
    try {
      final modelsDir = DartBridgeModelPaths.instance.getModelsDirectory();
      final modelsDirSize =
          modelsDir != null ? await _getDirectorySize(modelsDir) : 0;
      return AppStorageInfo(
        documentsSize: modelsDirSize,
        cacheSize: 0,
        appSupportSize: 0,
        totalSize: modelsDirSize,
      );
    } catch (e) {
      return const AppStorageInfo(
        documentsSize: 0,
        cacheSize: 0,
        appSupportSize: 0,
        totalSize: 0,
      );
    }
  }

  Future<int> _getDirectorySize(String path) async =>
      DartBridgeFileManager.calculateDirectorySize(path);

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
      case InferenceFramework.unknown:
        return 99;
    }
  }
}
