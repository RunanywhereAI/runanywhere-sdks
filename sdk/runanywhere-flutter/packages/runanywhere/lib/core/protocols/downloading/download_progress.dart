import 'package:runanywhere/core/protocols/downloading/download_state.dart';

/// Download progress information
/// Matches iOS DownloadProgress from Data/Models/Downloading/DownloadProgress.swift
class DownloadProgress {
  /// Bytes downloaded so far
  final int bytesDownloaded;

  /// Total bytes to download
  final int totalBytes;

  /// Current download state
  final DownloadState state;

  /// Estimated time remaining in seconds
  final double? estimatedTimeRemaining;

  /// Download speed in bytes per second
  final double? speed;

  /// Download percentage (0.0 to 1.0)
  final double percentage;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.state,
    this.estimatedTimeRemaining,
    this.speed,
    double? percentage,
  }) : percentage =
            percentage ?? (totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0);

  /// Create progress for downloading state
  factory DownloadProgress.downloading({
    required int bytesDownloaded,
    required int totalBytes,
    double? speed,
    double? estimatedTimeRemaining,
  }) {
    return DownloadProgress(
      bytesDownloaded: bytesDownloaded,
      totalBytes: totalBytes,
      state: const DownloadStateDownloading(),
      speed: speed,
      estimatedTimeRemaining: estimatedTimeRemaining,
    );
  }

  /// Create progress for pending state
  factory DownloadProgress.pending({int totalBytes = 0}) {
    return DownloadProgress(
      bytesDownloaded: 0,
      totalBytes: totalBytes,
      state: const DownloadStatePending(),
    );
  }

  /// Create progress for completed state
  factory DownloadProgress.completed({required int totalBytes}) {
    return DownloadProgress(
      bytesDownloaded: totalBytes,
      totalBytes: totalBytes,
      state: const DownloadStateCompleted(),
      percentage: 1.0,
    );
  }

  /// Create progress for failed state
  factory DownloadProgress.failed(Object error,
      {int bytesDownloaded = 0, int totalBytes = 0}) {
    return DownloadProgress(
      bytesDownloaded: bytesDownloaded,
      totalBytes: totalBytes,
      state: DownloadStateFailed(error),
    );
  }

  /// Create a copy with modified fields
  DownloadProgress copyWith({
    int? bytesDownloaded,
    int? totalBytes,
    DownloadState? state,
    double? estimatedTimeRemaining,
    double? speed,
    double? percentage,
  }) {
    return DownloadProgress(
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      state: state ?? this.state,
      estimatedTimeRemaining:
          estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      speed: speed ?? this.speed,
      percentage: percentage ?? this.percentage,
    );
  }

  @override
  String toString() =>
      'DownloadProgress(${(percentage * 100).toStringAsFixed(1)}%, state: $state)';
}
