//
// model_storage_strategy.dart
// RunAnywhere Flutter SDK
//
// Protocol for custom model storage strategies that handle file discovery and management.
// Matches iOS ModelStorageStrategy from Infrastructure/ModelManagement/Protocol/ModelStorageStrategy.swift
//

import 'dart:io';
import 'package:runanywhere/core/models/framework/model_format.dart';

/// Information about model storage details.
class ModelStorageDetails {
  /// The format of the model
  final ModelFormat format;

  /// Total size of the model in bytes
  final int totalSize;

  /// Number of files in the model storage
  final int fileCount;

  /// Main file for single-file models, null for multi-file
  final String? primaryFile;

  /// Whether the model is stored in a directory structure
  final bool isDirectoryBased;

  const ModelStorageDetails({
    required this.format,
    required this.totalSize,
    required this.fileCount,
    this.primaryFile,
    this.isDirectoryBased = false,
  });
}

/// Protocol for custom model storage strategies that handle file discovery and management.
///
/// This is separate from [DownloadStrategy] to follow Single Responsibility Principle.
/// Implementations that need both download and storage capabilities should implement both.
abstract class ModelStorageStrategy {
  /// Find the model file/folder in storage.
  ///
  /// [modelId] - The model identifier.
  /// [modelFolder] - The folder where the model is stored.
  ///
  /// Returns the path to the model (could be a file or folder depending on the model type).
  String? findModelPath(String modelId, Directory modelFolder);

  /// Detect if a model exists in the given folder.
  ///
  /// [modelFolder] - The folder to check.
  ///
  /// Returns model format and size information if found.
  (ModelFormat format, int size)? detectModel(Directory modelFolder);

  /// Check if the model storage is valid (all required files present).
  ///
  /// [modelFolder] - The folder containing the model.
  ///
  /// Returns true if the model storage is valid.
  bool isValidModelStorage(Directory modelFolder);

  /// Get display information for the model.
  ///
  /// [modelFolder] - The folder containing the model.
  ///
  /// Returns human-readable information about the model storage.
  ModelStorageDetails? getModelStorageInfo(Directory modelFolder);
}

/// Default implementation mixin for simple single-file models.
mixin DefaultModelStorageStrategy implements ModelStorageStrategy {
  @override
  String? findModelPath(String modelId, Directory modelFolder) {
    if (!modelFolder.existsSync()) return null;

    try {
      final files = modelFolder.listSync().whereType<File>();
      for (final file in files) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        if (fileName.contains(modelId)) {
          return file.path;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  (ModelFormat format, int size)? ModelFormat@override
  ? @override
  dynamic detectModel(Directory modelFolder) {
    if (!modelFolder.existsSync()) return null;

    try {
      final files = modelFolder.listSync().whereType<File>();
      for (final file in files) {
        final ext = file.path.split('.').last.toLowerCase();
        final format = ModelFormat.fromRawValue(ext);
        if (format != ModelFormat.unknown) {
          return (format, file.statSync().size);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  bool isValidModelStorage(Directory modelFolder) {
    return detectModel(modelFolder) != null;
  }

  @override
  ModelStorageDetails? getModelStorageInfo(Directory modelFolder) {
    final modelInfo = detectModel(modelFolder);
    if (modelInfo == null) return null;

    final (format, size) = modelInfo;

    int fileCount = 0;
    String? primaryFile;
    try {
      final files = modelFolder.listSync().whereType<File>().toList();
      fileCount = files.length;
      if (files.isNotEmpty) {
        primaryFile = files.first.path.split(Platform.pathSeparator).last;
      }
    } catch (_) {
      // Ignore errors
    }

    return ModelStorageDetails(
      format: format,
      totalSize: size,
      fileCount: fileCount,
      primaryFile: primaryFile,
      isDirectoryBased: false,
    );
  }
}
