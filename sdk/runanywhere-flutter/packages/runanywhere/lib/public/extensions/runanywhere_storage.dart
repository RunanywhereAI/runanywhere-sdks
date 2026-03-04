/// RunAnywhere + Storage
///
/// Public API for storage and download operations.
/// Mirrors Swift's RunAnywhere+Storage.swift.
library runanywhere_storage;

import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/infrastructure/download/download_service.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/runanywhere.dart';

// =============================================================================
// RunAnywhere Storage Extensions
// =============================================================================

/// Extension methods for storage operations
extension RunAnywhereStorage on RunAnywhere {
  /// Check if storage is available for a model download
  ///
  /// Returns true if sufficient storage is available for the given model size.
  /// Delegates to C++ file manager for storage checks.
  static Future<bool> checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  }) async {
    try {
      final requiredWithMargin = (modelSize * (1 + safetyMargin)).toInt();
      return DartBridgeFileManager.checkStorage(requiredWithMargin);
    } catch (_) {
      // Default to available if check fails
      return true;
    }
  }

  /// Get value from storage
  static Future<String?> getStorageValue(String key) async {
    return DartBridgeStorage.instance.get(key);
  }

  /// Set value in storage
  static Future<bool> setStorageValue(String key, String value) async {
    return DartBridgeStorage.instance.set(key, value);
  }

  /// Delete value from storage
  static Future<bool> deleteStorageValue(String key) async {
    return DartBridgeStorage.instance.delete(key);
  }

  /// Check if key exists in storage
  static Future<bool> storageKeyExists(String key) async {
    return DartBridgeStorage.instance.exists(key);
  }

  /// Clear all storage
  static Future<void> clearStorage() async {
    await DartBridgeStorage.instance.clear();
    EventBus.shared.publish(SDKStorageEvent.cacheCleared());
  }

  /// Get base directory URL for SDK files
  static Future<String> getBaseDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/runanywhere';
  }

  /// Download a model by ID with progress tracking
  ///
  /// ```dart
  /// final stream = RunAnywhereStorage.downloadModel('my-model-id');
  /// await for (final progress in stream) {
  ///   print('Progress: ${(progress.overallProgress * 100).toStringAsFixed(0)}%');
  /// }
  /// ```
  static Stream<ModelDownloadProgress> downloadModel(String modelId) {
    return ModelDownloadService.shared.downloadModel(modelId);
  }

}
