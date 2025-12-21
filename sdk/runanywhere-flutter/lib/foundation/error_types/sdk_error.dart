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
      case SDKErrorType.alreadyInitialized:
        return 'The SDK is already initialized. You can use it directly.';
      case SDKErrorType.invalidAPIKey:
        return 'Provide a valid API key in the configuration.';
      case SDKErrorType.invalidConfiguration:
        return 'Check your configuration settings and ensure all required fields are provided.';
      case SDKErrorType.environmentMismatch:
        return 'Use .development or .staging for DEBUG builds. Production environment requires a Release build.';

      case SDKErrorType.modelNotFound:
        return 'Check the model identifier or download the model first.';
      case SDKErrorType.modelLoadFailed:
        return 'Ensure the model file is not corrupted and is compatible with your device.';
      case SDKErrorType.loadingFailed:
        return 'The loading operation failed. Check logs for details.';
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
      case SDKErrorType.costLimitExceeded:
        return 'Increase your cost limit or use a more cost-effective model.';

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

      case SDKErrorType.authenticationFailed:
        return 'Check your credentials and try again.';

      case SDKErrorType.databaseInitializationFailed:
        return 'Try reinstalling the app or clearing app data.';

      case SDKErrorType.validationFailed:
        return 'Check your input parameters and ensure they are valid.';
      case SDKErrorType.unsupportedModality:
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

  static SDKError alreadyInitialized([String? message]) {
    return SDKError(
      message ?? 'SDK is already initialized',
      SDKErrorType.alreadyInitialized,
    );
  }

  static SDKError invalidAPIKey([String? message]) {
    return SDKError(
      message ?? 'Invalid API key',
      SDKErrorType.invalidAPIKey,
    );
  }

  static SDKError invalidConfiguration([String? message]) {
    return SDKError(
      message ?? 'Invalid configuration',
      SDKErrorType.invalidConfiguration,
    );
  }

  static SDKError environmentMismatch([String? message]) {
    return SDKError(
      message ?? 'Environment configuration mismatch',
      SDKErrorType.environmentMismatch,
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
      message ?? 'Loading failed',
      SDKErrorType.loadingFailed,
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

  static SDKError generationTimeout([String? message]) {
    return SDKError(
      message ?? 'Generation timed out',
      SDKErrorType.generationTimeout,
    );
  }

  static SDKError contextTooLong(int provided, int maximum) {
    return SDKError(
      'Context too long: $provided tokens (maximum: $maximum)',
      SDKErrorType.contextTooLong,
    );
  }

  static SDKError tokenLimitExceeded(int requested, int maximum) {
    return SDKError(
      'Token limit exceeded: requested $requested, maximum $maximum',
      SDKErrorType.tokenLimitExceeded,
    );
  }

  static SDKError costLimitExceeded(double estimated, double limit) {
    return SDKError(
      'Cost limit exceeded: estimated \$${estimated.toStringAsFixed(2)}, limit \$${limit.toStringAsFixed(2)}',
      SDKErrorType.costLimitExceeded,
    );
  }

  static SDKError authenticationFailed([String? message]) {
    return SDKError(
      message ?? 'Authentication failed',
      SDKErrorType.authenticationFailed,
    );
  }

  static SDKError databaseInitializationFailed(Object error) {
    return SDKError(
      'Database initialization failed: $error',
      SDKErrorType.databaseInitializationFailed,
      underlyingError: error,
    );
  }

  static SDKError unsupportedModality([String? message]) {
    return SDKError(
      message ?? 'Unsupported modality',
      SDKErrorType.unsupportedModality,
    );
  }

  static SDKError insufficientStorage(int required, int available) {
    return SDKError(
      'Insufficient storage: $required bytes required, $available bytes available',
      SDKErrorType.insufficientStorage,
    );
  }

  static SDKError hardwareUnsupported([String? message]) {
    return SDKError(
      message ?? 'Hardware not supported',
      SDKErrorType.hardwareUnsupported,
    );
  }

  static SDKError serverError([String? message]) {
    return SDKError(
      message ?? 'Server error occurred',
      SDKErrorType.serverError,
    );
  }

  static SDKError requestFailed(Object error) {
    return SDKError(
      'Request failed: $error',
      SDKErrorType.requestFailed,
      underlyingError: error,
    );
  }

  static SDKError networkUnavailable([String? message]) {
    return SDKError(
      message ?? 'Network connection unavailable',
      SDKErrorType.networkUnavailable,
    );
  }

  static SDKError modelValidationFailed(String modelId, List<String> errors) {
    return SDKError(
      'Model \'$modelId\' validation failed: ${errors.join(', ')}',
      SDKErrorType.modelValidationFailed,
    );
  }

  static SDKError modelIncompatible(String modelId, String reason) {
    return SDKError(
      'Model \'$modelId\' is incompatible: $reason',
      SDKErrorType.modelIncompatible,
    );
  }

  static SDKError frameworkNotAvailable([String? message]) {
    return SDKError(
      message ?? 'Required framework not available',
      SDKErrorType.frameworkNotAvailable,
    );
  }
}

/// SDK error types
/// Matches iOS RunAnywhereError cases
enum SDKErrorType {
  // Initialization errors
  notInitialized,
  alreadyInitialized,
  invalidAPIKey,
  invalidConfiguration,
  environmentMismatch,

  // Model errors
  modelNotFound,
  modelLoadFailed,
  loadingFailed, // Separate from modelLoadFailed for iOS parity
  modelValidationFailed,
  modelIncompatible,
  frameworkNotAvailable,

  // Generation errors
  generationFailed,
  generationTimeout,
  contextTooLong,
  tokenLimitExceeded,
  costLimitExceeded,

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

  // Authentication errors
  authenticationFailed,

  // Database errors
  databaseInitializationFailed,

  // Feature errors
  featureNotAvailable,
  notImplemented,

  // Validation errors
  validationFailed,
  unsupportedModality,

  // General errors
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
