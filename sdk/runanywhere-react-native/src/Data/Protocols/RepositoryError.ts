/**
 * RepositoryError.ts
 *
 * Errors that can occur during repository operations.
 * Matches iOS SDK: Data/Protocols/RepositoryError.swift
 */

import { SDKError } from '../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Errors that can occur during repository operations
 */
export class RepositoryError extends SDKError {
  /**
   * Failed to save data
   */
  static saveFailure(message: string): RepositoryError {
    return new RepositoryError(ErrorCode.Unknown, `Failed to save: ${message}`, {
      details: { operation: 'save', message },
    });
  }

  /**
   * Failed to fetch data
   */
  static fetchFailure(message: string): RepositoryError {
    return new RepositoryError(ErrorCode.Unknown, `Failed to fetch: ${message}`, {
      details: { operation: 'fetch', message },
    });
  }

  /**
   * Failed to delete data
   */
  static deleteFailure(message: string): RepositoryError {
    return new RepositoryError(ErrorCode.Unknown, `Failed to delete: ${message}`, {
      details: { operation: 'delete', message },
    });
  }

  /**
   * Failed to sync data
   */
  static syncFailure(message: string): RepositoryError {
    return new RepositoryError(ErrorCode.Unknown, `Failed to sync: ${message}`, {
      details: { operation: 'sync', message },
    });
  }

  /**
   * Database not initialized
   */
  static databaseNotInitialized(): RepositoryError {
    return new RepositoryError(ErrorCode.NotInitialized, 'Database not initialized');
  }

  /**
   * Entity not found
   */
  static entityNotFound(id: string): RepositoryError {
    return new RepositoryError(ErrorCode.FileNotFound, `Entity not found: ${id}`, {
      details: { entityId: id },
    });
  }

  /**
   * Network unavailable for sync
   */
  static networkUnavailable(): RepositoryError {
    return new RepositoryError(ErrorCode.NetworkUnavailable, 'Network unavailable for sync');
  }

  /**
   * Network not available (alias)
   */
  static networkNotAvailable(): RepositoryError {
    return new RepositoryError(ErrorCode.NetworkUnavailable, 'Network unavailable for sync');
  }

  /**
   * Network error
   */
  static networkError(error: Error): RepositoryError {
    return new RepositoryError(
      ErrorCode.NetworkUnavailable,
      `Network error: ${error.message}`,
      {
        underlyingError: error,
      }
    );
  }

  /**
   * Network request timed out
   */
  static networkTimeout(): RepositoryError {
    return new RepositoryError(ErrorCode.NetworkTimeout, 'Network request timed out');
  }

  private constructor(
    code: ErrorCode,
    message: string,
    options?: {
      underlyingError?: Error;
      details?: Record<string, unknown>;
    }
  ) {
    super(code, message, options);
    this.name = 'RepositoryError';
    Object.setPrototypeOf(this, RepositoryError.prototype);
  }
}
