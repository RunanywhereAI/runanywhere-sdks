import 'dart:async';

import '../../models/model/model_info.dart';
import 'download_task.dart';

/// Protocol for download management operations
/// Matches iOS DownloadManager from Core/Protocols/Downloading/DownloadManager.swift
abstract class DownloadManager {
  /// Download a model
  /// - Parameter model: The model to download
  /// - Returns: A download task tracking the download
  /// - Throws: An error if download setup fails
  Future<DownloadTask> downloadModel(ModelInfo model);

  /// Cancel a download
  /// - Parameter taskId: The ID of the task to cancel
  void cancelDownload(String taskId);

  /// Get all active downloads
  /// - Returns: List of active download tasks
  List<DownloadTask> activeDownloads();
}
