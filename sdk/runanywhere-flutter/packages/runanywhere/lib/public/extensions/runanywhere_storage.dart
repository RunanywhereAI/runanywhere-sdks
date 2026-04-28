// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_storage.dart — storage + download helpers.
// Mirrors Swift `RunAnywhere+Storage.swift`.

import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/adapters/model_download_adapter.dart';
import 'package:runanywhere/core/types/storage_types.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Static helpers for storage + low-level download operations.
class RunAnywhereStorage {
  RunAnywhereStorage._();

  /// True if the device has enough free storage for [modelSize].
  ///
  /// [safetyMargin] pads the check by a fraction (default 10%). Returns
  /// the rich [StorageAvailability] shape so callers can surface the
  /// required/available bytes and any warning. Mirrors Swift's
  /// `checkStorageAvailable(for:safetyMargin:) -> StorageAvailability`.
  static Future<StorageAvailability> checkStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  }) async {
    final requiredWithMargin = (modelSize * (1 + safetyMargin)).toInt();

    final native =
        DartBridgeFileManager.checkStorageAvailability(requiredWithMargin);
    if (native != null) {
      return StorageAvailability(
        isAvailable: native.isAvailable,
        requiredSpace: native.requiredSpace,
        availableSpace: native.availableSpace,
        hasWarning: native.hasWarning,
        recommendation: native.recommendation,
      );
    }

    // Fail-open: assume available if the native call returns null.
    return StorageAvailability(
      isAvailable: true,
      requiredSpace: requiredWithMargin,
      availableSpace: 0,
      hasWarning: false,
    );
  }

  /// Boolean-only convenience matching the legacy v3 surface. Prefer
  /// [checkStorageAvailable] which returns the rich shape.
  static Future<bool> isStorageAvailable({
    required int modelSize,
    double safetyMargin = 0.1,
  }) async {
    final result = await checkStorageAvailable(
      modelSize: modelSize,
      safetyMargin: safetyMargin,
    );
    return result.isAvailable;
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
