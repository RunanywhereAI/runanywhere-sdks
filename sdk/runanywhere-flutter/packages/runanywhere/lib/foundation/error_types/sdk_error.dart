import 'package:runanywhere/foundation/error_types/error_category.dart';
import 'package:runanywhere/foundation/error_types/error_code.dart';
import 'package:runanywhere/foundation/error_types/error_context.dart';

export 'error_category.dart';
export 'error_code.dart';
export 'error_context.dart';

/// Main SDK error type
/// Matches iOS RunAnywhereError from Public/Errors/RunAnywhereError.swift
///
/// Note: Also exported as [RunAnywhereError] for iOS parity
class SDKError implements Exception {
  final String message;
  final SDKErrorType type;

  /// The underlying error that caused this SDK error (if any)
  /// Matches iOS RunAnywhereError.underlyingError
  final Object? underlyingError;

  /// Error context with stack trace and location info
  final ErrorContext? context;

  SDKError(
    this.message,
    this.type, {
    this.underlyingError,
    this.context,
  });

  @override
  String toString() => 'SDKError($type): $message';

  /// The error code for machine-readable identification
  /// Matches iOS SDKErrorProtocol.code
  ErrorCode get code {
    switch (type) {
      case SDKErrorType.notInitialized:
        return ErrorCode.notInitialized;
      case SDKErrorType.alreadyInitialized:
        return ErrorCode.alreadyInitialized;
      case SDKErrorType.invalidAPIKey:
        return ErrorCode.apiKeyInvalid;
      case SDKErrorType.invalidConfiguration:
        return ErrorCode.invalidInput;
      case SDKErrorType.environmentMismatch:
        return ErrorCode.invalidInput;
      case SDKErrorType.modelNotFound:
        return ErrorCode.modelNotFound;
      case SDKErrorType.modelNotDownloaded:
        return ErrorCode.modelNotFound;
      case SDKErrorType.modelLoadFailed:
        return ErrorCode.modelLoadFailed;
      case SDKErrorType.loadingFailed:
        return ErrorCode.modelLoadFailed;
      case SDKErrorType.modelValidationFailed:
        return ErrorCode.modelValidationFailed;
      case SDKErrorType.modelIncompatible:
        return ErrorCode.modelIncompatible;
      case SDKErrorType.frameworkNotAvailable:
        return ErrorCode.hardwareUnavailable;
      case SDKErrorType.sttNotAvailable:
        return ErrorCode.hardwareUnavailable;
      case SDKErrorType.ttsNotAvailable:
        return ErrorCode.hardwareUnavailable;
      case SDKErrorType.generationFailed:
        return ErrorCode.generationFailed;
      case SDKErrorType.generationTimeout:
        return ErrorCode.generationTimeout;
      case SDKErrorType.contextTooLong:
        return ErrorCode.contextTooLong;
      case SDKErrorType.tokenLimitExceeded:
        return ErrorCode.tokenLimitExceeded;
      case SDKErrorType.costLimitExceeded:
        return ErrorCode.costLimitExceeded;
      case SDKErrorType.networkError:
        return ErrorCode.apiError;
      case SDKErrorType.networkUnavailable:
        return ErrorCode.networkUnavailable;
      case SDKErrorType.requestFailed:
        return ErrorCode.apiError;
      case SDKErrorType.downloadFailed:
        return ErrorCode.downloadFailed;
      case SDKErrorType.timeout:
        return ErrorCode.networkTimeout;
      case SDKErrorType.storageError:
        return ErrorCode.fileAccessDenied;
      case SDKErrorType.insufficientStorage:
        return ErrorCode.insufficientStorage;
      case SDKErrorType.storageFull:
        return ErrorCode.storageFull;
      case SDKErrorType.hardwareUnsupported:
        return ErrorCode.hardwareUnsupported;
      case SDKErrorType.memoryPressure:
        return ErrorCode.hardwareUnavailable;
      case SDKErrorType.thermalStateExceeded:
        return ErrorCode.hardwareUnavailable;
      case SDKErrorType.componentNotReady:
        return ErrorCode.notInitialized;
      case SDKErrorType.componentNotInitialized:
        return ErrorCode.notInitialized;
      case SDKErrorType.authenticationFailed:
        return ErrorCode.authenticationFailed;
      case SDKErrorType.databaseInitializationFailed:
        return ErrorCode.unknown;
      case SDKErrorType.featureNotAvailable:
        return ErrorCode.unknown;
      case SDKErrorType.notImplemented:
        return ErrorCode.unknown;
      case SDKErrorType.validationFailed:
        return ErrorCode.invalidInput;
      case SDKErrorType.unsupportedModality:
        return ErrorCode.invalidInput;
      case SDKErrorType.invalidState:
        return ErrorCode.invalidInput;
      case SDKErrorType.serverError:
        return ErrorCode.apiError;
      case SDKErrorType.rateLimitExceeded:
        return ErrorCode.apiError;
      case SDKErrorType.serviceUnavailable:
        return ErrorCode.apiError;
      case SDKErrorType.invalidInput:
        return ErrorCode.invalidInput;
      case SDKErrorType.resourceExhausted:
        return ErrorCode.insufficientStorage;
      case SDKErrorType.internalError:
        return ErrorCode.unknown;
    }
  }

  /// The category of this error for grouping/filtering
  /// Matches iOS SDKErrorProtocol.category
  ErrorCategory get category {
    switch (type) {
      case SDKErrorType.notInitialized:
      case SDKErrorType.alreadyInitialized:
      case SDKErrorType.invalidAPIKey:
      case SDKErrorType.invalidConfiguration:
      case SDKErrorType.environmentMismatch:
        return ErrorCategory.initialization;
      case SDKErrorType.modelNotFound:
      case SDKErrorType.modelNotDownloaded:
      case SDKErrorType.modelLoadFailed:
      case SDKErrorType.loadingFailed:
      case SDKErrorType.modelValidationFailed:
      case SDKErrorType.modelIncompatible:
      case SDKErrorType.sttNotAvailable:
      case SDKErrorType.ttsNotAvailable:
        return ErrorCategory.model;
      case SDKErrorType.generationFailed:
      case SDKErrorType.generationTimeout:
      case SDKErrorType.contextTooLong:
      case SDKErrorType.tokenLimitExceeded:
      case SDKErrorType.costLimitExceeded:
        return ErrorCategory.generation;
      case SDKErrorType.networkError:
      case SDKErrorType.networkUnavailable:
      case SDKErrorType.requestFailed:
      case SDKErrorType.downloadFailed:
      case SDKErrorType.timeout:
      case SDKErrorType.serverError:
      case SDKErrorType.rateLimitExceeded:
      case SDKErrorType.serviceUnavailable:
        return ErrorCategory.network;
      case SDKErrorType.storageError:
      case SDKErrorType.insufficientStorage:
      case SDKErrorType.storageFull:
      case SDKErrorType.resourceExhausted:
        return ErrorCategory.storage;
      case SDKErrorType.hardwareUnsupported:
      case SDKErrorType.memoryPressure:
      case SDKErrorType.thermalStateExceeded:
        return ErrorCategory.hardware;
      case SDKErrorType.componentNotReady:
      case SDKErrorType.componentNotInitialized:
      case SDKErrorType.invalidState:
        return ErrorCategory.component;
      case SDKErrorType.authenticationFailed:
        return ErrorCategory.authentication;
      case SDKErrorType.frameworkNotAvailable:
      case SDKErrorType.databaseInitializationFailed:
        return ErrorCategory.framework;
      case SDKErrorType.validationFailed:
      case SDKErrorType.unsupportedModality:
      case SDKErrorType.invalidInput:
        return ErrorCategory.validation;
      case SDKErrorType.featureNotAvailable:
      case SDKErrorType.notImplemented:
      case SDKErrorType.internalError:
        return ErrorCategory.unknown;
    }
  }

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
      case SDKErrorType.modelNotDownloaded:
        return 'Download the model first using RunAnywhere.downloadModel().';
      case SDKErrorType.modelLoadFailed:
        return 'Ensure the model file is not corrupted and is compatible with your device.';
      case SDKErrorType.sttNotAvailable:
        return 'Register an STT provider (e.g., ONNX) before using speech recognition.';
      case SDKErrorType.ttsNotAvailable:
        return 'Register a TTS provider (e.g., ONNX) before using text-to-speech.';
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
      case SDKErrorType.rateLimitExceeded:
        return 'You have exceeded the rate limit. Please wait before trying again.';
      case SDKErrorType.serviceUnavailable:
        return 'The service is temporarily unavailable. Please try again later.';

      case SDKErrorType.storageError:
      case SDKErrorType.insufficientStorage:
      case SDKErrorType.resourceExhausted:
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
      case SDKErrorType.unsupportedModality:
      case SDKErrorType.invalidInput:
        return 'Check your input parameters and ensure they are valid.';

      case SDKErrorType.featureNotAvailable:
      case SDKErrorType.notImplemented:
        return 'This feature may be available in a future update.';

      case SDKErrorType.internalError:
        return 'An internal error occurred. Please report this issue.';
    }
  }

  // Factory constructors for common errors
  static SDKError notInitialized([String? message]) {
    return SDKError(
      message ?? 'RunAnywhere SDK is not initialized. Call initialize() first.',
      SDKErrorType.notInitialized,
    );
  }

  static SDKError alreadyInitialized([String? message]) {
    return SDKError(
      message ?? 'RunAnywhere SDK is already initialized.',
      SDKErrorType.alreadyInitialized,
    );
  }

  static SDKError invalidAPIKey([String? message]) {
    return SDKError(
      message ?? 'Invalid or missing API key.',
      SDKErrorType.invalidAPIKey,
    );
  }

  static SDKError invalidConfiguration(String detail) {
    return SDKError(
      'Invalid configuration: $detail',
      SDKErrorType.invalidConfiguration,
    );
  }

  static SDKError environmentMismatch(String reason) {
    return SDKError(
      'Environment configuration mismatch: $reason',
      SDKErrorType.environmentMismatch,
    );
  }

  static SDKError modelNotFound(String modelId) {
    return SDKError(
      'Model \'$modelId\' not found.',
      SDKErrorType.modelNotFound,
    );
  }

  static SDKError modelLoadFailed(String modelId, Object? error) {
    return SDKError(
      error != null
          ? 'Failed to load model \'$modelId\': $error'
          : 'Failed to load model \'$modelId\'',
      SDKErrorType.modelLoadFailed,
      underlyingError: error,
    );
  }

  static SDKError loadingFailed(String reason) {
    return SDKError(
      'Failed to load: $reason',
      SDKErrorType.loadingFailed,
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

  /// Model not downloaded error
  static SDKError modelNotDownloaded(String message) {
    return SDKError(
      message,
      SDKErrorType.modelNotDownloaded,
    );
  }

  /// STT service not available
  static SDKError sttNotAvailable(String message) {
    return SDKError(
      message,
      SDKErrorType.sttNotAvailable,
    );
  }

  /// TTS service not available
  static SDKError ttsNotAvailable(String message) {
    return SDKError(
      message,
      SDKErrorType.ttsNotAvailable,
    );
  }

  static SDKError generationFailed(String reason) {
    return SDKError(
      'Text generation failed: $reason',
      SDKErrorType.generationFailed,
    );
  }

  static SDKError generationTimeout([String? reason]) {
    return SDKError(
      reason != null
          ? 'Generation timed out: $reason'
          : 'Text generation timed out.',
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

  static SDKError networkUnavailable([String? message]) {
    return SDKError(
      message ?? 'Network connection unavailable.',
      SDKErrorType.networkUnavailable,
    );
  }

  static SDKError networkError(String reason) {
    return SDKError(
      'Network error: $reason',
      SDKErrorType.networkError,
    );
  }

  static SDKError requestFailed(Object error) {
    return SDKError(
      'Request failed: $error',
      SDKErrorType.requestFailed,
      underlyingError: error,
    );
  }

  static SDKError downloadFailed(String url, Object? error) {
    return SDKError(
      error != null
          ? 'Failed to download from \'$url\': $error'
          : 'Failed to download from \'$url\'',
      SDKErrorType.downloadFailed,
      underlyingError: error,
    );
  }

  static SDKError serverError(String reason) {
    return SDKError(
      'Server error: $reason',
      SDKErrorType.serverError,
    );
  }

  static SDKError timeout(String reason) {
    return SDKError(
      'Operation timed out: $reason',
      SDKErrorType.timeout,
    );
  }

  static SDKError insufficientStorage(int required, int available) {
    return SDKError(
      'Insufficient storage: ${_formatBytes(required)} required, ${_formatBytes(available)} available',
      SDKErrorType.insufficientStorage,
    );
  }

  static SDKError storageFull([String? message]) {
    return SDKError(
      message ?? 'Device storage is full.',
      SDKErrorType.storageFull,
    );
  }

  static SDKError storageError(String reason) {
    return SDKError(
      'Storage error: $reason',
      SDKErrorType.storageError,
    );
  }

  static SDKError hardwareUnsupported(String feature) {
    return SDKError(
      'Hardware does not support $feature.',
      SDKErrorType.hardwareUnsupported,
    );
  }

  static SDKError componentNotInitialized(String component) {
    return SDKError(
      'Component not initialized: $component',
      SDKErrorType.componentNotInitialized,
    );
  }

  static SDKError componentNotReady(String component) {
    return SDKError(
      'Component not ready: $component',
      SDKErrorType.componentNotReady,
    );
  }

  static SDKError invalidState(String reason) {
    return SDKError(
      'Invalid state: $reason',
      SDKErrorType.invalidState,
    );
  }

  static SDKError validationFailed(String reason) {
    return SDKError(
      'Validation failed: $reason',
      SDKErrorType.validationFailed,
    );
  }

  static SDKError unsupportedModality(String modality) {
    return SDKError(
      'Unsupported modality: $modality',
      SDKErrorType.unsupportedModality,
    );
  }

  static SDKError authenticationFailed(String reason) {
    return SDKError(
      'Authentication failed: $reason',
      SDKErrorType.authenticationFailed,
    );
  }

  static SDKError frameworkNotAvailable(String framework) {
    return SDKError(
      'Framework $framework not available',
      SDKErrorType.frameworkNotAvailable,
    );
  }

  static SDKError databaseInitializationFailed(Object error) {
    return SDKError(
      'Database initialization failed: $error',
      SDKErrorType.databaseInitializationFailed,
      underlyingError: error,
    );
  }

  static SDKError featureNotAvailable(String feature) {
    return SDKError(
      'Feature \'$feature\' is not available.',
      SDKErrorType.featureNotAvailable,
    );
  }

  static SDKError notImplemented(String feature) {
    return SDKError(
      'Feature \'$feature\' is not yet implemented.',
      SDKErrorType.notImplemented,
    );
  }

  static SDKError rateLimitExceeded([String? message]) {
    return SDKError(
      message ?? 'Rate limit exceeded.',
      SDKErrorType.rateLimitExceeded,
    );
  }

  static SDKError serviceUnavailable([String? message]) {
    return SDKError(
      message ?? 'Service is currently unavailable.',
      SDKErrorType.serviceUnavailable,
    );
  }

  static SDKError invalidInput(String reason) {
    return SDKError(
      'Invalid input: $reason',
      SDKErrorType.invalidInput,
    );
  }

  static SDKError resourceExhausted([String? message]) {
    return SDKError(
      message ?? 'Resource exhausted.',
      SDKErrorType.resourceExhausted,
    );
  }

  static SDKError internalError([String? message]) {
    return SDKError(
      message ?? 'An internal error occurred.',
      SDKErrorType.internalError,
    );
  }

  /// Helper to format bytes
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
  modelNotDownloaded,
  modelLoadFailed,
  loadingFailed,
  modelValidationFailed,
  modelIncompatible,
  frameworkNotAvailable,
  sttNotAvailable,
  ttsNotAvailable,

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
  timeout,
  serverError,
  rateLimitExceeded,
  serviceUnavailable,

  // Storage errors
  storageError,
  insufficientStorage,
  storageFull,
  resourceExhausted,

  // Hardware errors
  hardwareUnsupported,
  memoryPressure,
  thermalStateExceeded,

  // Component errors
  componentNotReady,
  componentNotInitialized,
  invalidState,

  // Validation errors
  validationFailed,
  unsupportedModality,
  invalidInput,

  // Authentication errors
  authenticationFailed,

  // Database errors
  databaseInitializationFailed,

  // Feature errors
  featureNotAvailable,
  notImplemented,

  // General errors
  internalError,
}

/// Type alias for iOS parity
/// iOS uses RunAnywhereError; this alias provides compatibility
typedef RunAnywhereError = SDKError;
