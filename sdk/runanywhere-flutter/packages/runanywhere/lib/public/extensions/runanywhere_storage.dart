// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_storage.dart — storage + download helpers.
// Mirrors Swift `RunAnywhere+Storage.swift`.

import 'package:fixnum/fixnum.dart';
import 'package:path_provider/path_provider.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadProgress;
import 'package:runanywhere/generated/storage_types.pb.dart';
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';

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
    final result = await checkStorageAvailabilityResult(
      StorageAvailabilityRequest(
        requiredBytes: Int64(modelSize),
        safetyMargin: safetyMargin,
      ),
    );
    return result.hasAvailability()
        ? result.availability
        : StorageAvailability(
            isAvailable: false,
            requiredBytes: Int64(modelSize),
            availableBytes: Int64.ZERO,
            warningMessage: result.errorMessage,
          );
  }

  /// Generated-proto storage availability surface.
  static Future<StorageAvailabilityResult> checkStorageAvailabilityResult(
    StorageAvailabilityRequest request,
  ) =>
      DartBridgeStorage.instance.availabilityProto(request);

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
  }

  /// Base directory for SDK files (`.../<documents>/runanywhere`).
  static Future<String> getBaseDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/runanywhere';
  }

  /// Low-level download stream. Emits proto-generated `DownloadProgress`
  /// events driven by the C++ `rac_download_orchestrate` state machine.
  static Stream<DownloadProgress> downloadModel(String modelId) =>
      RunAnywhereDownloads.shared.start(modelId);
}
