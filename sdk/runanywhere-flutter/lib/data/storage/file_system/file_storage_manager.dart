import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../core/protocols/storage/model_storage_manager.dart';

/// File Storage Manager Implementation
/// Similar to Swift SDK's FileStorageManager
class FileStorageManager implements ModelStorageManager {
  Future<String> get _basePath async {
    final appDir = await getApplicationDocumentsDirectory();
    return path.join(appDir.path, 'RunAnywhere', 'Models');
  }

  @override
  Future<String> getStoragePath(String modelId) async {
    final base = await _basePath;
    return path.join(base, '$modelId.gguf');
  }

  @override
  Future<bool> modelExists(String modelId) async {
    final filePath = await getStoragePath(modelId);
    final file = File(filePath);
    return await file.exists();
  }

  @override
  Future<void> saveModel(String modelId, List<int> data) async {
    final filePath = await getStoragePath(modelId);
    final file = File(filePath);
    
    // Create directory if it doesn't exist
    final directory = file.parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    await file.writeAsBytes(data);
  }

  @override
  Future<List<int>> loadModel(String modelId) async {
    final filePath = await getStoragePath(modelId);
    final file = File(filePath);
    
    if (!await file.exists()) {
      throw FileSystemException('Model not found: $modelId', filePath);
    }

    return await file.readAsBytes();
  }

  @override
  Future<void> deleteModel(String modelId) async {
    final filePath = await getStoragePath(modelId);
    final file = File(filePath);
    
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<StorageInfo> getStorageInfo() async {
    final base = await _basePath;
    final directory = Directory(base);
    
    if (!await directory.exists()) {
      return StorageInfo(
        totalSpace: 0,
        usedSpace: 0,
        availableSpace: 0,
      );
    }

    int usedSpace = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        usedSpace += await entity.length();
      }
    }

    // TODO: Get actual total and available space from platform
    return StorageInfo(
      totalSpace: 10_000_000_000, // 10GB default
      usedSpace: usedSpace,
      availableSpace: 10_000_000_000 - usedSpace,
    );
  }
}

