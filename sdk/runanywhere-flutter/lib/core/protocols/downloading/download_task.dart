import 'dart:async';

import 'download_progress.dart';

/// Download task information
/// Matches iOS DownloadTask from Data/Models/Downloading/DownloadTask.swift
class DownloadTask {
  /// Unique task identifier
  final String id;

  /// Model identifier being downloaded
  final String modelId;

  /// Stream of progress updates
  final Stream<DownloadProgress> progress;

  /// Future that completes with the download result (file URI)
  final Future<Uri> result;

  const DownloadTask({
    required this.id,
    required this.modelId,
    required this.progress,
    required this.result,
  });

  @override
  String toString() => 'DownloadTask(id: $id, modelId: $modelId)';
}
