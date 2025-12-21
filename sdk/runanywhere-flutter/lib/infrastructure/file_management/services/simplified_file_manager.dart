import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../core/models/storage/device_storage_info.dart';
import '../protocol/file_management_error.dart';
import '../protocol/file_management_service.dart';

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
class SimplifiedFileManager implements FileManagementService {
  final SDKLogger _logger = SDKLogger(category: 'FileManager');

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

  @override
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

  @override
  String getModelFolderPath({
    required String modelId,
    required String framework,
  }) {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Models', framework, modelId);
  }

  @override
  bool modelFolderExists({
    required String modelId,
    required String framework,
  }) {
    _ensureInitialized();
    final folderPath =
        getModelFolderPath(modelId: modelId, framework: framework);
    final folder = Directory(folderPath);
    if (!folder.existsSync()) return false;
    final contents = folder.listSync();
    return contents.isNotEmpty;
  }

  @override
  Future<void> deleteModel({
    required String modelId,
    required String framework,
  }) async {
    _ensureInitialized();
    final folderPath =
        getModelFolderPath(modelId: modelId, framework: framework);
    final folder = Directory(folderPath);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
      _logger.info('Deleted model: $modelId from $framework');
    }
  }

  @override
  Map<String, List<String>> getDownloadedModels() {
    _ensureInitialized();
    final result = <String, List<String>>{};

    final modelsDir = Directory(path.join(_baseDirectory!.path, 'Models'));
    if (!modelsDir.existsSync()) return result;

    for (final frameworkDir in modelsDir.listSync().whereType<Directory>()) {
      final framework = path.basename(frameworkDir.path);
      final modelIds = <String>[];

      for (final modelDir in frameworkDir.listSync().whereType<Directory>()) {
        if (modelDir.listSync().isNotEmpty) {
          modelIds.add(path.basename(modelDir.path));
        }
      }

      if (modelIds.isNotEmpty) {
        result[framework] = modelIds;
      }
    }

    return result;
  }

  @override
  bool isModelDownloaded({
    required String modelId,
    required String framework,
  }) {
    return modelFolderExists(modelId: modelId, framework: framework);
  }

  @override
  Future<String> getDownloadFolder() async {
    _ensureInitialized();
    return path.join(_baseDirectory!.path, 'Downloads');
  }

  @override
  Future<String> createTempDownloadFile(String modelId) async {
    _ensureInitialized();
    final downloadFolder = await getDownloadFolder();
    final tempFileName =
        '${modelId}_${DateTime.now().millisecondsSinceEpoch}.tmp';
    return path.join(downloadFolder, tempFileName);
  }

  @override
  Future<void> storeCache(
      {required String key, required List<int> data}) async {
    _ensureInitialized();
    final cacheDir = Directory(path.join(_baseDirectory!.path, 'Cache'));
    final cacheFile = File(path.join(cacheDir.path, '$key.cache'));
    await cacheFile.writeAsBytes(data);
  }

  @override
  Future<List<int>?> loadCache(String key) async {
    _ensureInitialized();
    final cacheDir = Directory(path.join(_baseDirectory!.path, 'Cache'));
    final cacheFile = File(path.join(cacheDir.path, '$key.cache'));
    if (await cacheFile.exists()) {
      return await cacheFile.readAsBytes();
    }
    return null;
  }

  @override
  Future<void> clearCache() async {
    _ensureInitialized();
    final cacheDir = Directory(path.join(_baseDirectory!.path, 'Cache'));
    if (await cacheDir.exists()) {
      for (final file in cacheDir.listSync().whereType<File>()) {
        await file.delete();
      }
    }
    _logger.info('Cleared cache');
  }

  @override
  Future<void> cleanTempFiles() async {
    _ensureInitialized();
    final tempDir = Directory(path.join(_baseDirectory!.path, 'Temp'));
    if (await tempDir.exists()) {
      for (final file in tempDir.listSync().whereType<File>()) {
        await file.delete();
      }
    }
    _logger.info('Cleaned temp files');
  }

  @override
  int getAvailableSpace() {
    // This would need platform-specific implementation
    // For now, return a default value
    return 0;
  }

  @override
  DeviceStorageInfo getDeviceStorageInfo() {
    // This would need platform-specific implementation
    return const DeviceStorageInfo(
      totalSpace: 0,
      freeSpace: 0,
      usedSpace: 0,
    );
  }

  @override
  int calculateDirectorySize(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;

    int totalSize = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        totalSize += entity.lengthSync();
      }
    }
    return totalSize;
  }

  @override
  String getBaseDirectoryPath() {
    _ensureInitialized();
    return _baseDirectory!.path;
  }

  void _ensureInitialized() {
    if (_baseDirectory == null) {
      throw FileManagementError(
        'FileManager not initialized. Call initialize() first.',
        FileManagementErrorType.directoryNotFound,
      );
    }
  }
}
