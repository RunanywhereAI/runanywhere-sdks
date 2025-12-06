import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../public/models/models.dart';

/// Centralized utility for calculating model paths and directories.
/// Follows the structure: `Documents/RunAnywhere/Models/{framework.rawValue}/{modelId}/`
///
/// This utility ensures consistent path calculation across the entire SDK,
/// preventing scattered path logic and reducing potential bugs.
///
/// Matches iOS ModelPathUtils from Foundation/FileOperations/ModelPathUtils.swift
class ModelPathUtils {
  // Private constructor to prevent instantiation
  ModelPathUtils._();

  // MARK: - Base Directories

  /// Get the base RunAnywhere directory in Documents
  /// Returns path to `Documents/RunAnywhere/`
  static Future<Directory> getBaseDirectory() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return Directory('${documentsDir.path}/RunAnywhere');
  }

  /// Get the models directory
  /// Returns path to `Documents/RunAnywhere/Models/`
  static Future<Directory> getModelsDirectory() async {
    final baseDir = await getBaseDirectory();
    return Directory('${baseDir.path}/Models');
  }

  // MARK: - Framework-Specific Paths

  /// Get the folder for a specific framework
  /// Returns path to `Documents/RunAnywhere/Models/{framework.rawValue}/`
  static Future<Directory> getFrameworkDirectory(LLMFramework framework) async {
    final modelsDir = await getModelsDirectory();
    return Directory('${modelsDir.path}/${framework.rawValue}');
  }

  /// Get the folder for a specific model within a framework
  /// Returns path to `Documents/RunAnywhere/Models/{framework.rawValue}/{modelId}/`
  static Future<Directory> getModelFolder({
    required String modelId,
    required LLMFramework framework,
  }) async {
    final frameworkDir = await getFrameworkDirectory(framework);
    return Directory('${frameworkDir.path}/$modelId');
  }

  /// Get the folder for a model (legacy path without framework)
  /// Returns path to `Documents/RunAnywhere/Models/{modelId}/`
  static Future<Directory> getModelFolderLegacy(String modelId) async {
    final modelsDir = await getModelsDirectory();
    return Directory('${modelsDir.path}/$modelId');
  }

  // MARK: - Model File Paths

  /// Get the full path to a model file
  /// Returns path to `Documents/RunAnywhere/Models/{framework.rawValue}/{modelId}/{modelId}.{format.rawValue}`
  static Future<File> getModelFilePath({
    required String modelId,
    required LLMFramework framework,
    required ModelFormat format,
  }) async {
    final modelFolder = await getModelFolder(modelId: modelId, framework: framework);
    final fileName = '$modelId.${format.extension}';
    return File('${modelFolder.path}/$fileName');
  }

  /// Get the full path to a model file (legacy path without framework)
  /// Returns path to `Documents/RunAnywhere/Models/{modelId}/{modelId}.{format.rawValue}`
  static Future<File> getModelFilePathLegacy({
    required String modelId,
    required ModelFormat format,
  }) async {
    final modelFolder = await getModelFolderLegacy(modelId);
    final fileName = '$modelId.${format.extension}';
    return File('${modelFolder.path}/$fileName');
  }

  /// Get the expected model path from ModelInfo
  /// Returns path based on framework and format
  static Future<String> getModelPath(ModelInfo modelInfo) async {
    // Use preferred framework if available, otherwise use first compatible framework
    final framework = modelInfo.preferredFramework ?? modelInfo.compatibleFrameworks.firstOrNull;

    if (framework != null) {
      // For directory-based models (e.g., CoreML packages), return the folder
      if (modelInfo.format.isDirectoryBased) {
        final folder = await getModelFolder(modelId: modelInfo.id, framework: framework);
        return folder.path;
      }
      // For single-file models, return the full file path
      final file = await getModelFilePath(
        modelId: modelInfo.id,
        framework: framework,
        format: modelInfo.format,
      );
      return file.path;
    } else {
      // Legacy fallback without framework
      if (modelInfo.format.isDirectoryBased) {
        final folder = await getModelFolderLegacy(modelInfo.id);
        return folder.path;
      }
      final file = await getModelFilePathLegacy(
        modelId: modelInfo.id,
        format: modelInfo.format,
      );
      return file.path;
    }
  }

  /// Get the expected model path from components
  static Future<String> getExpectedModelPath({
    required String modelId,
    LLMFramework? framework,
    required ModelFormat format,
  }) async {
    if (framework != null) {
      if (format.isDirectoryBased) {
        final folder = await getModelFolder(modelId: modelId, framework: framework);
        return folder.path;
      }
      final file = await getModelFilePath(
        modelId: modelId,
        framework: framework,
        format: format,
      );
      return file.path;
    } else {
      if (format.isDirectoryBased) {
        final folder = await getModelFolderLegacy(modelId);
        return folder.path;
      }
      final file = await getModelFilePathLegacy(
        modelId: modelId,
        format: format,
      );
      return file.path;
    }
  }

  // MARK: - Other Directories

  /// Get the cache directory
  /// Returns path to `Documents/RunAnywhere/Cache/`
  static Future<Directory> getCacheDirectory() async {
    final baseDir = await getBaseDirectory();
    return Directory('${baseDir.path}/Cache');
  }

  /// Get the temporary files directory
  /// Returns path to `Documents/RunAnywhere/Temp/`
  static Future<Directory> getTempDirectory() async {
    final baseDir = await getBaseDirectory();
    return Directory('${baseDir.path}/Temp');
  }

  /// Get the downloads directory
  /// Returns path to `Documents/RunAnywhere/Downloads/`
  static Future<Directory> getDownloadsDirectory() async {
    final baseDir = await getBaseDirectory();
    return Directory('${baseDir.path}/Downloads');
  }

  // MARK: - Directory Creation

  /// Ensure a directory exists, creating it if necessary
  static Future<Directory> ensureDirectoryExists(Directory directory) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Ensure all base directories exist
  static Future<void> ensureBaseDirectoriesExist() async {
    await ensureDirectoryExists(await getBaseDirectory());
    await ensureDirectoryExists(await getModelsDirectory());
    await ensureDirectoryExists(await getCacheDirectory());
    await ensureDirectoryExists(await getTempDirectory());
    await ensureDirectoryExists(await getDownloadsDirectory());
  }

  // MARK: - Path Analysis

  /// Extract model ID from a file path
  static String? extractModelId(String path) {
    final pathComponents = path.split('/');

    // Check if this is a model in our framework structure
    final modelsIndex = pathComponents.indexOf('Models');
    if (modelsIndex >= 0 && modelsIndex + 1 < pathComponents.length) {
      final nextComponent = pathComponents[modelsIndex + 1];

      // Check if next component is a framework name
      final isFramework = LLMFramework.values.any((f) => f.rawValue == nextComponent);
      if (isFramework && modelsIndex + 2 < pathComponents.length) {
        // Framework structure: Models/framework/modelId
        return pathComponents[modelsIndex + 2];
      } else {
        // Direct model folder structure: Models/modelId
        return nextComponent;
      }
    }

    return null;
  }

  /// Extract framework from a file path
  static LLMFramework? extractFramework(String path) {
    final pathComponents = path.split('/');

    final modelsIndex = pathComponents.indexOf('Models');
    if (modelsIndex >= 0 && modelsIndex + 1 < pathComponents.length) {
      final nextComponent = pathComponents[modelsIndex + 1];

      // Check if next component is a framework name
      return LLMFramework.values.cast<LLMFramework?>().firstWhere(
            (f) => f?.rawValue == nextComponent,
            orElse: () => null,
          );
    }

    return null;
  }

  /// Check if a path is within the models directory
  static bool isModelPath(String path) {
    return path.contains('/Models/');
  }

  // MARK: - Model File Checks

  /// Check if a model exists at the expected path
  static Future<bool> modelExists(ModelInfo modelInfo) async {
    final path = await getModelPath(modelInfo);

    if (modelInfo.format.isDirectoryBased) {
      return Directory(path).exists();
    } else {
      return File(path).exists();
    }
  }

  /// Get the size of a model file/directory in bytes
  static Future<int> getModelSize(ModelInfo modelInfo) async {
    final path = await getModelPath(modelInfo);

    if (modelInfo.format.isDirectoryBased) {
      final dir = Directory(path);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } else {
      final file = File(path);
      if (!await file.exists()) return 0;
      return await file.length();
    }
  }

  /// Delete a model from disk
  static Future<void> deleteModel(ModelInfo modelInfo) async {
    final path = await getModelPath(modelInfo);

    if (modelInfo.format.isDirectoryBased) {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } else {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      // Also try to delete the parent directory if empty
      final parentDir = file.parent;
      if (await parentDir.exists()) {
        final contents = await parentDir.list().toList();
        if (contents.isEmpty) {
          await parentDir.delete();
        }
      }
    }
  }
}

/// Extension to add isDirectoryBased to ModelFormat
extension ModelFormatPathExtension on ModelFormat {
  /// Whether this format represents a directory-based model
  bool get isDirectoryBased {
    switch (this) {
      case ModelFormat.mlmodel:
      case ModelFormat.mlpackage:
        return true;
      default:
        return false;
    }
  }

  /// Get the file extension for this format
  String get extension {
    return rawValue;
  }
}
