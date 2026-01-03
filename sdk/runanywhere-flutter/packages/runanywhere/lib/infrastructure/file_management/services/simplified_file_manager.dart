/// Simplified File Manager
///
/// File manager for RunAnywhere SDK.
/// Matches iOS SimplifiedFileManager from Infrastructure/FileManagement/Services/.
library simplified_file_manager;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/core/types/storage_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// File manager for RunAnywhere SDK
/// Matches iOS SimplifiedFileManager from Infrastructure/FileManagement/Services/SimplifiedFileManager.swift
///
/// Directory Structure:
/// ```
/// Documents/RunAnywhere/
///   Models/
///     {framework}/          # e.g., "onnx", "llamacpp"
///       {modelId}/          # e.g., "sherpa-onnx-whisper-tiny.en"
///         [model files]
///   Cache/
///   Temp/
///   Downloads/
/// ```
class SimplifiedFileManager {
  final SDKLogger _logger = SDKLogger('FileManager');

  Directory? _baseDirectory;

  SimplifiedFileManager();

  /// Initialize the file manager
  Future<void> initialize() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    _baseDirectory = Directory(path.join(documentsDir.path, 'RunAnywhere'));
    await _createDirectoryStructure();
  }

  Future<void> _createDirectoryStructure() async {
    if (_baseDirectory == null) return;

    final subdirs = ['Models', 'Cache', 'Temp', 'Downloads'];
    for (final subdir in subdirs) {
      final dir = Directory(path.join(_baseDirectory!.path, subdir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// Get the model folder path, creating it if necessary
  Future<String> getModelFolder({
    required String modelId,
    required String framework,
  }) async {
    _ensureInitialized();
    final folderPath = path.join(
      _baseDirectory!.path,
      'Models',
      framework,
      modelId,
    );
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folderPath;
  }

  /// Get the model folder path without creating
  String getModelFolderPath({
    required String modelId,
    required String framework,
  }) {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Models', framework, modelId);
  }

  /// Check if model folder exists
  bool modelFolderExists({
    required String modelId,
    required String framework,
  }) {
    _ensureInitialized();
    final folderPath = path.join(
      _baseDirectory!.path,
      'Models',
      framework,
      modelId,
    );
    return Directory(folderPath).existsSync();
  }

  /// Get the models root directory
  Future<String> getModelsDirectory() async {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Models');
  }

  /// Get the downloads directory
  Future<String> getDownloadsDirectory() async {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Downloads');
  }

  /// Get the cache directory
  Future<String> getCacheDirectory() async {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Cache');
  }

  /// Get the temp directory
  Future<String> getTempDirectory() async {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Temp');
  }

  /// Check if a file exists
  Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// Get file size in bytes
  Future<int> getFileSize(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      return file.length();
    }
    return 0;
  }

  /// Delete a file
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      _logger.info('Deleted file: $filePath');
    }
  }

  /// Delete a model folder
  Future<void> deleteModelFolder({
    required String modelId,
    required String framework,
  }) async {
    _ensureInitialized();
    final folderPath = path.join(
      _baseDirectory!.path,
      'Models',
      framework,
      modelId,
    );
    final folder = Directory(folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
      _logger.info('Deleted model folder: $folderPath');
    }
  }

  /// Calculate total size of all models
  Future<int> calculateModelsSize() async {
    _ensureInitialized();
    final modelsDir = Directory(path.join(_baseDirectory!.path, 'Models'));
    if (!await modelsDir.exists()) return 0;

    int totalSize = 0;
    await for (final entity in modelsDir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// Get device storage info
  DeviceStorageInfo getDeviceStorageInfo() {
    // Get device storage stats
    // Note: This is a simplified implementation
    return const DeviceStorageInfo(
      totalSpace: 0,
      freeSpace: 0,
      usedSpace: 0,
    );
  }

  /// Clear all cache
  Future<void> clearCache() async {
    _ensureInitialized();
    final cacheDir = Directory(path.join(_baseDirectory!.path, 'Cache'));
    if (await cacheDir.exists()) {
      await for (final entity in cacheDir.list()) {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
      _logger.info('Cache cleared');
    }
  }

  /// Clear all temporary files
  Future<void> clearTemp() async {
    _ensureInitialized();
    final tempDir = Directory(path.join(_baseDirectory!.path, 'Temp'));
    if (await tempDir.exists()) {
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
      _logger.info('Temp directory cleared');
    }
  }

  void _ensureInitialized() {
    if (_baseDirectory == null) {
      throw StateError(
          'SimplifiedFileManager not initialized. Call initialize() first.');
    }
  }
}
