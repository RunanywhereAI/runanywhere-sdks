/// Main SDK error type
class SDKError implements Exception {
  final String message;
  final SDKErrorType type;

  SDKError(this.message, this.type);

  @override
  String toString() => 'SDKError($type): $message';

  // Factory constructors for common errors
  static SDKError notInitialized([String? message]) {
    return SDKError(
      message ?? 'SDK has not been initialized',
      SDKErrorType.notInitialized,
    );
  }

  static SDKError invalidAPIKey([String? message]) {
    return SDKError(
      message ?? 'Invalid API key',
      SDKErrorType.invalidAPIKey,
    );
  }

  static SDKError modelNotFound(String modelId) {
    return SDKError(
      'Model not found: $modelId',
      SDKErrorType.modelNotFound,
    );
  }

  static SDKError modelLoadFailed(String modelId, Object error) {
    return SDKError(
      'Model load failed: $modelId - $error',
      SDKErrorType.modelLoadFailed,
    );
  }

  static SDKError loadingFailed([String? message]) {
    return SDKError(
      message ?? 'Model loading failed',
      SDKErrorType.modelLoadFailed,
    );
  }

  static SDKError featureNotAvailable([String? message]) {
    return SDKError(
      message ?? 'Feature not available',
      SDKErrorType.featureNotAvailable,
    );
  }

  static SDKError componentNotReady(String component) {
    return SDKError(
      'Component not ready: $component',
      SDKErrorType.componentNotReady,
    );
  }

  static SDKError networkError([String? message]) {
    return SDKError(
      message ?? 'Network error occurred',
      SDKErrorType.networkError,
    );
  }

  static SDKError storageError([String? message]) {
    return SDKError(
      message ?? 'Storage error occurred',
      SDKErrorType.storageError,
    );
  }

  static SDKError validationFailed([String? message]) {
    return SDKError(
      message ?? 'Validation failed',
      SDKErrorType.validationFailed,
    );
  }

  static SDKError invalidState([String? message]) {
    return SDKError(
      message ?? 'Invalid state',
      SDKErrorType.invalidState,
    );
  }

  static SDKError timeout([String? message]) {
    return SDKError(
      message ?? 'Operation timed out',
      SDKErrorType.timeout,
    );
  }

  static SDKError downloadFailed([String? message]) {
    return SDKError(
      message ?? 'Download failed',
      SDKErrorType.downloadFailed,
    );
  }

  static SDKError generationFailed([String? message]) {
    return SDKError(
      message ?? 'Generation failed',
      SDKErrorType.generationFailed,
    );
  }
}

/// SDK error types
enum SDKErrorType {
  // Initialization errors
  notInitialized,
  invalidAPIKey,
  invalidConfiguration,

  // Model errors
  modelNotFound,
  modelLoadFailed,
  modelValidationFailed,
  modelIncompatible,
  frameworkNotAvailable,

  // Generation errors
  generationFailed,
  generationTimeout,
  contextTooLong,
  tokenLimitExceeded,

  // Network errors
  networkError,
  networkUnavailable,
  requestFailed,
  downloadFailed,

  // Storage errors
  storageError,
  insufficientStorage,
  storageFull,

  // Hardware errors
  hardwareUnsupported,
  memoryPressure,
  thermalStateExceeded,

  // Component errors
  componentNotReady,
  componentNotInitialized,

  // Feature errors
  featureNotAvailable,
  notImplemented,

  // General errors
  validationFailed,
  invalidState,
  timeout,
  serverError,
}

