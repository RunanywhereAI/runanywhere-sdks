/// Main SDK error type
/// Matches iOS RunAnywhereError from Foundation/Errors/RunAnywhereError.swift
///
/// Note: Also exported as [RunAnywhereError] for iOS parity
class SDKError implements Exception {
  final String message;
  final SDKErrorType type;

  /// The underlying error that caused this SDK error (if any)
  /// Matches iOS RunAnywhereError.underlyingError
  final Object? underlyingError;

  SDKError(this.message, this.type, {this.underlyingError});

  @override
  String toString() => 'SDKError($type): $message';

  /// Recovery suggestion for the error
  /// Matches iOS RunAnywhereError.recoverySuggestion
  String? get recoverySuggestion {
    switch (type) {
      case SDKErrorType.notInitialized:
        return 'Call RunAnywhere.initialize() before using the SDK.';
      case SDKErrorType.invalidAPIKey:
        return 'Provide a valid API key in the configuration.';
      case SDKErrorType.invalidConfiguration:
        return 'Check your configuration settings and ensure all required fields are provided.';

      case SDKErrorType.modelNotFound:
        return 'Check the model identifier or download the model first.';
      case SDKErrorType.modelLoadFailed:
        return 'Ensure the model file is not corrupted and is compatible with your device.';
      case SDKErrorType.modelValidationFailed:
        return 'The model file may be corrupted or incompatible. Try re-downloading.';
      case SDKErrorType.modelIncompatible:
        return 'Use a different model that is compatible with your device.';
      case SDKErrorType.frameworkNotAvailable:
        return 'Use a different model or device that supports this feature.';

      case SDKErrorType.generationFailed:
        return 'Check your input and try again.';
      case SDKErrorType.generationTimeout:
        return 'Try with a shorter prompt or fewer tokens.';
      case SDKErrorType.contextTooLong:
        return 'Reduce the context size or use a model with larger context window.';
      case SDKErrorType.tokenLimitExceeded:
        return 'Reduce the number of tokens requested.';

      case SDKErrorType.networkError:
      case SDKErrorType.networkUnavailable:
      case SDKErrorType.requestFailed:
      case SDKErrorType.serverError:
        return 'Check your internet connection and try again.';
      case SDKErrorType.downloadFailed:
        return 'Check your internet connection and available storage space.';
      case SDKErrorType.timeout:
        return 'The operation timed out. Try again or check your network connection.';

      case SDKErrorType.storageError:
      case SDKErrorType.insufficientStorage:
        return 'Free up storage space on your device.';
      case SDKErrorType.storageFull:
        return 'Delete unnecessary files to free up space.';

      case SDKErrorType.hardwareUnsupported:
        return 'Use a different model or device that supports this feature.';
      case SDKErrorType.memoryPressure:
        return 'Close other apps to free up memory.';
      case SDKErrorType.thermalStateExceeded:
        return 'Wait for the device to cool down before trying again.';

      case SDKErrorType.componentNotReady:
      case SDKErrorType.componentNotInitialized:
        return 'Ensure the component is properly initialized before use.';
      case SDKErrorType.invalidState:
        return 'Check the current state and ensure operations are called in the correct order.';

      case SDKErrorType.validationFailed:
        return 'Check your input parameters and ensure they are valid.';

      case SDKErrorType.featureNotAvailable:
      case SDKErrorType.notImplemented:
        return 'This feature may be available in a future update.';
    }
  }

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
      underlyingError: error,
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

/// Type alias for iOS parity
/// iOS uses RunAnywhereError; this alias provides compatibility
typedef RunAnywhereError = SDKError;

/// Type alias for iOS parity
/// iOS uses ErrorCategory; this alias provides compatibility
typedef ErrorCategory = SDKErrorType;
