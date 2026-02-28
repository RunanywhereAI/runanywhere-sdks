import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// FFI typedef for rac_extract_archive_native
typedef _RacExtractNative = Int32 Function(
  Pointer<Utf8> archivePath,
  Pointer<Utf8> destinationDir,
  Pointer<Void> options,
  Pointer<Void> progressCallback,
  Pointer<Void> userData,
  Pointer<Void> outResult,
);
typedef _RacExtractDart = int Function(
  Pointer<Utf8> archivePath,
  Pointer<Utf8> destinationDir,
  Pointer<Void> options,
  Pointer<Void> progressCallback,
  Pointer<Void> userData,
  Pointer<Void> outResult,
);

/// ONNX download strategy for handling .onnx files and .tar.bz2 archives
/// Matches iOS ONNXDownloadStrategy pattern
///
/// Uses native C++ extraction via libarchive for all archive formats.
class OnnxDownloadStrategy {
  final SDKLogger logger = SDKLogger('OnnxDownloadStrategy');

  /// Check if this strategy can handle a given URL
  bool canHandle(String url) {
    final urlString = url.toLowerCase();

    // Handle tar.bz2 archives (sherpa-onnx models)
    final isTarBz2 = urlString.endsWith('.tar.bz2');

    // Handle direct .onnx files (HuggingFace Piper models)
    final isDirectOnnx = urlString.endsWith('.onnx');

    return isTarBz2 || isDirectOnnx;
  }

  /// Download a model from URL to destination folder
  Future<Uri> download({
    required String modelId,
    required Uri downloadURL,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  }) async {
    final urlString = downloadURL.toString().toLowerCase();

    if (urlString.endsWith('.onnx')) {
      // Handle direct ONNX files (download model + config)
      return _downloadDirectOnnx(
        modelId: modelId,
        downloadURL: downloadURL,
        destinationFolder: destinationFolder,
        progressHandler: progressHandler,
      );
    } else if (urlString.endsWith('.tar.bz2')) {
      // Handle tar.bz2 archives
      return _downloadTarBz2Archive(
        modelId: modelId,
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
    required String modelId,
    required Uri downloadURL,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  }) async {
    logger.info('Downloading direct ONNX model: $modelId');

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
    required String modelId,
    required Uri downloadURL,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  }) async {
    logger.info('Downloading sherpa-onnx archive for model: $modelId');

    // Use the provided destination folder
    final modelFolder = Directory(destinationFolder.toFilePath());
    await modelFolder.create(recursive: true);

    // Download the .tar.bz2 archive to a temporary location
    final tempDirectory = Directory.systemTemp;
    final archivePath = File('${tempDirectory.path}/$modelId.tar.bz2');

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

    // Extract the archive using native C++ (libarchive)
    try {
      await _extractNative(
        archivePath: archivePath.path,
        destinationPath: modelFolder.path,
      );

      // Report extraction progress complete
      progressHandler?.call(0.95);

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

  /// Extract archive using native C++ (libarchive) via FFI.
  /// Supports ZIP, TAR.GZ, TAR.BZ2, TAR.XZ with auto-detection.
  Future<void> _extractNative({
    required String archivePath,
    required String destinationPath,
  }) async {
    final lib = PlatformLoader.loadCommons();
    final extractFn = lib.lookupFunction<_RacExtractNative, _RacExtractDart>(
      'rac_extract_archive_native',
    );

    final archivePathPtr = archivePath.toNativeUtf8();
    final destPathPtr = destinationPath.toNativeUtf8();

    try {
      final result = extractFn(
        archivePathPtr,
        destPathPtr,
        nullptr, // default options
        nullptr, // no progress callback
        nullptr, // no user data
        nullptr, // no result output
      );

      if (result != 0) {
        throw SDKError.downloadFailed(
          archivePath,
          'Native extraction failed with code: $result',
        );
      }
    } finally {
      calloc.free(archivePathPtr);
      calloc.free(destPathPtr);
    }
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
