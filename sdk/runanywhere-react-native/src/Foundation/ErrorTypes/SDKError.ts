/**
 * SDKError.ts
 *
 * Base SDK error class matching iOS SDKErrorProtocol.
 * Matches iOS SDK: Foundation/ErrorTypes/SDKErrorProtocol.swift
 */

import { ErrorCode, getErrorCodeMessage } from './ErrorCodes';
import {
  ErrorCategory,
  getCategoryFromCode,
  inferCategoryFromError,
} from './ErrorCategory';
import type { ErrorContext } from './ErrorContext';
import {
  createErrorContext,
  formatContext,
  formatLocation,
} from './ErrorContext';

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
 * Base SDK error class.
 * All SDK errors should extend this class.
 */
export class SDKError extends Error implements SDKErrorProtocol {
  readonly code: ErrorCode;
  readonly category: ErrorCategory;
  readonly underlyingError?: Error;
  readonly context: ErrorContext;

  constructor(
    code: ErrorCode,
    message?: string,
    options?: {
      underlyingError?: Error;
      category?: ErrorCategory;
    }
  ) {
    const errorMessage = message ?? getErrorCodeMessage(code);
    super(errorMessage);

    this.name = 'SDKError';
    this.code = code;
    this.category = options?.category ?? getCategoryFromCode(code);
    this.underlyingError = options?.underlyingError;
    this.context = createErrorContext(options?.underlyingError ?? this);

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
      error_category: this.category,
      error_message: this.message,
      error_location: formatLocation(this.context),
      error_timestamp: this.context.timestamp,
      has_underlying_error: this.underlyingError !== undefined,
      underlying_error_name: this.underlyingError?.name,
      underlying_error_message: this.underlyingError?.message,
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
