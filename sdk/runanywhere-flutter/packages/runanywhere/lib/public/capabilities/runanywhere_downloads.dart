// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_downloads.dart — v4.0 Downloads capability instance API.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/infrastructure/download/download_service.dart';
import 'package:runanywhere/public/runanywhere.dart' as legacy;
import 'package:runanywhere/public/types/types.dart';

/// Download / storage management surface.
///
/// Access via `RunAnywhere.instance.downloads`.
class RunAnywhereDownloads {
  RunAnywhereDownloads._();
  static final RunAnywhereDownloads _instance = RunAnywhereDownloads._();
  static RunAnywhereDownloads get shared => _instance;

  /// Start a model download. Returns a `Stream<ModelDownloadProgress>`
  /// that emits per-chunk progress until COMPLETED or FAILED.
  Stream<ModelDownloadProgress> start(String modelId) =>
      legacy.RunAnywhere.downloadModel(modelId);

  /// Delete a stored model from disk.
  Future<void> delete(String modelId) =>
      legacy.RunAnywhere.deleteStoredModel(modelId);

  /// Storage info: device free/total bytes, app bytes used, model count.
  Future<StorageInfo> getStorageInfo() =>
      legacy.RunAnywhere.getStorageInfo();

  /// List downloaded models with on-disk size info.
  Future<List<StoredModel>> list() =>
      legacy.RunAnywhere.getDownloadedModelsWithInfo();
}
