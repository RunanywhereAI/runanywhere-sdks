// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_storage.dart — storage + download helpers.
// Mirrors Swift `RunAnywhere+Storage.swift`.

import 'package:fixnum/fixnum.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/adapters/model_download_adapter.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadProgress;
import 'package:runanywhere/generated/storage_types.pb.dart';
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
        requiredBytes: Int64(native.requiredSpace),
        availableBytes: Int64(native.availableSpace),
        warningMessage: native.hasWarning ? 'Low storage' : '',
        recommendation: native.recommendation ?? '',
      );
    }

    // Fail-open: assume available if the native call returns null.
    return StorageAvailability(
      isAvailable: true,
      requiredBytes: Int64(requiredWithMargin),
      availableBytes: Int64.ZERO,
    );
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

  /// Low-level download stream. Emits proto-generated `DownloadProgress`
  /// events driven by the C++ `rac_download_orchestrate` state machine.
  static Stream<DownloadProgress> downloadModel(String modelId) =>
      ModelDownloadService.shared.downloadModel(modelId);
}
