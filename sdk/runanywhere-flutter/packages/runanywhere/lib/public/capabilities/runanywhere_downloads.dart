// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_downloads.dart — v4 Downloads capability. Owns model
// download lifecycle, delete, and storage inspection.

import 'dart:io';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/component_types.pbenum.dart';
import 'package:runanywhere/generated/download_service.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart' show ModelInfo;
import 'package:runanywhere/generated/sdk_events.pb.dart' as sdk_events;
import 'package:runanywhere/generated/storage_types.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_download.dart';
import 'package:runanywhere/native/dart_bridge_events.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
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

  /// Plan a download and retry once after clearing oversize partial bytes.
  ///
  /// Mirrors Swift `RunAnywhere+Storage.planDownload(_:)`: when a prior
  /// interrupted download left more bytes on disk than the new plan expects
  /// (e.g. the server reported a smaller Content-Length after a CDN swap),
  /// delete the oversize partials and re-plan instead of surfacing
  /// `existing partial bytes exceed` to the caller as a hard error.
  Future<DownloadPlanResult> _planWithSelfHeal(
    DownloadPlanRequest request,
  ) async {
    final planResult = await plan(request);
    if (planResult.canStart ||
        !planResult.errorMessage.contains('existing partial bytes exceed')) {
      return planResult;
    }

    final logger = SDKLogger('RunAnywhere.Download');
    for (final file in planResult.files) {
      final destinationPath = file.destinationPath;
      if (destinationPath.isEmpty) continue;
      final partial = File(destinationPath);
      if (partial.existsSync()) {
        try {
          partial.deleteSync();
          logger.warning(
            'Removed oversize partial download at $destinationPath '
            'for ${request.modelId}',
          );
        } catch (e) {
          logger.warning(
            'Failed to remove oversize partial download at $destinationPath '
            'for ${request.modelId}: $e',
          );
        }
      }
    }

    return plan(request);
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

    final planResult = await _planWithSelfHeal(DownloadPlanRequest(
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

    // Subscribe BEFORE starting so we don't lose early native callbacks.
    // Filter the process-wide stream down to this model id.
    final progressStream = DartBridgeDownload.instance.progressStream
        .where((p) => p.modelId == modelId);

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

    logger.info(
      'Download accepted for $modelId (task=${startResult.taskId})',
    );

    if (startResult.hasInitialProgress()) {
      yield startResult.initialProgress;
      if (_isTerminalState(startResult.initialProgress.state)) {
        if (startResult.initialProgress.state ==
            DownloadState.DOWNLOAD_STATE_COMPLETED) {
          await _handleDownloadCompleted(startResult.initialProgress, logger);
        }
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
          if (progress.state == DownloadState.DOWNLOAD_STATE_COMPLETED) {
            await _handleDownloadCompleted(progress, logger);
          }
          break;
        }
      }
    } finally {
      if (!reachedTerminal) {
        try {
          await DartBridgeDownload.instance.cancelProto(DownloadCancelRequest(
            modelId: modelId,
            taskId: startResult.taskId,
            deletePartialBytes: false,
          ));
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

  Future<void> _handleDownloadCompleted(
    DownloadProgress progress,
    SDKLogger logger,
  ) async {
    var localPath = progress.localPath;

    try {
      await RunAnywhereModels.shared.refreshModelRegistry();
      final model = await DartBridgeModelRegistry.instance
          .getProtoModel(progress.modelId);
      if (model != null && model.localPath.isNotEmpty) {
        localPath = model.localPath;
      }
    } catch (e) {
      logger.warning(
        'Failed to refresh model registry after download: $e',
      );
    }

    DartBridgeEvents.instance.emit(sdk_events.SDKEvent(
      timestampMs: fixnum.Int64(DateTime.now().millisecondsSinceEpoch),
      category: EventCategory.EVENT_CATEGORY_MODEL,
      source: 'flutter.downloads',
      model: sdk_events.ModelEvent(
        kind: sdk_events.ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED,
        modelId: progress.modelId,
        taskId: progress.taskId,
        progress: _completedProgress(progress),
        bytesDownloaded: progress.bytesDownloaded,
        totalBytes: progress.totalBytes,
        downloadState: progress.state.name,
        localPath: localPath,
      ),
    ));
  }

  static double _completedProgress(DownloadProgress progress) {
    if (progress.overallProgress > 0) return progress.overallProgress;
    if (progress.stageProgress > 0) return progress.stageProgress;
    return 1;
  }

  /// Cancel an active model download if the adapter still owns it.
  Future<DownloadCancelResult> cancelDownload(String modelId) async {
    if (!DartBridge.isInitialized) {
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

    return DartBridgeStorage.instance.deleteProto(StorageDeleteRequest(
      modelIds: [modelId],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
    ));
  }

  /// Delete every downloaded model while keeping registry entries available.
  Future<StorageDeleteResult> deleteAllModels() async {
    if (!DartBridge.isInitialized) {
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
    if (!DartBridge.isInitialized) {
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
