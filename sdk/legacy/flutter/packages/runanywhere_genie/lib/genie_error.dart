/// Genie specific errors.
///
/// This is the Flutter equivalent of Genie-specific error handling.
class GenieError implements Exception {
  final String message;
  final GenieErrorType type;

  const GenieError._(this.message, this.type);

  /// Model failed to load.
  factory GenieError.modelLoadFailed([String? details]) {
    return GenieError._(
      details ?? 'Failed to load the NPU model',
      GenieErrorType.modelLoadFailed,
    );
  }

  /// Service not initialized.
  factory GenieError.notInitialized() {
    return const GenieError._(
      'Genie service not initialized',
      GenieErrorType.notInitialized,
    );
  }

  /// Generation failed.
  factory GenieError.generationFailed(String reason) {
    return GenieError._(
      'Generation failed: $reason',
      GenieErrorType.generationFailed,
    );
  }

  /// Model not found.
  factory GenieError.modelNotFound(String path) {
    return GenieError._(
      'Model not found at: $path',
      GenieErrorType.modelNotFound,
    );
  }

  /// Timeout error.
  factory GenieError.timeout(Duration duration) {
    return GenieError._(
      'Generation timed out after ${duration.inSeconds} seconds',
      GenieErrorType.timeout,
    );
  }

  /// Platform not supported (Genie is Android/Snapdragon only).
  factory GenieError.platformNotSupported([String? platform]) {
    return GenieError._(
      'Genie NPU is not supported on ${platform ?? 'this platform'}. '
      'Genie requires Android with Snapdragon NPU.',
      GenieErrorType.platformNotSupported,
    );
  }

  @override
  String toString() => 'GenieError: $message';
}

/// Types of Genie errors.
enum GenieErrorType {
  modelLoadFailed,
  notInitialized,
  generationFailed,
  modelNotFound,
  timeout,
  platformNotSupported,
}
