/**
 * AnalyticsError.ts
 * RunAnywhere SDK
 *
 * Typed error enum for analytics-related errors.
 * Matches iOS: Infrastructure/Analytics/Protocol/AnalyticsError.swift
 */

/**
 * Analytics error codes
 */
export enum AnalyticsErrorCode {
  // Initialization Errors
  /** Analytics service not initialized */
  NotInitialized = 'ANALYTICS_NOT_INITIALIZED',
  /** Failed to initialize analytics with underlying error */
  InitializationFailed = 'ANALYTICS_INITIALIZATION_FAILED',
  /** Invalid configuration provided */
  InvalidConfiguration = 'ANALYTICS_INVALID_CONFIGURATION',

  // Tracking Errors
  /** Failed to track event */
  TrackingFailed = 'ANALYTICS_TRACKING_FAILED',
  /** Event queue is full */
  QueueFull = 'ANALYTICS_QUEUE_FULL',
  /** Invalid event data */
  InvalidEventData = 'ANALYTICS_INVALID_EVENT_DATA',

  // Storage Errors
  /** Failed to persist analytics data */
  StorageFailed = 'ANALYTICS_STORAGE_FAILED',
  /** Failed to retrieve analytics data */
  RetrievalFailed = 'ANALYTICS_RETRIEVAL_FAILED',
  /** Database error */
  DatabaseError = 'ANALYTICS_DATABASE_ERROR',

  // Sync Errors
  /** Failed to sync analytics to remote */
  SyncFailed = 'ANALYTICS_SYNC_FAILED',
  /** Network unavailable for sync */
  NetworkUnavailable = 'ANALYTICS_NETWORK_UNAVAILABLE',
  /** Remote server error */
  ServerError = 'ANALYTICS_SERVER_ERROR',

  // Session Errors
  /** Invalid session ID */
  InvalidSession = 'ANALYTICS_INVALID_SESSION',
  /** Session already ended */
  SessionAlreadyEnded = 'ANALYTICS_SESSION_ALREADY_ENDED',
}

/**
 * Analytics error class
 */
export class AnalyticsError extends Error {
  readonly code: AnalyticsErrorCode;
  readonly cause?: Error;
  readonly metadata?: Record<string, unknown>;

  constructor(
    code: AnalyticsErrorCode,
    message: string,
    cause?: Error,
    metadata?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'AnalyticsError';
    this.code = code;
    this.cause = cause;
    this.metadata = metadata;

    // Maintain proper prototype chain
    Object.setPrototypeOf(this, AnalyticsError.prototype);
  }

  // MARK: - Initialization Errors

  static notInitialized(): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.NotInitialized,
      'Analytics service not initialized. Call initialize() first.'
    );
  }

  static initializationFailed(cause: Error): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.InitializationFailed,
      `Analytics initialization failed: ${cause.message}`,
      cause
    );
  }

  static invalidConfiguration(reason: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.InvalidConfiguration,
      `Invalid analytics configuration: ${reason}`,
      undefined,
      { reason }
    );
  }

  // MARK: - Tracking Errors

  static trackingFailed(eventType: string, reason: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.TrackingFailed,
      `Failed to track event '${eventType}': ${reason}`,
      undefined,
      { eventType, reason }
    );
  }

  static queueFull(maxSize: number): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.QueueFull,
      `Analytics event queue is full (max: ${maxSize})`,
      undefined,
      { maxSize }
    );
  }

  static invalidEventData(reason: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.InvalidEventData,
      `Invalid event data: ${reason}`,
      undefined,
      { reason }
    );
  }

  // MARK: - Storage Errors

  static storageFailed(cause: Error): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.StorageFailed,
      `Failed to store analytics data: ${cause.message}`,
      cause
    );
  }

  static retrievalFailed(cause: Error): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.RetrievalFailed,
      `Failed to retrieve analytics data: ${cause.message}`,
      cause
    );
  }

  static databaseError(reason: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.DatabaseError,
      `Analytics database error: ${reason}`,
      undefined,
      { reason }
    );
  }

  // MARK: - Sync Errors

  static syncFailed(cause: Error): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.SyncFailed,
      `Failed to sync analytics: ${cause.message}`,
      cause
    );
  }

  static networkUnavailable(): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.NetworkUnavailable,
      'Network unavailable for analytics sync'
    );
  }

  static serverError(statusCode: number, message?: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.ServerError,
      `Analytics server error (${statusCode}): ${message || 'Unknown error'}`,
      undefined,
      { statusCode, message }
    );
  }

  // MARK: - Session Errors

  static invalidSession(sessionId: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.InvalidSession,
      `Invalid analytics session: ${sessionId}`,
      undefined,
      { sessionId }
    );
  }

  static sessionAlreadyEnded(sessionId: string): AnalyticsError {
    return new AnalyticsError(
      AnalyticsErrorCode.SessionAlreadyEnded,
      `Analytics session already ended: ${sessionId}`,
      undefined,
      { sessionId }
    );
  }
}

/**
 * Type guard to check if an error is an AnalyticsError
 */
export function isAnalyticsError(error: unknown): error is AnalyticsError {
  return error instanceof AnalyticsError;
}
