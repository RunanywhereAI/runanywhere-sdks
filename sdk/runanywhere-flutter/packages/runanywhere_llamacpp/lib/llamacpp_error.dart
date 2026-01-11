/// LlamaCpp specific errors.
///
/// This is the Flutter equivalent of Swift's `LLMSwiftError`.
class LlamaCppError implements Exception {
  final String message;
  final LlamaCppErrorType type;

  const LlamaCppError._(this.message, this.type);

  /// Model failed to load.
  factory LlamaCppError.modelLoadFailed([String? details]) {
    return LlamaCppError._(
      details ?? 'Failed to load the LLM model',
      LlamaCppErrorType.modelLoadFailed,
    );
  }

  /// Service not initialized.
  factory LlamaCppError.notInitialized() {
    return const LlamaCppError._(
      'LLM service not initialized',
      LlamaCppErrorType.notInitialized,
    );
  }

  /// Generation failed.
  factory LlamaCppError.generationFailed(String reason) {
    return LlamaCppError._(
      'Generation failed: $reason',
      LlamaCppErrorType.generationFailed,
    );
  }

  /// Template resolution failed.
  factory LlamaCppError.templateResolutionFailed(String reason) {
    return LlamaCppError._(
      'Template resolution failed: $reason',
      LlamaCppErrorType.templateResolutionFailed,
    );
  }

  /// Model not found.
  factory LlamaCppError.modelNotFound(String path) {
    return LlamaCppError._(
      'Model not found at: $path',
      LlamaCppErrorType.modelNotFound,
    );
  }

  /// Timeout error.
  factory LlamaCppError.timeout(Duration duration) {
    return LlamaCppError._(
      'Generation timed out after ${duration.inSeconds} seconds',
      LlamaCppErrorType.timeout,
    );
  }

  @override
  String toString() => 'LlamaCppError: $message';
}

/// Types of LlamaCpp errors.
enum LlamaCppErrorType {
  modelLoadFailed,
  notInitialized,
  generationFailed,
  templateResolutionFailed,
  modelNotFound,
  timeout,
}
