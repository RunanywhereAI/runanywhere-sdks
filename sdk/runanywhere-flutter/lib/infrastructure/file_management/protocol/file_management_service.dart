import 'dart:async';

import '../../../core/models/storage/device_storage_info.dart';

/// Protocol defining file management capabilities
/// Matches iOS FileManagementService from Infrastructure/FileManagement/Protocol/FileManagementService.swift
///
/// Directory Structure:
/// Documents/RunAnywhere/
///   Models/{framework}/{modelId}/[files]
///   Cache/
///   Temp/
///   Downloads/
abstract class FileManagementService {
  // MARK: - Model Storage

  /// Get or create folder path for a model: Models/{framework}/{modelId}/
  Future<String> getModelFolder({
    required String modelId,
    required String framework,
  });

  /// Get model folder path (without creating it)
  String getModelFolderPath({
    required String modelId,
    required String framework,
  });

  /// Check if a model folder exists and has contents
  bool modelFolderExists({
    required String modelId,
    required String framework,
  });

  /// Delete a model folder
  Future<void> deleteModel({
    required String modelId,
    required String framework,
  });

  /// Get all downloaded models by framework
  Map<String, List<String>> getDownloadedModels();

  /// Check if a specific model is downloaded
  bool isModelDownloaded({
    required String modelId,
    required String framework,
  });

  // MARK: - Download Management

  /// Get downloads folder path
  Future<String> getDownloadFolder();

  /// Create temp file for download
  Future<String> createTempDownloadFile(String modelId);

  // MARK: - Cache

  Future<void> storeCache({required String key, required List<int> data});
  Future<List<int>?> loadCache(String key);
  Future<void> clearCache();

  // MARK: - Temp Files

  Future<void> cleanTempFiles();

  // MARK: - Storage Info

  int getAvailableSpace();
  DeviceStorageInfo getDeviceStorageInfo();
  int calculateDirectorySize(String path);
  String getBaseDirectoryPath();
}
