// Phase C-prime FLUTTER:
//
// `SDKException` is the Dart-throwable wrapper around the canonical proto
// `SDKError` (`generated/errors.pb.dart`). The proto type carries the
// machine-readable shape (code/category/message/context/cAbiCode); this
// class adds the `implements Exception` marker plus factory constructors
// that mirror the legacy hand-rolled `SDKError` factories so call sites
// can keep their familiar shape while flowing proto messages end-to-end.

import 'package:runanywhere/generated/errors.pb.dart' as pb;
import 'package:runanywhere/generated/errors.pbenum.dart' as pb_enum;

/// Throwable wrapper around the canonical [pb.SDKError] proto.
class SDKException implements Exception {
  /// Underlying proto carrying code, category, message, context, ABI code.
  final pb.SDKError error;

  /// Optional underlying cause (mirrors legacy `underlyingError`).
  final Object? underlyingError;

  SDKException(this.error, {this.underlyingError});

  /// Convenience: human-readable message from the underlying proto.
  String get message => error.message;

  /// Convenience: error code from the underlying proto.
  pb_enum.ErrorCode get code => error.code;

  /// Convenience: error category from the underlying proto.
  pb_enum.ErrorCategory get category => error.category;

  @override
  String toString() => 'SDKException(${error.code.name}): ${error.message}';

  // ---------------------------------------------------------------------------
  // Factory constructors mirroring the legacy hand-rolled `SDKError` API.
  // Call sites stay readable (`throw SDKException.notInitialized()`).
  // ---------------------------------------------------------------------------

  static SDKException _build({
    required pb_enum.ErrorCode code,
    required pb_enum.ErrorCategory category,
    required String message,
    Object? underlyingError,
  }) {
    return SDKException(
      pb.SDKError(
        code: code,
        category: category,
        message: message,
      ),
      underlyingError: underlyingError,
    );
  }

  static SDKException notInitialized([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_NOT_INITIALIZED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message ??
            'RunAnywhere SDK is not initialized. Call initialize() first.',
      );

  static SDKException alreadyInitialized([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_ALREADY_INITIALIZED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message ?? 'RunAnywhere SDK is already initialized.',
      );

  static SDKException invalidAPIKey([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INVALID_API_KEY,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_AUTH,
        message: message ?? 'Invalid or missing API key.',
      );

  static SDKException invalidConfiguration(String detail) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INVALID_CONFIGURATION,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_CONFIGURATION,
        message: 'Invalid configuration: $detail',
      );

  static SDKException environmentMismatch(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_ENVIRONMENT_MISMATCH,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_CONFIGURATION,
        message: 'Environment configuration mismatch: $reason',
      );

  static SDKException modelNotFound(String modelId) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: "Model '$modelId' not found.",
      );

  static SDKException modelLoadFailed(String modelId, [Object? error]) =>
      _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: error != null
            ? "Failed to load model '$modelId': $error"
            : "Failed to load model '$modelId'",
        underlyingError: error,
      );

  static SDKException loadingFailed(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: 'Failed to load: $reason',
      );

  static SDKException modelValidationFailed(
          String modelId, List<String> errors) =>
      _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_VALIDATION_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: "Model '$modelId' validation failed: ${errors.join(', ')}",
      );

  static SDKException modelIncompatible(String modelId, String reason) =>
      _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_INCOMPATIBLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: "Model '$modelId' is incompatible: $reason",
      );

  static SDKException modelNotDownloaded(String message) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: message,
      );

  static SDKException sttNotAvailable(String message) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message,
      );

  static SDKException ttsNotAvailable(String message) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message,
      );

  static SDKException generationFailed(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_GENERATION_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: 'Text generation failed: $reason',
      );

  static SDKException generationTimeout([String? reason]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_GENERATION_TIMEOUT,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: reason != null
            ? 'Generation timed out: $reason'
            : 'Text generation timed out.',
      );

  static SDKException contextTooLong(int provided, int maximum) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_CONTEXT_TOO_LONG,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: 'Context too long: $provided tokens (maximum: $maximum)',
      );

  static SDKException tokenLimitExceeded(int requested, int maximum) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_TOKEN_LIMIT_EXCEEDED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: 'Token limit exceeded: requested $requested, maximum $maximum',
      );

  static SDKException costLimitExceeded(double estimated, double limit) =>
      _build(
        code: pb_enum.ErrorCode.ERROR_CODE_COST_LIMIT_EXCEEDED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message:
            'Cost limit exceeded: estimated \$${estimated.toStringAsFixed(2)}, limit \$${limit.toStringAsFixed(2)}',
      );

  static SDKException networkUnavailable([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_NETWORK_UNAVAILABLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: message ?? 'Network connection unavailable.',
      );

  static SDKException networkError(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_NETWORK_ERROR,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: 'Network error: $reason',
      );

  static SDKException requestFailed(Object error) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_REQUEST_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: 'Request failed: $error',
        underlyingError: error,
      );

  static SDKException downloadFailed(String url, [Object? error]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: error != null
            ? "Failed to download from '$url': $error"
            : "Failed to download from '$url'",
        underlyingError: error,
      );

  static SDKException serverError(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_SERVER_ERROR,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: 'Server error: $reason',
      );

  static SDKException timeout(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_TIMEOUT,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: 'Operation timed out: $reason',
      );

  static SDKException insufficientStorage(int required, int available) =>
      _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INSUFFICIENT_STORAGE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_IO,
        message:
            'Insufficient storage: ${_formatBytes(required)} required, ${_formatBytes(available)} available',
      );

  static SDKException storageFull([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_STORAGE_FULL,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_IO,
        message: message ?? 'Device storage is full.',
      );

  static SDKException storageError(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_STORAGE_ERROR,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_IO,
        message: 'Storage error: $reason',
      );

  static SDKException hardwareUnsupported(String feature) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_HARDWARE_UNSUPPORTED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: 'Hardware does not support $feature.',
      );

  static SDKException componentNotInitialized(String component) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: 'Component not initialized: $component',
      );

  static SDKException componentNotReady(String component) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: 'Component not ready: $component',
      );

  static SDKException invalidState(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INVALID_STATE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: 'Invalid state: $reason',
      );

  static SDKException validationFailed(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_VALIDATION_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_VALIDATION,
        message: 'Validation failed: $reason',
      );

  static SDKException unsupportedModality(String modality) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_UNSUPPORTED_MODALITY,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_VALIDATION,
        message: 'Unsupported modality: $modality',
      );

  static SDKException authenticationFailed(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_AUTHENTICATION_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_AUTH,
        message: 'Authentication failed: $reason',
      );

  static SDKException frameworkNotAvailable(String framework) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_FRAMEWORK_NOT_AVAILABLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: 'Framework $framework not available',
      );

  static SDKException databaseInitializationFailed(Object error) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: 'Database initialization failed: $error',
        underlyingError: error,
      );

  static SDKException featureNotAvailable(String feature) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: "Feature '$feature' is not available.",
      );

  static SDKException notImplemented(String feature) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: "Feature '$feature' is not yet implemented.",
      );

  static SDKException rateLimitExceeded([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_REQUEST_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_NETWORK,
        message: message ?? 'Rate limit exceeded.',
      );

  static SDKException serviceUnavailable([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message ?? 'Service is currently unavailable.',
      );

  static SDKException invalidInput(String reason) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INVALID_INPUT,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_VALIDATION,
        message: 'Invalid input: $reason',
      );

  static SDKException resourceExhausted([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_IO,
        message: message ?? 'Resource exhausted.',
      );

  static SDKException internalError([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INTERNAL,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: message ?? 'An internal error occurred.',
      );

  static SDKException voiceAgentNotReady(String message) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message,
      );

  // VLM errors
  static SDKException vlmNotInitialized([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_NOT_INITIALIZED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_COMPONENT,
        message: message ?? 'VLM model not loaded. Call loadVLMModel() first.',
      );

  static SDKException vlmModelLoadFailed(String message) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_MODEL,
        message: 'VLM model load failed: $message',
      );

  static SDKException vlmProcessingFailed(String message) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_PROCESSING_FAILED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: 'VLM processing failed: $message',
      );

  static SDKException vlmInvalidImage([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_INVALID_INPUT,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_VALIDATION,
        message: message ?? 'Invalid image input for VLM processing.',
      );

  static SDKException vlmCancelled([String? message]) => _build(
        code: pb_enum.ErrorCode.ERROR_CODE_CANCELLED,
        category: pb_enum.ErrorCategory.ERROR_CATEGORY_INTERNAL,
        message: message ?? 'VLM generation was cancelled.',
      );

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
