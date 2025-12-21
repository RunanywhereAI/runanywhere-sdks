import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/models/framework/llm_framework.dart';
import '../../core/models/model/model_info.dart';
import '../../core/protocols/downloading/download_strategy.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../../foundation/error_types/sdk_error.dart';
import '../../foundation/file_operations/archive_utils.dart';

/// ONNX download strategy for handling .onnx files and .tar.bz2 archives
/// Matches iOS ONNXDownloadStrategy pattern
///
/// Uses pure Dart archive extraction (via `archive` package) for cross-platform support.
/// This works on both iOS and Android without requiring native libarchive.
class OnnxDownloadStrategy implements DownloadStrategy {
  final SDKLogger logger = SDKLogger(category: 'OnnxDownloadStrategy');

  @override
  bool canHandle(ModelInfo model) {
    final url = model.downloadURL;
    if (url == null) return false;

    final urlString = url.toString().toLowerCase();
    final isONNX = model.compatibleFrameworks.contains(LLMFramework.onnx);

    // Handle tar.bz2 archives (sherpa-onnx models)
    final isTarBz2 = urlString.endsWith('.tar.bz2');

    // Handle direct .onnx files (HuggingFace Piper models)
    final isDirectOnnx = urlString.endsWith('.onnx');

    final canHandle = isONNX && (isTarBz2 || isDirectOnnx);
    logger.debug('canHandle(${model.id}): $canHandle (url: $urlString)');
    return canHandle;
  }

  @override
  Future<Uri> download({
    required ModelInfo model,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  }) async {
    final downloadURL = model.downloadURL;
    if (downloadURL == null) {
      throw SDKError.downloadFailed(
        'Model ${model.id}',
        'Model has no download URL',
      );
    }

    final urlString = downloadURL.toString().toLowerCase();

    if (urlString.endsWith('.onnx')) {
      // Handle direct ONNX files (download model + config)
      return await _downloadDirectOnnx(
        model: model,
        downloadURL: downloadURL,
        destinationFolder: destinationFolder,
        progressHandler: progressHandler,
      );
    } else if (urlString.endsWith('.tar.bz2')) {
      // Handle tar.bz2 archives
      return await _downloadTarBz2Archive(
        model: model,
        downloadURL: downloadURL,
        destinationFolder: destinationFolder,
        progressHandler: progressHandler,
      );
    } else {
      throw SDKError.downloadFailed(
        urlString,
        'Unsupported ONNX model format',
      );
    }
  }

  /// Download direct .onnx files along with their companion .onnx.json config
  Future<Uri> _downloadDirectOnnx({
    required ModelInfo model,
    required Uri downloadURL,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  }) async {
    logger.info('Downloading direct ONNX model: ${model.id}');

    // Create model folder
    final modelFolder = Directory(destinationFolder.toFilePath());
    await modelFolder.create(recursive: true);

    // Get the model filename from URL
    final modelFilename = downloadURL.path.split('/').last;
    final modelDestination = File('${modelFolder.path}/$modelFilename');

    // Also download the companion .onnx.json config file
    final configURL = Uri.parse('${downloadURL.toString()}.json');
    final configFilename = '$modelFilename.json';
    final configDestination = File('${modelFolder.path}/$configFilename');

    logger.info('Downloading model file: $modelFilename');
    logger.info('Downloading config file: $configFilename');

    // Download model file (0% - 45%)
    await _downloadFile(
      from: downloadURL,
      to: modelDestination,
      progressHandler: (progress) => progressHandler?.call(progress * 0.45),
    );

    logger.info('Model file downloaded, now downloading config...');
    progressHandler?.call(0.5);

    // Download config file (50% - 95%)
    try {
      await _downloadFile(
        from: configURL,
        to: configDestination,
        progressHandler: (progress) =>
            progressHandler?.call(0.5 + progress * 0.45),
      );
      logger.info('Config file downloaded successfully');
    } catch (e) {
      // Config file might not exist for some models, log warning but continue
      logger.warning('Config file download failed (model may still work): $e');
    }

    progressHandler?.call(1.0);

    logger.info('Direct ONNX model download complete: ${modelFolder.path}');
    return modelFolder.uri;
  }

  /// Download and extract tar.bz2 archive
  Future<Uri> _downloadTarBz2Archive({
    required ModelInfo model,
    required Uri downloadURL,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  }) async {
    logger.info('Downloading sherpa-onnx archive for model: ${model.id}');

    // Use the provided destination folder
    final modelFolder = Directory(destinationFolder.toFilePath());
    await modelFolder.create(recursive: true);

    // Download the .tar.bz2 archive to a temporary location
    final tempDirectory = Directory.systemTemp;
    final archivePath = File('${tempDirectory.path}/${model.id}.tar.bz2');

    logger.info('Downloading archive to: ${archivePath.path}');

    // Download the archive (0% - 50%)
    await _downloadFile(
      from: downloadURL,
      to: archivePath,
      progressHandler: (progress) => progressHandler?.call(progress * 0.5),
    );

    // Report download complete (50% - download done, extraction next)
    progressHandler?.call(0.5);

    logger.info('Archive downloaded, extracting to: ${modelFolder.path}');

    // Extract the archive using Flutter-side extraction (cross-platform)
    try {
      // Use pure Dart archive extraction instead of native backend
      // This works on both iOS and Android
      await ArchiveUtils.extractTarBz2(
        archivePath: archivePath.path,
        destinationPath: modelFolder.path,
        onProgress: (extractProgress) {
          // Map extraction progress to 50% - 95% of overall progress
          final overallProgress = 0.5 + (extractProgress * 0.45);
          progressHandler?.call(overallProgress);
        },
      );

      logger.info('Archive extracted successfully to: ${modelFolder.path}');
    } catch (e) {
      logger.error('Archive extraction failed: $e');
      // Clean up archive on error
      try {
        await archivePath.delete();
      } catch (_) {}
      rethrow;
    }

    // Clean up the archive
    try {
      await archivePath.delete();
    } catch (e) {
      logger.warning('Failed to delete archive file: $e');
    }

    // Find the extracted model directory
    // Sherpa-ONNX archives typically extract to a subdirectory with the model name
    final contents = await modelFolder.list().toList();
    logger.debug(
        'Extracted contents: ${contents.map((e) => e.path.split('/').last).join(", ")}');

    // If there's a single subdirectory, the actual model files are in there
    var modelDir = modelFolder;
    if (contents.length == 1 && contents.first is Directory) {
      final subdir = contents.first as Directory;
      final subdirStat = await subdir.stat();
      if (subdirStat.type == FileSystemEntityType.directory) {
        // Model files are in the subdirectory
        modelDir = subdir;
        logger.info(
            'Model files are in subdirectory: ${subdir.path.split('/').last}');
      }
    }

    // Report completion (100%)
    progressHandler?.call(1.0);

    logger.info('Model download and extraction complete: ${modelDir.path}');
    return modelDir.uri;
  }

  /// Helper to download a single file
  Future<void> _downloadFile({
    required Uri from,
    required File to,
    void Function(double progress)? progressHandler,
  }) async {
    logger.debug('Downloading file from: $from');

    // Ensure destination directory exists
    await to.parent.create(recursive: true);

    final request = http.Request('GET', from);
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw SDKError.downloadFailed(
        from.toString(),
        'Download failed with status ${response.statusCode}',
      );
    }

    final totalBytes = response.contentLength ?? 0;
    int bytesDownloaded = 0;

    final sink = to.openWrite();

    // Stream response and track progress
    await for (final chunk in response.stream) {
      sink.add(chunk);
      bytesDownloaded += chunk.length;

      if (totalBytes > 0 && progressHandler != null) {
        final progress = bytesDownloaded / totalBytes;
        progressHandler(progress);
      }
    }

    await sink.close();

    if (progressHandler != null) {
      progressHandler(1.0);
    }
  }
}
