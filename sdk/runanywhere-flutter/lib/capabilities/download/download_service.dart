import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/models/model/model_info.dart';
import '../../core/protocols/registry/model_registry.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../../foundation/error_types/sdk_error.dart';
import '../registry/registry_service.dart' hide ModelRegistry;

/// Service for downloading models with progress tracking
class DownloadService {
  final ModelRegistry modelRegistry;
  final SDKLogger logger = SDKLogger(category: 'DownloadService');
  final Map<String, DownloadTask> _activeDownloads = {};

  DownloadService({required this.modelRegistry});

  /// Download a model with progress tracking
  Future<DownloadTask> downloadModel(ModelInfo model) async {
    // Check if already downloaded
    if (model.isDownloaded) {
      logger.info('Model ${model.id} is already downloaded');
      return DownloadTask.completed(
        model.id,
        model.localPath?.toFilePath() ?? '',
      );
    }

    // Check if download is already in progress
    if (_activeDownloads.containsKey(model.id)) {
      logger.info('Download already in progress for model: ${model.id}');
      return _activeDownloads[model.id]!;
    }

    // Check if download URL is available
    if (model.downloadURL == null) {
      throw SDKError.modelNotFound('Model ${model.id} has no download URL');
    }

    // Create download task
    final task = _createDownloadTask(model);
    _activeDownloads[model.id] = task;

    // Start download
    unawaited(_performDownload(model, task));

    return task;
  }

  /// Create a download task
  DownloadTask _createDownloadTask(ModelInfo model) {
    final controller = StreamController<DownloadProgress>();
    final completer = Completer<String>();

    return DownloadTask(
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

  /// Perform the actual download
  Future<void> _performDownload(ModelInfo model, DownloadTask task) async {
    try {
      final url = model.downloadURL!;
      final request = http.Request('GET', url);
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw SDKError.downloadFailed(
          'Download failed with status ${response.statusCode}',
        );
      }

      final totalBytes = response.contentLength ?? 0;
      int bytesDownloaded = 0;

      // Get destination directory
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${appDir.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final fileExtension = model.format.rawValue;
      final destinationPath = '${modelsDir.path}/${model.id}.$fileExtension';
      final file = File(destinationPath);
      final sink = file.openWrite();

      // Stream response and track progress
      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesDownloaded = (bytesDownloaded + chunk.length).toInt();

        task.progressController.add(DownloadProgress(
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
          state: DownloadState.downloading,
        ));
      }

      await sink.close();

      // Update model with local path
      final updatedModel = model.copyWith(
        localPath: Uri.file(destinationPath),
      );

      (modelRegistry as RegistryService).updateModel(updatedModel);

      // Complete task
      task.progressController.add(DownloadProgress(
        bytesDownloaded: totalBytes,
        totalBytes: totalBytes,
        state: DownloadState.completed,
      ));

      task.resultCompleter.complete(destinationPath);
      unawaited(task.progressController.close());
      _activeDownloads.remove(model.id);

      logger.info('Model ${model.id} downloaded successfully');
    } catch (e) {
      task.progressController.add(DownloadProgress(
        bytesDownloaded: 0,
        totalBytes: 0,
        state: DownloadState.failed,
        error: e.toString(),
      ));
      task.resultCompleter.completeError(e);
      unawaited(task.progressController.close());
      _activeDownloads.remove(model.id);
      logger.error('Download failed for model ${model.id}: $e');
    }
  }

  /// Cancel a download
  Future<void> cancelDownload(String modelId) async {
    final task = _activeDownloads[modelId];
    if (task != null) {
      task.onCancel?.call();
      _activeDownloads.remove(modelId);
      logger.info('Download cancelled for model: $modelId');
    }
  }
}

/// Download task with progress tracking
class DownloadTask {
  final String id;
  final String modelId;
  final StreamController<DownloadProgress> progressController;
  final Completer<String> resultCompleter;
  final void Function()? onCancel;

  DownloadTask({
    required this.id,
    required this.modelId,
    required this.progressController,
    required this.resultCompleter,
    this.onCancel,
  });

  Stream<DownloadProgress> get progress => progressController.stream;
  Future<String> get result => resultCompleter.future;

  /// Create a completed task (for already downloaded models)
  factory DownloadTask.completed(String modelId, String localPath) {
    final controller = StreamController<DownloadProgress>();
    final completer = Completer<String>();

    controller.add(DownloadProgress(
      bytesDownloaded: 0,
      totalBytes: 0,
      state: DownloadState.completed,
    ));
    completer.complete(localPath);
    controller.close();

    return DownloadTask(
      id: modelId,
      modelId: modelId,
      progressController: controller,
      resultCompleter: completer,
    );
  }
}

/// Download progress information
class DownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final DownloadState state;
  final String? error;
  final double? speed; // bytes per second
  final Duration? estimatedTimeRemaining;

  DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.state,
    this.error,
    this.speed,
    this.estimatedTimeRemaining,
  });

  double get progress => totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;
}

enum DownloadState {
  downloading,
  completed,
  failed,
  cancelled,
}
