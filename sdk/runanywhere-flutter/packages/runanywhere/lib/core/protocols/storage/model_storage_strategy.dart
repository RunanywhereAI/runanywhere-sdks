import 'package:runanywhere/core/models/framework/model_format.dart';
import 'package:runanywhere/core/protocols/downloading/download_strategy.dart';

/// Information about model storage details.
/// Matches iOS ModelStorageDetails from Core/Protocols/Storage/ModelStorageStrategy.swift
class ModelStorageDetails {
  /// Format of the model
  final ModelFormat format;

  /// Total size in bytes
  final int totalSize;

  /// Number of files
  final int fileCount;

  /// Primary file name for single-file models (null for multi-file)
  final String? primaryFile;

  /// Whether the model is stored as a directory
  final bool isDirectoryBased;

  const ModelStorageDetails({
    required this.format,
    required this.totalSize,
    required this.fileCount,
    this.primaryFile,
    this.isDirectoryBased = false,
  });

  /// Create from JSON map
  factory ModelStorageDetails.fromJson(Map<String, dynamic> json) {
    return ModelStorageDetails(
      format: ModelFormat.fromRawValue(json['format'] as String? ?? 'unknown'),
      totalSize: (json['totalSize'] as num?)?.toInt() ?? 0,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      primaryFile: json['primaryFile'] as String?,
      isDirectoryBased: json['isDirectoryBased'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'format': format.rawValue,
      'totalSize': totalSize,
      'fileCount': fileCount,
      if (primaryFile != null) 'primaryFile': primaryFile,
      'isDirectoryBased': isDirectoryBased,
    };
  }
}

/// Protocol for custom model storage strategies that handle both downloading and file management.
/// Extends the DownloadStrategy concept to include file discovery and management.
/// Matches iOS ModelStorageStrategy from Core/Protocols/Storage/ModelStorageStrategy.swift
abstract interface class ModelStorageStrategy implements DownloadStrategy {
  /// Find the model file/folder in storage
  /// [modelId] - The model identifier
  /// [modelFolder] - The folder where the model is stored
  /// Returns URL to the model (could be a file or folder depending on the model type)
  String? findModelPath({
    required String modelId,
    required String modelFolder,
  });

  /// Detect if a model exists in the given folder
  /// Returns model format and size if found, null otherwise
  (ModelFormat format, int size)? detectModel(String modelFolder);

  /// Check if the model storage is valid (all required files present)
  bool isValidModelStorage(String modelFolder);

  /// Get display information for the model
  ModelStorageDetails? getModelStorageInfo(String modelFolder);
}

/// Default mixin with basic model storage operations.
/// Provides default implementations for simple single-file models.
mixin DefaultModelStorageStrategy on DownloadStrategy
    implements ModelStorageStrategy {
  @override
  String? findModelPath({
    required String modelId,
    required String modelFolder,
  }) {
    // Default implementation would use dart:io to find the file
    // Mock: Return null
    return null;
  }

  @override
  (ModelFormat format, int size)? detectModel(String modelFolder) {
    // Default implementation would scan for known model file extensions
    // Mock: Return null
    return null;
  }

  @override
  bool isValidModelStorage(String modelFolder) {
    return detectModel(modelFolder) != null;
  }

  @override
  ModelStorageDetails? getModelStorageInfo(String modelFolder) {
    final modelInfo = detectModel(modelFolder);
    if (modelInfo == null) return null;

    return ModelStorageDetails(
      format: modelInfo.$1,
      totalSize: modelInfo.$2,
      fileCount: 1,
      primaryFile: null,
      isDirectoryBased: false,
    );
  }
}
