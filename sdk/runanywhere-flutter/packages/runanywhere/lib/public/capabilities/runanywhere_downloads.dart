// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_downloads.dart — v4 Downloads capability. Owns model
// download lifecycle, delete, and storage inspection.

import 'dart:io';

import 'package:runanywhere/adapters/model_download_adapter.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadProgress;
import 'package:runanywhere/generated/download_service.pbenum.dart'
    show DownloadStage;
import 'package:runanywhere/generated/storage_types.pb.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:fixnum/fixnum.dart';
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

  /// Start a model download. Emits per-chunk progress until COMPLETED
  /// or FAILED; telemetry is recorded at each terminal state.
  Stream<DownloadProgress> start(String modelId) async* {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.Download');
    logger.info('📥 Starting download for model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    await for (final progress
        in ModelDownloadService.shared.downloadModel(modelId)) {
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
    }
  }

  /// Cancel an active model download if the adapter still owns it.
  Future<void> cancelDownload(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    ModelDownloadService.shared.cancelDownload(modelId);
  }

  /// Delete a stored model from the C++ registry + disk.
  Future<void> delete(String modelId) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
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
        throw SDKException.storageError(
          'Failed to delete stored files for model: ${model.id}',
        );
      }
    } else {
      logger.warning('Delete requested for unknown model: $modelId');
    }

    await DartBridgeModelRegistry.instance.updateDownloadStatus(modelId, null);
    EventBus.shared.publish(SDKModelEvent.deleted(modelId: modelId));
  }

  /// Delete every downloaded model while keeping registry entries available.
  Future<void> deleteAllModels() async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    final storedModels = await list();
    for (final storedModel in storedModels) {
      await delete(storedModel.modelId);
    }
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
  Future<StorageInfo> getStorageInfo() async {
    if (!SdkState.shared.isInitialized) {
      return StorageInfo();
    }

    try {
      final deviceStorage = await _getDeviceStorageInfo();
      final appStorage = await _getAppStorageInfo();
      final storedModels = await list();
      final modelMetrics = storedModels
          .map((m) => ModelStorageMetrics(
                modelId: m.modelId,
                sizeOnDiskBytes: m.sizeBytes,
              ))
          .toList();

      return StorageInfo(
        app: appStorage,
        device: deviceStorage,
        models: modelMetrics,
        totalModels: modelMetrics.length,
      );
    } catch (e) {
      SDKLogger('RunAnywhere.Storage').error('Failed to get storage info: $e');
      return StorageInfo();
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

        storedModels.add(StoredModel(
          modelId: model.id,
          name: model.name,
          sizeBytes: Int64(fileSize),
          localPath: localPath,
        ));
      }

      return storedModels;
    } catch (e) {
      SDKLogger('RunAnywhere.Storage')
          .error('Failed to get downloaded models: $e');
      return [];
    }
  }

  // -- private helpers ------------------------------------------------------

  Future<DeviceStorageInfo> _getDeviceStorageInfo() async {
    try {
      final modelsDir = DartBridgeModelPaths.instance.getModelsDirectory();
      if (modelsDir == null) {
        return DeviceStorageInfo(
          totalBytes: Int64.ZERO,
          freeBytes: Int64.ZERO,
          usedBytes: Int64.ZERO,
        );
      }
      final modelsDirSize = await _getDirectorySize(modelsDir);
      return DeviceStorageInfo(
        totalBytes: Int64(modelsDirSize),
        freeBytes: Int64.ZERO,
        usedBytes: Int64(modelsDirSize),
      );
    } catch (e) {
      return DeviceStorageInfo(
        totalBytes: Int64.ZERO,
        freeBytes: Int64.ZERO,
        usedBytes: Int64.ZERO,
      );
    }
  }

  Future<AppStorageInfo> _getAppStorageInfo() async {
    try {
      final modelsDir = DartBridgeModelPaths.instance.getModelsDirectory();
      final modelsDirSize =
          modelsDir != null ? await _getDirectorySize(modelsDir) : 0;
      return AppStorageInfo(
        documentsBytes: Int64(modelsDirSize),
        cacheBytes: Int64.ZERO,
        appSupportBytes: Int64.ZERO,
        totalBytes: Int64(modelsDirSize),
      );
    } catch (e) {
      return AppStorageInfo(
        documentsBytes: Int64.ZERO,
        cacheBytes: Int64.ZERO,
        appSupportBytes: Int64.ZERO,
        totalBytes: Int64.ZERO,
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
      case InferenceFramework.sherpa:
        return 12;
      case InferenceFramework.unknown:
        return 99;
    }
  }
}
