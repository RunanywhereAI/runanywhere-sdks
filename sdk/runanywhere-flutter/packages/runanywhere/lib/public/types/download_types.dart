/// Download Types
///
/// Types for model download progress and state.
/// Mirrors Swift DownloadProgress.
library download_types;

/// Download progress information
/// Matches Swift `DownloadProgress`.
class DownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final DownloadProgressState state;
  final DownloadProgressStage stage;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.state,
    this.stage = DownloadProgressStage.downloading,
  });

  /// Overall progress from 0.0 to 1.0
  double get overallProgress =>
      totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;

  /// Legacy alias for overallProgress
  double get percentage => overallProgress;
}

/// Download progress state
enum DownloadProgressState {
  downloading,
  completed,
  failed,
  cancelled;

  bool get isCompleted => this == DownloadProgressState.completed;
  bool get isFailed => this == DownloadProgressState.failed;
}

/// Download progress stage (more detailed than state)
enum DownloadProgressStage {
  queued,
  downloading,
  extracting,
  verifying,
  completed,
  failed,
  cancelled,
}
