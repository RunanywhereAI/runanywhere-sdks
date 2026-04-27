import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/runanywhere.dart';

typedef DownloadHttpClientFactory = Future<http.Client> Function(Uri url);

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException(this.modelId);

  final String modelId;

  @override
  String toString() => 'Download cancelled for model: $modelId';
}

int _estimatePerFileDownloadSize(int? totalModelBytes, int totalFiles) {
  if (totalModelBytes == null || totalModelBytes <= 0 || totalFiles <= 0) {
    return 0;
  }
  return (totalModelBytes / totalFiles).ceil();
}

double _calculateOverallMultiFileDownloadProgress({
  required int cumulativeDownloadedBytes,
  required int downloadedBytesForCurrentFile,
  required int totalModelBytes,
  required int completedFiles,
  required int totalFiles,
  required int currentFileSizeEstimate,
}) {
  if (totalModelBytes <= 0) {
    if (totalFiles <= 0) {
      return 0;
    }

    final currentFileProgress = currentFileSizeEstimate > 0
        ? (downloadedBytesForCurrentFile / currentFileSizeEstimate)
            .clamp(0.0, 1.0)
        : 0.0;
    return ((completedFiles + currentFileProgress) / totalFiles)
        .clamp(0.0, 1.0);
  }

  return ((cumulativeDownloadedBytes + downloadedBytesForCurrentFile) /
          totalModelBytes)
      .clamp(0.0, 1.0);
}

@visibleForTesting
int estimatePerFileDownloadSizeForTesting({
  required int? totalModelBytes,
  required int totalFiles,
}) {
  return _estimatePerFileDownloadSize(totalModelBytes, totalFiles);
}

@visibleForTesting
double calculateOverallMultiFileDownloadProgressForTesting({
  required int cumulativeDownloadedBytes,
  required int downloadedBytesForCurrentFile,
  required int totalModelBytes,
  required int completedFiles,
  required int totalFiles,
  required int currentFileSizeEstimate,
}) {
  return _calculateOverallMultiFileDownloadProgress(
    cumulativeDownloadedBytes: cumulativeDownloadedBytes,
    downloadedBytesForCurrentFile: downloadedBytesForCurrentFile,
    totalModelBytes: totalModelBytes,
    completedFiles: completedFiles,
    totalFiles: totalFiles,
    currentFileSizeEstimate: currentFileSizeEstimate,
  );
}

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

  factory ModelDownloadProgress.cancelled(String modelId) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.cancelled,
        overallProgress: 0,
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
  final Set<String> _cancelledDownloads = <String>{};
  DownloadHttpClientFactory? _clientFactory;

  void configureClientFactory(DownloadHttpClientFactory? factory) {
    _clientFactory = factory;
  }

  Future<http.Client> _createClient(Uri url) async {
    if (_clientFactory != null) {
      return _clientFactory!(url);
    }
    return http.Client();
  }

  void _throwIfCancelled(String modelId) {
    if (_cancelledDownloads.contains(modelId)) {
      throw _DownloadCancelledException(modelId);
    }
  }

  /// Download a model by ID
  ///
  /// Returns a stream of download progress updates.
  Stream<ModelDownloadProgress> downloadModel(String modelId) async* {
    _logger.info('Starting download for model: $modelId');
    _cancelledDownloads.remove(modelId);

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

      // Handle multi-file models (e.g. embedding model + vocab.txt)
      if (model.artifactType is MultiFileArtifact) {
        final multiFile = model.artifactType as MultiFileArtifact;

        try {
          final totalFiles = multiFile.files.length;
          final totalModelBytes = model.downloadSize ?? 0;
          final estimatedPerFileSize =
              _estimatePerFileDownloadSize(model.downloadSize, totalFiles);
          var cumulativeDownloaded = 0;
          _logger.info('Multi-file model: downloading $totalFiles files');
          yield ModelDownloadProgress.started(modelId, totalModelBytes);

          for (var i = 0; i < multiFile.files.length; i++) {
            _throwIfCancelled(modelId);
            final descriptor = multiFile.files[i];
            final fileUrl = descriptor.url;
            if (fileUrl == null) {
              _logger.warning(
                  'No URL for file descriptor: ${descriptor.destinationPath}');
              continue;
            }

            final destPath = p.join(destDir.path, descriptor.destinationPath);
            _logger.info(
                'Downloading file ${i + 1}/$totalFiles: ${descriptor.destinationPath}');

            final client = await _createClient(fileUrl);
            _activeDownloads[modelId] = client;
            final request = http.Request('GET', fileUrl);
            try {
              _throwIfCancelled(modelId);
              final response = await client.send(request);

              if (response.statusCode < 200 || response.statusCode >= 300) {
                throw Exception(
                    'HTTP ${response.statusCode} for ${descriptor.destinationPath}');
              }

              final file = File(destPath);
              await file.create(recursive: true);
              final sink = file.openWrite();
              final currentFileSizeEstimate = (response.contentLength ?? 0) > 0
                  ? response.contentLength!
                  : estimatedPerFileSize;
              var downloaded = 0;
              var completedSuccessfully = false;

              try {
                await for (final chunk in response.stream) {
                  _throwIfCancelled(modelId);
                  sink.add(chunk);
                  downloaded += chunk.length;

                  final overallProgress =
                      _calculateOverallMultiFileDownloadProgress(
                    cumulativeDownloadedBytes: cumulativeDownloaded,
                    downloadedBytesForCurrentFile: downloaded,
                    totalModelBytes: totalModelBytes,
                    completedFiles: i,
                    totalFiles: totalFiles,
                    currentFileSizeEstimate: currentFileSizeEstimate,
                  );
                  yield ModelDownloadProgress(
                    modelId: modelId,
                    bytesDownloaded: cumulativeDownloaded + downloaded,
                    totalBytes: totalModelBytes,
                    stage: ModelDownloadStage.downloading,
                    overallProgress: overallProgress * 0.9,
                  );
                }

                await sink.flush();
                cumulativeDownloaded += downloaded;
                completedSuccessfully = true;
                _logger.info('Downloaded: ${descriptor.destinationPath}');
              } finally {
                await sink.close();
                if (!completedSuccessfully) {
                  try {
                    if (await file.exists()) {
                      await file.delete();
                    }
                  } catch (e) {
                    _logger.warning(
                      'Failed to clean up partial file $destPath: $e',
                    );
                  }
                }
              }
            } finally {
              client.close();
            }
          }
        } finally {
          _activeDownloads.remove(modelId);
        }

        // Local path is the directory containing all files
        await _updateModelLocalPath(model, destDir.path);
        EventBus.shared
            .publish(SDKModelEvent.downloadCompleted(modelId: modelId));
        yield ModelDownloadProgress.completed(modelId);
        _logger.info(
            'Multi-file model download completed: $modelId -> ${destDir.path}');
        return;
      }

      // Single-file / archive download
      // Determine if extraction is needed
      final requiresExtraction = model.artifactType.requiresExtraction;
      _logger.info('Requires extraction: $requiresExtraction');

      // Determine the download file name
      final downloadUrl = model.downloadURL!;
      final fileName = p.basename(downloadUrl.path);
      final downloadPath = p.join(destDir.path, fileName);

      // Create HTTP client
      final client = await _createClient(downloadUrl);
      _activeDownloads[modelId] = client;

      try {
        // Send HEAD request to get content length
        _throwIfCancelled(modelId);
        final headResponse = await client.head(downloadUrl);
        final totalBytes =
            int.tryParse(headResponse.headers['content-length'] ?? '0') ??
                model.downloadSize ??
                0;

        _logger.info('Total bytes to download: $totalBytes');
        yield ModelDownloadProgress.started(modelId, totalBytes);

        // Start download
        _throwIfCancelled(modelId);
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
          _throwIfCancelled(modelId);
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

          // Snapshot items before extraction to detect new entries
          final itemsBefore = await destDir.list().map((e) => e.path).toSet();

          final extractedPath = await _extractArchive(
            downloadPath,
            destDir.path,
            framework: model.framework,
            format: model.format,
          );

          // Clean up archive file after extraction
          try {
            await File(downloadPath).delete();
          } catch (e) {
            _logger.warning('Failed to delete archive: $e');
          }

          // Resolve the extracted model path using the snapshot
          finalModelPath = await _resolveExtractedModelPath(
            destDir.path,
            modelId,
            itemsBefore,
            extractedPath,
          );
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
    } on _DownloadCancelledException {
      _logger.info('Download cancelled: $modelId');
      yield ModelDownloadProgress.cancelled(modelId);
    } catch (e, stack) {
      _logger
          .error('Download failed: $e', metadata: {'stack': stack.toString()});
      EventBus.shared.publish(SDKModelEvent.downloadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      yield ModelDownloadProgress.failed(modelId, e.toString());
    } finally {
      _activeDownloads.remove(modelId);
      _cancelledDownloads.remove(modelId);
    }
  }

  /// Cancel an active download
  void cancelDownload(String modelId) {
    _cancelledDownloads.add(modelId);
    final client = _activeDownloads[modelId];
    if (client != null) {
      client.close();
    }
    _logger.info('Download cancel requested: $modelId');
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

  /// Extract an archive to the destination using native C++ (libarchive).
  /// Supports ZIP, TAR.GZ, TAR.BZ2, TAR.XZ with auto-detection.
  Future<String> _extractArchive(
    String archivePath,
    String destDir, {
    required InferenceFramework framework,
    required ModelFormat format,
  }) async {
    _logger.info('Extracting archive: $archivePath');

    final lib = PlatformLoader.loadCommons();
    final extractFn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>,
            Pointer<Void>, Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>, Pointer<Void>,
            Pointer<Void>, Pointer<Void>)>(
      'rac_extract_archive_native',
    );

    final archivePathPtr = archivePath.toNativeUtf8(allocator: calloc);
    final destPathPtr = destDir.toNativeUtf8(allocator: calloc);

    try {
      final result = extractFn(
        archivePathPtr,
        destPathPtr,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
      );

      if (result != 0) {
        _logger.error('Native extraction failed with code: $result');
        throw Exception('Native extraction failed with code: $result');
      }
    } finally {
      calloc.free(archivePathPtr);
      calloc.free(destPathPtr);
    }

    _logger.info('Extraction complete: $destDir');
    return destDir;
  }

  /// Resolve the final model directory after archive extraction.
  ///
  /// The download service already creates a per-model directory (destDir) named
  /// after the modelId.  Archives may contain a single root folder whose name
  /// differs from modelId (e.g. Genie NPU tar.gz).  We flatten that away so
  /// model files always live directly inside destDir.
  ///
  /// Cases handled:
  /// 1. Model files extracted directly into destDir → nothing to do.
  /// 2. Single new subdirectory created by extraction → move its contents up
  ///    into destDir and delete the now-empty subdirectory.
  /// 3. Multiple new items → already flat, nothing to do.
  Future<String> _resolveExtractedModelPath(
    String destDir,
    String modelId,
    Set<String> itemsBefore,
    String fallbackPath,
  ) async {
    final destDirectory = Directory(destDir);

    // Find new items created by extraction
    final currentItems = await destDirectory.list().toList();
    final newItems =
        currentItems.where((e) => !itemsBefore.contains(e.path)).toList();
    final newDirs = newItems.whereType<Directory>().toList();
    final newFiles = newItems.whereType<File>().toList();

    // Case: single new directory (e.g. Genie NPU archive root like
    // "llama_v3_2_1b_instruct-genie-w4-qualcomm_snapdragon_8_elite/").
    // Move its contents up into destDir so files are discoverable directly.
    if (newDirs.length == 1 && newFiles.isEmpty) {
      final extractedDir = newDirs.first;
      _logger.info(
        'Flattening extracted dir '
        "'${p.basename(extractedDir.path)}' into destDir",
      );
      try {
        final innerItems = await extractedDir.list().toList();
        for (final item in innerItems) {
          final target = p.join(destDir, p.basename(item.path));
          try {
            await item.rename(target);
          } catch (e) {
            if (item is File) {
              await item.copy(target);
              await item.delete();
            } else {
              _logger.warning('Failed to move ${item.path}: $e');
            }
          }
        }
        await extractedDir.delete(recursive: true);
        _logger.info(
          'Flattened ${innerItems.length} items from '
          "'${p.basename(extractedDir.path)}' into: $destDir",
        );
      } catch (e) {
        _logger.warning('Error flattening extracted dir: $e');
      }
      return destDir;
    }

    // Files already at destDir root (flat archive or direct match) — use as-is
    if (newItems.isNotEmpty) {
      _logger
          .info('Extracted ${newItems.length} items directly into: $destDir');
      return destDir;
    }

    return fallbackPath;
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
