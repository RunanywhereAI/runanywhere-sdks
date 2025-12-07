import 'dart:async';

import '../../models/storage/storage_availability.dart';
import '../../models/storage/storage_info.dart';
import '../../models/storage/model_storage_info.dart';
import '../../models/storage/storage_recommendation.dart';

/// Protocol for storage analysis operations.
/// Matches iOS StorageAnalyzer from Core/Protocols/Storage/StorageAnalyzer.swift
abstract interface class StorageAnalyzer {
  /// Analyze overall storage situation
  Future<StorageInfo> analyzeStorage();

  /// Get model storage usage information
  Future<ModelStorageInfo> getModelStorageUsage();

  /// Check storage availability for a model
  /// [modelSize] - Required size in bytes
  /// [safetyMargin] - Safety margin as a percentage (e.g., 0.1 for 10%)
  StorageAvailability checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  });

  /// Get storage recommendations based on current storage info
  List<StorageRecommendation> getRecommendations(StorageInfo storageInfo);

  /// Calculate size at a given path
  Future<int> calculateSize(String path);
}

/// Default mock implementation of StorageAnalyzer.
/// TODO: Implement platform-specific storage analysis when FFI bridge is ready.
class MockStorageAnalyzer implements StorageAnalyzer {
  @override
  Future<StorageInfo> analyzeStorage() async {
    return StorageInfo.empty;
  }

  @override
  Future<ModelStorageInfo> getModelStorageUsage() async {
    return const ModelStorageInfo(
      totalSize: 0,
      modelCount: 0,
      modelsByFramework: {},
      largestModel: null,
    );
  }

  @override
  StorageAvailability checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  }) {
    // Mock: Always report storage available
    return StorageAvailability(
      isAvailable: true,
      requiredSpace: modelSize,
      availableSpace: 10 * 1024 * 1024 * 1024, // 10GB mock
      hasWarning: false,
    );
  }

  @override
  List<StorageRecommendation> getRecommendations(StorageInfo storageInfo) {
    return const [];
  }

  @override
  Future<int> calculateSize(String path) async {
    return 0;
  }
}
