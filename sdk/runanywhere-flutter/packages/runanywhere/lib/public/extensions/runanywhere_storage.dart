// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_storage.dart — storage + download helpers.
// Mirrors Swift `RunAnywhere+Storage.swift`.

import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/infrastructure/download/download_service.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Static helpers for storage + low-level download operations.
class RunAnywhereStorage {
  RunAnywhereStorage._();

  /// True if the device has enough free storage for [modelSize].
  /// [safetyMargin] pads the check by a fraction (default 10%).
  static Future<bool> checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  }) async {
    try {
      final requiredWithMargin = (modelSize * (1 + safetyMargin)).toInt();
      return DartBridgeFileManager.checkStorage(requiredWithMargin);
    } catch (_) {
      // Fail-open: assume available if the native check fails.
      return true;
    }
  }

  /// Get a value from native storage.
  static Future<String?> getStorageValue(String key) =>
      DartBridgeStorage.instance.get(key);

  /// Set a value in native storage.
  static Future<bool> setStorageValue(String key, String value) =>
      DartBridgeStorage.instance.set(key, value);

  /// Delete a value from native storage.
  static Future<bool> deleteStorageValue(String key) =>
      DartBridgeStorage.instance.delete(key);

  /// Check if a key exists in native storage.
  static Future<bool> storageKeyExists(String key) =>
      DartBridgeStorage.instance.exists(key);

  /// Clear all native storage.
  static Future<void> clearStorage() async {
    await DartBridgeStorage.instance.clear();
    EventBus.shared.publish(SDKStorageEvent.cacheCleared());
  }

  /// Base directory for SDK files (`.../<documents>/runanywhere`).
  static Future<String> getBaseDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/runanywhere';
  }

  /// Low-level download stream (internal progress type). Most callers
  /// should prefer `RunAnywhereSDK.instance.downloads.start(id)` which
  /// yields the public `DownloadProgress` type.
  static Stream<ModelDownloadProgress> downloadModel(String modelId) =>
      ModelDownloadService.shared.downloadModel(modelId);
}
