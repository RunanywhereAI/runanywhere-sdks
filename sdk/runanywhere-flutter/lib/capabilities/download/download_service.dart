import 'dart:async';

import 'package:http/http.dart' as http;

import '../../core/models/model/model_info.dart';
import '../../core/protocols/registry/model_registry.dart';
import '../../core/protocols/downloading/download_manager.dart';
import '../../core/protocols/downloading/download_progress.dart' as proto;
import '../../core/protocols/downloading/download_state.dart';
import '../../core/protocols/downloading/download_task.dart' as proto;
import '../../core/protocols/downloading/download_strategy.dart';
import '../../foundation/file_operations/model_path_utils.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../../foundation/error_types/sdk_error.dart';
import '../registry/registry_service.dart' hide ModelRegistry;

/// Service for downloading models with progress tracking
/// Matches iOS AlamofireDownloadService pattern
/// Implements DownloadManager protocol from Core/Protocols/Downloading/DownloadManager
class DownloadService implements DownloadManager {
  final ModelRegistry modelRegistry;
  final SDKLogger logger = SDKLogger(category: 'DownloadService');
  final Map<String, _DownloadTaskImpl> _activeDownloads = {};
  final List<DownloadStrategy> _customStrategies = [];

  DownloadService({required this.modelRegistry});

  /// Register a custom download strategy
  /// Matches iOS pattern for registering custom strategies
  void registerStrategy(DownloadStrategy strategy) {
    _customStrategies.add(strategy);
    logger.info('Registered custom download strategy');
  }

  /// Find a strategy that can handle this model
  DownloadStrategy? _findStrategy(ModelInfo model) {
    for (final strategy in _customStrategies) {
      if (strategy.canHandle(model)) {
        return strategy;
      }
    }
    return null;
  }

  /// Download a model with progress tracking
  /// Implements DownloadManager.downloadModel
  @override
  Future<proto.DownloadTask> downloadModel(ModelInfo model) async {
    // Check if already downloaded
    if (model.isDownloaded) {
      logger.info('Model ${model.id} is already downloaded');
      return _createCompletedTask(model);
    }

    // Check if download is already in progress
    if (_activeDownloads.containsKey(model.id)) {
      logger.info('Download already in progress for model: ${model.id}');
      return _activeDownloads[model.id]!.toProtocolTask();
    }

    // Check if download URL is available
    if (model.downloadURL == null) {
      throw SDKError.modelNotFound('Model ${model.id} has no download URL');
    }

    // Try to find a custom strategy for this model
    final strategy = _findStrategy(model);
    if (strategy != null) {
      logger.info('Using custom download strategy for model: ${model.id}');
      return _downloadWithStrategy(model, strategy);
    }

    // Create download task using default strategy
    final task = _createDownloadTask(model);
    _activeDownloads[model.id] = task;

    // Start download
    unawaited(_performDownload(model, task));

    return task.toProtocolTask();
  }

  /// Download using a custom strategy
  Future<proto.DownloadTask> _downloadWithStrategy(
    ModelInfo model,
    DownloadStrategy strategy,
  ) async {
    final controller = StreamController<proto.DownloadProgress>.broadcast();
    final completer = Completer<Uri>();

    final task = _DownloadTaskImpl(
      id: model.id,
      modelId: model.id,
      progressController: controller,
      resultCompleter: completer,
    );

    _activeDownloads[model.id] = task;

    try {
      // Get destination folder using ModelPathUtils
      final modelFolder = await ModelPathUtils.getModelFolder(
        modelId: model.id,
        framework: model.preferredFramework!,
      );

      // Download using strategy
      final destinationUri = await strategy.download(
        model: model,
        destinationFolder: modelFolder.uri,
        progressHandler: (progress) {
          controller.add(proto.DownloadProgress.downloading(
            bytesDownloaded: (progress * 100).toInt(),
            totalBytes: 100,
          ));
        },
      );

      // Update model with local path
      final updatedModel = model.copyWith(localPath: destinationUri);
      (modelRegistry as RegistryService).updateModel(updatedModel);

      // Complete task
      controller.add(proto.DownloadProgress.completed(totalBytes: 100));
      completer.complete(destinationUri);
      await controller.close();
      _activeDownloads.remove(model.id);

      logger.info('Model ${model.id} downloaded successfully via strategy');
      logger.debug('Downloaded to: ${destinationUri.toFilePath()}');
      logger.debug(
          'Updated model localPath: ${updatedModel.localPath?.toFilePath()}');
      return task.toProtocolTask();
    } catch (e) {
      controller.add(proto.DownloadProgress.failed(e));
      completer.completeError(e);
      await controller.close();
      _activeDownloads.remove(model.id);
      logger.error('Strategy download failed for model ${model.id}: $e');
      return task.toProtocolTask();
    }
  }

  /// Create a download task
  _DownloadTaskImpl _createDownloadTask(ModelInfo model) {
    final controller = StreamController<proto.DownloadProgress>.broadcast();
    final completer = Completer<Uri>();

    return _DownloadTaskImpl(
      id: model.id,
      modelId: model.id,
      progressController: controller,
      resultCompleter: completer,
      onCancel: () {
        controller.close();
        _activeDownloads.remove(model.id);
      },
    );
  }

  /// Create a completed task for already downloaded models
  proto.DownloadTask _createCompletedTask(ModelInfo model) {
    final controller = StreamController<proto.DownloadProgress>.broadcast();
    final localPath = model.localPath ?? Uri.file('');

    controller.add(proto.DownloadProgress.completed(totalBytes: 0));
    controller.close();

    return proto.DownloadTask(
      id: model.id,
      modelId: model.id,
      progress: controller.stream,
      result: Future.value(localPath),
    );
  }

  /// Perform the actual download (default strategy)
  /// Uses ModelPathUtils for consistent path management
  Future<void> _performDownload(ModelInfo model, _DownloadTaskImpl task) async {
    final startTime = DateTime.now();
    int bytesDownloaded = 0;

    try {
      final url = model.downloadURL!;
      final request = http.Request('GET', url);
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw SDKError.downloadFailed(
          url.toString(),
          'Download failed with status ${response.statusCode}',
        );
      }

      final totalBytes = response.contentLength ?? 0;

      // Use ModelPathUtils for consistent path management (matching iOS)
      final modelFile = await ModelPathUtils.getModelFilePath(
        modelId: model.id,
        framework: model.preferredFramework!,
        format: model.format,
      );

      // Ensure parent directory exists
      await modelFile.parent.create(recursive: true);

      final sink = modelFile.openWrite();

      // Stream response and track progress
      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesDownloaded = (bytesDownloaded + chunk.length).toInt();

        // Calculate speed and ETA
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        final speed =
            elapsed > 0 ? (bytesDownloaded / elapsed) * 1000 : null; // bytes/s
        final remaining = totalBytes - bytesDownloaded;
        final eta =
            speed != null && speed > 0 ? remaining / speed : null; // seconds

        task.progressController.add(proto.DownloadProgress.downloading(
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
          speed: speed,
          estimatedTimeRemaining: eta,
        ));
      }

      await sink.close();

      // Handle archive extraction if needed
      final needsExtraction =
          model.format.rawValue == 'tar.bz2' || model.format.rawValue == 'zip';

      if (needsExtraction) {
        task.progressController.add(proto.DownloadProgress(
          bytesDownloaded: totalBytes,
          totalBytes: totalBytes,
          state: const DownloadStateExtracting(),
        ));

        // TODO: Implement archive extraction using native backend
        // For now, mark as completed without extraction
        logger.warning(
            'Archive extraction not yet implemented for ${model.format.rawValue}');
      }

      // Update model with local path
      final updatedModel = model.copyWith(
        localPath: modelFile.uri,
      );

      (modelRegistry as RegistryService).updateModel(updatedModel);

      // Complete task
      task.progressController.add(proto.DownloadProgress.completed(
        totalBytes: totalBytes,
      ));

      task.resultCompleter.complete(modelFile.uri);
      await task.progressController.close();
      _activeDownloads.remove(model.id);

      logger.info(
          'Model ${model.id} downloaded successfully to ${modelFile.path}');
      logger.debug('Downloaded to: ${modelFile.path}');
      logger.debug(
          'Updated model localPath: ${updatedModel.localPath?.toFilePath()}');
    } catch (e) {
      task.progressController.add(proto.DownloadProgress.failed(
        e,
        bytesDownloaded: bytesDownloaded,
      ));
      task.resultCompleter.completeError(e);
      await task.progressController.close();
      _activeDownloads.remove(model.id);
      logger.error('Download failed for model ${model.id}: $e');
    }
  }

  /// Cancel a download
  /// Implements DownloadManager.cancelDownload
  @override
  void cancelDownload(String taskId) {
    final task = _activeDownloads[taskId];
    if (task != null) {
      task.onCancel?.call();
      task.progressController.add(const proto.DownloadProgress(
        bytesDownloaded: 0,
        totalBytes: 0,
        state: DownloadStateCancelled(),
      ));
      _activeDownloads.remove(taskId);
      logger.info('Download cancelled for model: $taskId');
    }
  }

  /// Get active download tasks
  /// Implements DownloadManager.activeDownloads
  @override
  List<proto.DownloadTask> activeDownloads() {
    return _activeDownloads.values.map((t) => t.toProtocolTask()).toList();
  }

  /// Get active download task by model ID (internal use)
  /// Returns the internal task implementation for advanced use cases
  Object? getActiveDownload(String modelId) {
    return _activeDownloads[modelId];
  }

  /// Check if a download is in progress
  bool isDownloading(String modelId) {
    return _activeDownloads.containsKey(modelId);
  }

  /// Delete a downloaded model
  /// Uses ModelPathUtils for consistent path management
  Future<bool> deleteModel(ModelInfo model) async {
    try {
      await ModelPathUtils.deleteModel(model);
      // Update model to remove local path
      final updatedModel = model.copyWith(localPath: null);
      (modelRegistry as RegistryService).updateModel(updatedModel);
      logger.info('Model ${model.id} deleted successfully');
      return true;
    } catch (e) {
      logger.error('Failed to delete model ${model.id}: $e');
      return false;
    }
  }

  /// Check if a model file exists
  /// Uses ModelPathUtils for consistent path management
  Future<bool> isModelFileAvailable(ModelInfo model) async {
    return ModelPathUtils.modelExists(model);
  }
}

/// Internal download task implementation
class _DownloadTaskImpl {
  final String id;
  final String modelId;
  final StreamController<proto.DownloadProgress> progressController;
  final Completer<Uri> resultCompleter;
  final void Function()? onCancel;

  _DownloadTaskImpl({
    required this.id,
    required this.modelId,
    required this.progressController,
    required this.resultCompleter,
    this.onCancel,
  });

  /// Convert to protocol DownloadTask
  proto.DownloadTask toProtocolTask() {
    return proto.DownloadTask(
      id: id,
      modelId: modelId,
      progress: progressController.stream,
      result: resultCompleter.future,
    );
  }
}
