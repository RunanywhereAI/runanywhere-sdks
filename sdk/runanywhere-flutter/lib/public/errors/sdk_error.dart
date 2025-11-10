/// SDK Error types
/// Similar to Swift SDK's SDKError
class SDKError extends Error implements Exception {
  final String message;
  final String? code;
  final Object? underlyingError;

  SDKError(this.message, {this.code, this.underlyingError});

  // Factory constructors for common errors
  factory SDKError.notInitialized() {
    return SDKError(
      'SDK has not been initialized. Call RunAnywhere.initialize() first.',
      code: 'NOT_INITIALIZED',
    );
  }

  factory SDKError.invalidAPIKey(String reason) {
    return SDKError(
      'Invalid API key: $reason',
      code: 'INVALID_API_KEY',
    );
  }

  factory SDKError.networkError(String message) {
    return SDKError(
      'Network error: $message',
      code: 'NETWORK_ERROR',
    );
  }

  factory SDKError.timeout(String message) {
    return SDKError(
      'Timeout: $message',
      code: 'TIMEOUT',
    );
  }

  factory SDKError.storageError(String message) {
    return SDKError(
      'Storage error: $message',
      code: 'STORAGE_ERROR',
    );
  }

  factory SDKError.validationFailed(String message) {
    return SDKError(
      'Validation failed: $message',
      code: 'VALIDATION_FAILED',
    );
  }

  factory SDKError.invalidState(String message) {
    return SDKError(
      'Invalid state: $message',
      code: 'INVALID_STATE',
    );
  }

  factory SDKError.serverError(String message) {
    return SDKError(
      'Server error: $message',
      code: 'SERVER_ERROR',
    );
  }

  @override
  String toString() {
    if (code != null) {
      return 'SDKError($code): $message';
    }
    return 'SDKError: $message';
  }
}

