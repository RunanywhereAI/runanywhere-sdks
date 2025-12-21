/**
 * LoggingError.ts
 * RunAnywhere SDK
 *
 * Typed error enum for logging operations.
 * Matches iOS: Infrastructure/Logging/Protocol/LoggingError.swift
 */

/**
 * Logging error codes
 */
export enum LoggingErrorCode {
  // Configuration Errors
  /** Invalid logging configuration provided */
  InvalidConfiguration = 'LOGGING_INVALID_CONFIGURATION',

  // Destination Errors
  /** Log destination is not available */
  DestinationUnavailable = 'LOGGING_DESTINATION_UNAVAILABLE',
  /** Failed to write to log destination */
  DestinationWriteFailed = 'LOGGING_DESTINATION_WRITE_FAILED',
  /** No destinations configured */
  NoDestinationsConfigured = 'LOGGING_NO_DESTINATIONS_CONFIGURED',

  // Runtime Errors
  /** Logging service not initialized */
  NotInitialized = 'LOGGING_NOT_INITIALIZED',
  /** Flush operation failed */
  FlushFailed = 'LOGGING_FLUSH_FAILED',
}

/**
 * Logging error class
 */
export class LoggingError extends Error {
  readonly code: LoggingErrorCode;
  readonly cause?: Error;
  readonly metadata?: Record<string, unknown>;

  constructor(
    code: LoggingErrorCode,
    message: string,
    cause?: Error,
    metadata?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'LoggingError';
    this.code = code;
    this.cause = cause;
    this.metadata = metadata;

    // Maintain proper prototype chain
    Object.setPrototypeOf(this, LoggingError.prototype);
  }

  // MARK: - Configuration Errors

  static invalidConfiguration(reason: string): LoggingError {
    return new LoggingError(
      LoggingErrorCode.InvalidConfiguration,
      `Invalid logging configuration: ${reason}`,
      undefined,
      { reason }
    );
  }

  // MARK: - Destination Errors

  static destinationUnavailable(name: string): LoggingError {
    return new LoggingError(
      LoggingErrorCode.DestinationUnavailable,
      `Log destination '${name}' is not available`,
      undefined,
      { name }
    );
  }

  static destinationWriteFailed(name: string, cause: Error): LoggingError {
    return new LoggingError(
      LoggingErrorCode.DestinationWriteFailed,
      `Failed to write to log destination '${name}': ${cause.message}`,
      cause,
      { name }
    );
  }

  static noDestinationsConfigured(): LoggingError {
    return new LoggingError(
      LoggingErrorCode.NoDestinationsConfigured,
      'No log destinations configured'
    );
  }

  // MARK: - Runtime Errors

  static notInitialized(): LoggingError {
    return new LoggingError(
      LoggingErrorCode.NotInitialized,
      'Logging service not initialized'
    );
  }

  static flushFailed(cause: Error): LoggingError {
    return new LoggingError(
      LoggingErrorCode.FlushFailed,
      `Failed to flush logs: ${cause.message}`,
      cause
    );
  }
}

/**
 * Type guard to check if an error is a LoggingError
 */
export function isLoggingError(error: unknown): error is LoggingError {
  return error instanceof LoggingError;
}
