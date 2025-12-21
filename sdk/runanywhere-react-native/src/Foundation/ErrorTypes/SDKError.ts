/**
 * SDKError.ts
 *
 * Base SDK error class matching iOS SDKErrorProtocol.
 * Matches iOS SDK: Foundation/ErrorTypes/SDKErrorProtocol.swift
 */

import { ErrorCode, getErrorCodeMessage } from './ErrorCodes';
import { ErrorCategory, getCategoryFromCode, inferCategoryFromError } from './ErrorCategory';
import type { ErrorContext } from './ErrorContext';
import { createErrorContext, formatContext, formatLocation } from './ErrorContext';

/**
 * Legacy SDK error code enum (string-based).
 * @deprecated Prefer using ErrorCode (numeric) for new code.
 */
export enum SDKErrorCode {
  NotInitialized = 'notInitialized',
  NotImplemented = 'notImplemented',
  InvalidAPIKey = 'invalidAPIKey',
  ModelNotFound = 'modelNotFound',
  LoadingFailed = 'loadingFailed',
  ModelLoadFailed = 'modelLoadFailed',
  GenerationFailed = 'generationFailed',
  GenerationTimeout = 'generationTimeout',
  FrameworkNotAvailable = 'frameworkNotAvailable',
  FeatureNotAvailable = 'featureNotAvailable',
  DownloadFailed = 'downloadFailed',
  ValidationFailed = 'validationFailed',
  RoutingFailed = 'routingFailed',
  DatabaseInitializationFailed = 'databaseInitializationFailed',
  UnsupportedModality = 'unsupportedModality',
  InvalidResponse = 'invalidResponse',
  AuthenticationFailed = 'authenticationFailed',
  NetworkError = 'networkError',
  InvalidState = 'invalidState',
  ComponentNotInitialized = 'componentNotInitialized',
  ComponentNotReady = 'componentNotReady',
  CleanupFailed = 'cleanupFailed',
  ProcessingFailed = 'processingFailed',
  Timeout = 'timeout',
  ServerError = 'serverError',
  StorageError = 'storageError',
  InvalidConfiguration = 'invalidConfiguration',
}

/**
 * Map legacy string-based SDKErrorCode to numeric ErrorCode
 */
function mapLegacyCodeToErrorCode(code: SDKErrorCode): ErrorCode {
  switch (code) {
    case SDKErrorCode.NotInitialized:
      return ErrorCode.NotInitialized;
    case SDKErrorCode.NotImplemented:
      return ErrorCode.Unknown;
    case SDKErrorCode.InvalidAPIKey:
      return ErrorCode.ApiKeyInvalid;
    case SDKErrorCode.ModelNotFound:
      return ErrorCode.ModelNotFound;
    case SDKErrorCode.LoadingFailed:
    case SDKErrorCode.ModelLoadFailed:
      return ErrorCode.ModelLoadFailed;
    case SDKErrorCode.GenerationFailed:
      return ErrorCode.GenerationFailed;
    case SDKErrorCode.GenerationTimeout:
      return ErrorCode.GenerationTimeout;
    case SDKErrorCode.FrameworkNotAvailable:
    case SDKErrorCode.FeatureNotAvailable:
      return ErrorCode.HardwareUnavailable;
    case SDKErrorCode.DownloadFailed:
      return ErrorCode.DownloadFailed;
    case SDKErrorCode.ValidationFailed:
    case SDKErrorCode.InvalidConfiguration:
      return ErrorCode.InvalidInput;
    case SDKErrorCode.RoutingFailed:
      return ErrorCode.Unknown;
    case SDKErrorCode.DatabaseInitializationFailed:
      return ErrorCode.Unknown;
    case SDKErrorCode.UnsupportedModality:
      return ErrorCode.InvalidInput;
    case SDKErrorCode.InvalidResponse:
      return ErrorCode.ApiError;
    case SDKErrorCode.AuthenticationFailed:
      return ErrorCode.AuthenticationFailed;
    case SDKErrorCode.NetworkError:
      return ErrorCode.NetworkUnavailable;
    case SDKErrorCode.InvalidState:
    case SDKErrorCode.ComponentNotInitialized:
    case SDKErrorCode.ComponentNotReady:
      return ErrorCode.NotInitialized;
    case SDKErrorCode.CleanupFailed:
      return ErrorCode.Unknown;
    case SDKErrorCode.ProcessingFailed:
      return ErrorCode.GenerationFailed;
    case SDKErrorCode.Timeout:
      return ErrorCode.NetworkTimeout;
    case SDKErrorCode.ServerError:
      return ErrorCode.ApiError;
    case SDKErrorCode.StorageError:
      return ErrorCode.FileAccessDenied;
    default:
      return ErrorCode.Unknown;
  }
}

/**
 * Base SDK error interface matching iOS SDKErrorProtocol.
 */
export interface SDKErrorProtocol {
  /** Machine-readable error code */
  readonly code: ErrorCode;
  /** Error category for filtering/analytics */
  readonly category: ErrorCategory;
  /** Original error that caused this error */
  readonly underlyingError?: Error;
  /** Error context with stack trace and location */
  readonly context: ErrorContext;
}

/**
 * Unified SDK error class.
 *
 * Supports both legacy string-based codes (SDKErrorCode) and
 * new numeric codes (ErrorCode) for backwards compatibility.
 *
 * @example
 * // Legacy usage (still works):
 * throw new SDKError(SDKErrorCode.NotInitialized, 'SDK not ready');
 *
 * // New recommended usage:
 * throw new SDKError(ErrorCode.NotInitialized, 'SDK not ready');
 */
export class SDKError extends Error implements SDKErrorProtocol {
  readonly code: ErrorCode;
  readonly legacyCode?: SDKErrorCode;
  readonly category: ErrorCategory;
  readonly underlyingError?: Error;
  readonly context: ErrorContext;
  readonly details?: Record<string, unknown>;

  constructor(
    code: ErrorCode | SDKErrorCode,
    message?: string,
    options?: {
      underlyingError?: Error;
      category?: ErrorCategory;
      details?: Record<string, unknown>;
    }
  ) {
    // Determine if we're using legacy string code or new numeric code
    const isLegacyCode = typeof code === 'string';
    const numericCode = isLegacyCode
      ? mapLegacyCodeToErrorCode(code as SDKErrorCode)
      : (code as ErrorCode);
    const errorMessage = message ?? getErrorCodeMessage(numericCode);

    super(errorMessage);

    this.name = 'SDKError';
    this.code = numericCode;
    this.legacyCode = isLegacyCode ? (code as SDKErrorCode) : undefined;
    this.category = options?.category ?? getCategoryFromCode(numericCode);
    this.underlyingError = options?.underlyingError;
    this.context = createErrorContext(options?.underlyingError ?? this);
    this.details = options?.details;

    // Maintain proper prototype chain
    Object.setPrototypeOf(this, SDKError.prototype);
  }

  /**
   * Convert error to analytics data for event tracking.
   */
  toAnalyticsData(): Record<string, unknown> {
    return {
      error_code: this.code,
      error_code_name: ErrorCode[this.code],
      legacy_code: this.legacyCode,
      error_category: this.category,
      error_message: this.message,
      error_location: formatLocation(this.context),
      error_timestamp: this.context.timestamp,
      has_underlying_error: this.underlyingError !== undefined,
      underlying_error_name: this.underlyingError?.name,
      underlying_error_message: this.underlyingError?.message,
      ...this.details,
    };
  }

  /**
   * Log error with full context.
   */
  logError(): void {
    console.error(`[SDKError] ${ErrorCode[this.code]}: ${this.message}`);
    console.error(formatContext(this.context));
    if (this.underlyingError) {
      console.error('Underlying error:', this.underlyingError);
    }
  }
}

/**
 * Convert any error to an SDKError.
 * If already an SDKError, returns as-is.
 * Otherwise, wraps with appropriate categorization.
 */
export function asSDKError(error: Error): SDKError {
  if (error instanceof SDKError) {
    return error;
  }

  const category = inferCategoryFromError(error);
  const code = mapCategoryToCode(category);

  return new SDKError(code, error.message, {
    underlyingError: error,
    category,
  });
}

/**
 * Map an error category to a default error code.
 */
function mapCategoryToCode(category: ErrorCategory): ErrorCode {
  switch (category) {
    case ErrorCategory.Initialization:
      return ErrorCode.NotInitialized;
    case ErrorCategory.Model:
      return ErrorCode.ModelLoadFailed;
    case ErrorCategory.Generation:
      return ErrorCode.GenerationFailed;
    case ErrorCategory.Network:
      return ErrorCode.NetworkUnavailable;
    case ErrorCategory.Storage:
      return ErrorCode.FileNotFound;
    case ErrorCategory.Memory:
      return ErrorCode.HardwareUnavailable;
    case ErrorCategory.Hardware:
      return ErrorCode.HardwareUnsupported;
    case ErrorCategory.Validation:
      return ErrorCode.InvalidInput;
    case ErrorCategory.Authentication:
      return ErrorCode.AuthenticationFailed;
    case ErrorCategory.Component:
      return ErrorCode.Unknown;
    case ErrorCategory.Framework:
      return ErrorCode.Unknown;
    case ErrorCategory.Unknown:
    default:
      return ErrorCode.Unknown;
  }
}

/**
 * Type guard to check if an error is an SDKError.
 */
export function isSDKError(error: unknown): error is SDKError {
  return error instanceof SDKError;
}

/**
 * Create and throw an SDKError, capturing context at the call site.
 * Useful for wrapping errors with automatic context capture.
 */
export function captureAndThrow(
  code: ErrorCode,
  message?: string,
  underlyingError?: Error
): never {
  throw new SDKError(code, message, { underlyingError });
}

// Convenience factory functions for common error types

export function notInitializedError(component?: string): SDKError {
  const message = component
    ? `${component} not initialized`
    : 'SDK not initialized';
  return new SDKError(ErrorCode.NotInitialized, message);
}

export function alreadyInitializedError(component?: string): SDKError {
  const message = component
    ? `${component} already initialized`
    : 'SDK already initialized';
  return new SDKError(ErrorCode.AlreadyInitialized, message);
}

export function invalidInputError(details?: string): SDKError {
  const message = details ? `Invalid input: ${details}` : 'Invalid input';
  return new SDKError(ErrorCode.InvalidInput, message);
}

export function modelNotFoundError(modelId?: string): SDKError {
  const message = modelId ? `Model not found: ${modelId}` : 'Model not found';
  return new SDKError(ErrorCode.ModelNotFound, message);
}

export function modelLoadError(modelId?: string, cause?: Error): SDKError {
  const message = modelId
    ? `Failed to load model: ${modelId}`
    : 'Failed to load model';
  return new SDKError(ErrorCode.ModelLoadFailed, message, {
    underlyingError: cause,
  });
}

export function networkError(details?: string, cause?: Error): SDKError {
  const message = details ?? 'Network error';
  return new SDKError(ErrorCode.NetworkUnavailable, message, {
    underlyingError: cause,
  });
}

export function authenticationError(details?: string): SDKError {
  const message = details ?? 'Authentication failed';
  return new SDKError(ErrorCode.AuthenticationFailed, message);
}

export function generationError(details?: string, cause?: Error): SDKError {
  const message = details ?? 'Generation failed';
  return new SDKError(ErrorCode.GenerationFailed, message, {
    underlyingError: cause,
  });
}

export function storageError(details?: string, cause?: Error): SDKError {
  const message = details ?? 'Storage error';
  return new SDKError(ErrorCode.FileNotFound, message, {
    underlyingError: cause,
  });
}

// ============================================================================
// Native Error Wrapping
// ============================================================================

/**
 * Native error structure from Nitro/React Native bridge.
 * Native modules typically return errors as JSON with these fields.
 */
export interface NativeErrorData {
  /** Error code (may be string or number) */
  code?: string | number;
  /** Error message */
  message?: string;
  /** Domain (iOS) or exception type (Android) */
  domain?: string;
  /** User info dictionary (iOS) */
  userInfo?: Record<string, unknown>;
  /** Native stack trace */
  nativeStackTrace?: string;
  /** Additional details */
  details?: Record<string, unknown>;
}

/**
 * Parse and wrap a native error from JSON-based error data.
 *
 * Native modules (via Nitro) often return errors as JSON strings or objects.
 * This function converts them to proper SDKError instances with full context.
 *
 * Matches iOS pattern where native errors are wrapped with proper categorization.
 *
 * @param nativeError - Native error data (string, object, or Error)
 * @returns SDKError with proper wrapping
 *
 * @example
 * ```typescript
 * try {
 *   const result = await nativeModule.someMethod();
 * } catch (error) {
 *   throw fromNativeError(error);
 * }
 * ```
 */
export function fromNativeError(nativeError: unknown): SDKError {
  // Already an SDKError - return as-is
  if (nativeError instanceof SDKError) {
    return nativeError;
  }

  // Standard Error - wrap it
  if (nativeError instanceof Error) {
    return asSDKError(nativeError);
  }

  // Try to parse as JSON string
  if (typeof nativeError === 'string') {
    try {
      const parsed = JSON.parse(nativeError);
      return parseNativeErrorData(parsed);
    } catch {
      // Not JSON, treat as error message
      return new SDKError(ErrorCode.Unknown, nativeError);
    }
  }

  // Object with error data
  if (typeof nativeError === 'object' && nativeError !== null) {
    return parseNativeErrorData(nativeError as NativeErrorData);
  }

  // Unknown type - create generic error
  return new SDKError(ErrorCode.Unknown, String(nativeError));
}

/**
 * Parse native error data object into SDKError.
 */
function parseNativeErrorData(data: NativeErrorData): SDKError {
  // Extract error code
  let code = ErrorCode.Unknown;
  if (typeof data.code === 'number') {
    code = data.code in ErrorCode ? data.code : ErrorCode.Unknown;
  } else if (typeof data.code === 'string') {
    // Try to map string code to ErrorCode
    code = mapNativeCodeString(data.code);
  }

  // Build message
  const message = data.message ?? 'Native error';

  // Create underlying error with native stack trace
  let underlyingError: Error | undefined;
  if (data.nativeStackTrace) {
    const nativeErr = new Error(message);
    nativeErr.stack = data.nativeStackTrace;
    nativeErr.name = data.domain ?? 'NativeError';
    underlyingError = nativeErr;
  }

  return new SDKError(code, message, {
    underlyingError,
    details: {
      nativeDomain: data.domain,
      nativeUserInfo: data.userInfo,
      ...data.details,
    },
  });
}

/**
 * Map native code strings to ErrorCode.
 * Native modules may use various string identifiers.
 */
function mapNativeCodeString(codeString: string): ErrorCode {
  const normalized = codeString.toLowerCase().replace(/[_-]/g, '');

  // Common native error patterns
  if (normalized.includes('notinitialized') || normalized.includes('notinit')) {
    return ErrorCode.NotInitialized;
  }
  if (normalized.includes('modelload') || normalized.includes('loadfail')) {
    return ErrorCode.ModelLoadFailed;
  }
  if (normalized.includes('modelnotfound')) {
    return ErrorCode.ModelNotFound;
  }
  if (normalized.includes('generation') || normalized.includes('inference')) {
    return ErrorCode.GenerationFailed;
  }
  if (normalized.includes('network') || normalized.includes('connection')) {
    return ErrorCode.NetworkUnavailable;
  }
  if (normalized.includes('auth') || normalized.includes('unauthorized')) {
    return ErrorCode.AuthenticationFailed;
  }
  if (normalized.includes('timeout')) {
    return ErrorCode.NetworkTimeout;
  }
  if (normalized.includes('memory') || normalized.includes('oom')) {
    return ErrorCode.HardwareUnavailable;
  }
  if (normalized.includes('file') || normalized.includes('storage')) {
    return ErrorCode.FileNotFound;
  }
  if (normalized.includes('invalid') || normalized.includes('validation')) {
    return ErrorCode.InvalidInput;
  }
  if (normalized.includes('download')) {
    return ErrorCode.DownloadFailed;
  }
  if (normalized.includes('cancelled') || normalized.includes('canceled')) {
    return ErrorCode.GenerationCancelled;
  }

  return ErrorCode.Unknown;
}
