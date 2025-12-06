/// Download state enumeration
/// Matches iOS DownloadState from Data/Models/Downloading/DownloadState.swift
sealed class DownloadState {
  const DownloadState();

  /// Convenience getter to check if download is completed
  bool get isCompleted => this is DownloadStateCompleted;

  /// Convenience getter to check if download failed
  bool get isFailed => this is DownloadStateFailed;

  /// Convenience getter to check if download is pending
  bool get isPending => this is DownloadStatePending;

  /// Convenience getter to check if download is in progress
  bool get isDownloading => this is DownloadStateDownloading;

  /// Convenience getter to check if download was cancelled
  bool get isCancelled => this is DownloadStateCancelled;

  /// Convenience getter to check if download is extracting
  bool get isExtracting => this is DownloadStateExtracting;
}

/// Download is pending, waiting to start
class DownloadStatePending extends DownloadState {
  const DownloadStatePending();

  @override
  String toString() => 'DownloadState.pending';
}

/// Download is in progress
class DownloadStateDownloading extends DownloadState {
  const DownloadStateDownloading();

  @override
  String toString() => 'DownloadState.downloading';
}

/// Downloaded file is being extracted
class DownloadStateExtracting extends DownloadState {
  const DownloadStateExtracting();

  @override
  String toString() => 'DownloadState.extracting';
}

/// Download is being retried
class DownloadStateRetrying extends DownloadState {
  final int attempt;

  const DownloadStateRetrying(this.attempt);

  @override
  String toString() => 'DownloadState.retrying(attempt: $attempt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadStateRetrying &&
          runtimeType == other.runtimeType &&
          attempt == other.attempt;

  @override
  int get hashCode => attempt.hashCode;
}

/// Download completed successfully
class DownloadStateCompleted extends DownloadState {
  const DownloadStateCompleted();

  @override
  String toString() => 'DownloadState.completed';
}

/// Download failed with an error
class DownloadStateFailed extends DownloadState {
  final Object error;

  const DownloadStateFailed(this.error);

  @override
  String toString() => 'DownloadState.failed($error)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadStateFailed &&
          runtimeType == other.runtimeType &&
          error == other.error;

  @override
  int get hashCode => error.hashCode;
}

/// Download was cancelled
class DownloadStateCancelled extends DownloadState {
  const DownloadStateCancelled();

  @override
  String toString() => 'DownloadState.cancelled';
}
