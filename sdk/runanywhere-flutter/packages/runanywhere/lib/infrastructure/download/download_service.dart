import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/runanywhere.dart';

/// Download progress information
class ModelDownloadProgress {
  final String modelId;
  final int bytesDownloaded;
  final int totalBytes;
  final ModelDownloadStage stage;
  final double overallProgress;
  final String? error;

  const ModelDownloadProgress({
    required this.modelId,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.stage,
    required this.overallProgress,
    this.error,
  });

  factory ModelDownloadProgress.started(String modelId, int totalBytes) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: totalBytes,
        stage: ModelDownloadStage.downloading,
        overallProgress: 0,
      );

  factory ModelDownloadProgress.downloading(
    String modelId,
    int downloaded,
    int total,
  ) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: downloaded,
        totalBytes: total,
        stage: ModelDownloadStage.downloading,
        overallProgress: total > 0 ? downloaded / total * 0.9 : 0,
      );

  factory ModelDownloadProgress.extracting(String modelId) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.extracting,
        overallProgress: 0.92,
      );

  factory ModelDownloadProgress.completed(String modelId) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.completed,
        overallProgress: 1.0,
      );

  factory ModelDownloadProgress.failed(String modelId, String error) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.failed,
        overallProgress: 0,
        error: error,
      );
}

/// Download stages
enum ModelDownloadStage {
  downloading,
  extracting,
  verifying,
  completed,
  failed,
  cancelled;

  bool get isCompleted => this == ModelDownloadStage.completed;
  bool get isFailed => this == ModelDownloadStage.failed;
}

/// Model download service - handles actual file downloads
class ModelDownloadService {
  static final ModelDownloadService shared = ModelDownloadService._();
  ModelDownloadService._();

  final _logger = SDKLogger('ModelDownloadService');
  final Map<String, http.Client> _activeDownloads = {};

  /// Download a model by ID
  ///
  /// Returns a stream of download progress updates.
  Stream<ModelDownloadProgress> downloadModel(String modelId) async* {
    _logger.info('Starting download for model: $modelId');

    // Find the model
    final models = await RunAnywhere.availableModels();
    final model = models.where((m) => m.id == modelId).firstOrNull;

    if (model == null) {
      _logger.error('Model not found: $modelId');
      yield ModelDownloadProgress.failed(modelId, 'Model not found: $modelId');
      return;
    }

    if (model.downloadURL == null) {
      _logger.error('Model has no download URL: $modelId');
      yield ModelDownloadProgress.failed(
          modelId, 'Model has no download URL: $modelId');
      return;
    }

    // Emit download started event
    EventBus.shared.publish(SDKModelEvent.downloadStarted(modelId: modelId));

    try {
      // Get destination directory
      final destDir = await _getModelDirectory(model);
      await destDir.create(recursive: true);
      _logger.info('Download destination: ${destDir.path}');

      // Determine if extraction is needed
      final requiresExtraction = model.artifactType.requiresExtraction;
      _logger.info('Requires extraction: $requiresExtraction');

      // Determine the download file name
      final downloadUrl = model.downloadURL!;
      final fileName = p.basename(downloadUrl.path);
      final downloadPath = p.join(destDir.path, fileName);

      // Create HTTP client
      final client = http.Client();
      _activeDownloads[modelId] = client;

      try {
        // Send HEAD request to get content length
        final headResponse = await client.head(downloadUrl);
        final totalBytes =
            int.tryParse(headResponse.headers['content-length'] ?? '0') ??
                model.downloadSize ??
                0;

        _logger.info('Total bytes to download: $totalBytes');
        yield ModelDownloadProgress.started(modelId, totalBytes);

        // Start download
        final request = http.Request('GET', downloadUrl);
        final response = await client.send(request);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
              'HTTP ${response.statusCode}: ${response.reasonPhrase}');
        }

        // Download with progress tracking
        final file = File(downloadPath);
        final sink = file.openWrite();
        var downloaded = 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;

          yield ModelDownloadProgress.downloading(
            modelId,
            downloaded,
            totalBytes > 0 ? totalBytes : downloaded,
          );
        }

        await sink.flush();
        await sink.close();

        _logger.info('Download complete: ${file.path}');

        // Handle extraction if needed
        String finalModelPath = downloadPath;
        if (requiresExtraction) {
          yield ModelDownloadProgress.extracting(modelId);

          final extractedPath = await _extractArchive(
            downloadPath,
            destDir.path,
            model.artifactType,
          );
          finalModelPath = extractedPath;

          // Clean up archive file after extraction
          try {
            await File(downloadPath).delete();
          } catch (e) {
            _logger.warning('Failed to delete archive: $e');
          }
        }

        // Update model's local path
        await _updateModelLocalPath(model, finalModelPath);

        // Emit completion
        EventBus.shared.publish(SDKModelEvent.downloadCompleted(
          modelId: modelId,
        ));

        yield ModelDownloadProgress.completed(modelId);
        _logger.info('Model download completed: $modelId -> $finalModelPath');
      } finally {
        client.close();
        _activeDownloads.remove(modelId);
      }
    } catch (e, stack) {
      _logger
          .error('Download failed: $e', metadata: {'stack': stack.toString()});
      EventBus.shared.publish(SDKModelEvent.downloadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      yield ModelDownloadProgress.failed(modelId, e.toString());
    }
  }

  /// Cancel an active download
  void cancelDownload(String modelId) {
    final client = _activeDownloads[modelId];
    if (client != null) {
      client.close();
      _activeDownloads.remove(modelId);
      _logger.info('Download cancelled: $modelId');
    }
  }

  /// Get the model storage directory.
  /// Uses C++ path functions to ensure consistency with discovery.
  /// Matches Swift: CppBridge.ModelPaths.getModelFolder()
  Future<Directory> _getModelDirectory(ModelInfo model) async {
    // Use C++ path functions - this creates the directory if needed
    final modelPath =
        await DartBridgeModelPaths.instance.getModelFolderAndCreate(
      model.id,
      model.framework,
    );
    return Directory(modelPath);
  }

  /// Extract an archive to the destination
  Future<String> _extractArchive(
    String archivePath,
    String destDir,
    ModelArtifactType artifactType,
  ) async {
    _logger.info('Extracting archive: $archivePath');

    final archiveFile = File(archivePath);
    final bytes = await archiveFile.readAsBytes();

    Archive? archive;

    // Determine archive type
    if (archivePath.endsWith('.tar.gz') || archivePath.endsWith('.tgz')) {
      final gzDecoded = GZipDecoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(gzDecoded);
    } else if (archivePath.endsWith('.tar.bz2') ||
        archivePath.endsWith('.tbz2')) {
      final bz2Decoded = BZip2Decoder().decodeBytes(bytes);
      archive = TarDecoder().decodeBytes(bz2Decoded);
    } else if (archivePath.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (archivePath.endsWith('.tar')) {
      archive = TarDecoder().decodeBytes(bytes);
    } else {
      _logger.warning('Unknown archive format: $archivePath');
      return archivePath;
    }

    // Extract files
    String? rootDir;
    for (final file in archive) {
      final filePath = p.join(destDir, file.name);

      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        _logger.debug('Extracted: ${file.name}');

        // Track root directory
        final parts = file.name.split('/');
        if (parts.isNotEmpty && rootDir == null) {
          rootDir = parts.first;
        }
      } else {
        await Directory(filePath).create(recursive: true);
      }
    }

    _logger.info('Extraction complete: $destDir');

    // Return the model directory (could be a nested directory)
    if (rootDir != null) {
      final nestedPath = p.join(destDir, rootDir);
      if (await Directory(nestedPath).exists()) {
        return nestedPath;
      }
    }

    return destDir;
  }

  /// Update model's local path after download
  Future<void> _updateModelLocalPath(ModelInfo model, String path) async {
    model.localPath = Uri.file(path);
    _logger.info('Updated model local path: ${model.id} -> $path');

    // Also update the C++ registry so model is discoverable
    await _updateModelRegistry(model.id, path);
  }

  /// Update the C++ model registry (for persistence across app restarts)
  Future<void> _updateModelRegistry(String modelId, String path) async {
    try {
      // Update the C++ registry so model is discoverable
      // Matches Swift: CppBridge.ModelRegistry.shared.updateDownloadStatus()
      await RunAnywhere.updateModelDownloadStatus(modelId, path);
    } catch (e) {
      _logger.debug('Could not update C++ registry: $e');
    }
  }
}
