/**
 * DownloadError.ts
 *
 * Download and file operation errors.
 * Matches iOS SDK: Infrastructure/Download/Protocol/DownloadError.swift
 */

import { SDKError } from '../../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Download and file operation errors
 */
export class DownloadError extends SDKError {
  /**
   * Invalid download URL
   */
  static invalidURL(): DownloadError {
    return new DownloadError(ErrorCode.InvalidInput, 'Invalid download URL');
  }

  /**
   * Network error
   */
  static networkError(error: Error): DownloadError {
    return new DownloadError(
      ErrorCode.NetworkUnavailable,
      `Network error: ${error.message}`,
      {
        underlyingError: error,
      }
    );
  }

  /**
   * Download timeout
   */
  static timeout(): DownloadError {
    return new DownloadError(ErrorCode.NetworkTimeout, 'Download timeout');
  }

  /**
   * Partial download - file incomplete
   */
  static partialDownload(): DownloadError {
    return new DownloadError(
      ErrorCode.DownloadFailed,
      'Partial download - file incomplete'
    );
  }

  /**
   * Downloaded file checksum doesn't match expected
   */
  static checksumMismatch(): DownloadError {
    return new DownloadError(
      ErrorCode.FileCorrupted,
      "Downloaded file checksum doesn't match expected"
    );
  }

  /**
   * Archive extraction failed
   */
  static extractionFailed(reason: string): DownloadError {
    return new DownloadError(
      ErrorCode.DownloadFailed,
      `Archive extraction failed: ${reason}`,
      {
        details: { reason },
      }
    );
  }

  /**
   * Unsupported archive format
   */
  static unsupportedArchive(format: string): DownloadError {
    return new DownloadError(
      ErrorCode.DownloadFailed,
      `Unsupported archive format: ${format}`,
      {
        details: { format },
      }
    );
  }

  /**
   * Unknown download error
   */
  static unknown(): DownloadError {
    return new DownloadError(ErrorCode.Unknown, 'Unknown download error');
  }

  /**
   * Invalid server response
   */
  static invalidResponse(): DownloadError {
    return new DownloadError(ErrorCode.ApiError, 'Invalid server response');
  }

  /**
   * HTTP error
   */
  static httpError(code: number): DownloadError {
    return new DownloadError(ErrorCode.ApiError, `HTTP error: ${code}`, {
      details: { httpCode: code },
    });
  }

  /**
   * Download was cancelled
   */
  static cancelled(): DownloadError {
    return new DownloadError(
      ErrorCode.OperationCancelled,
      'Download was cancelled'
    );
  }

  /**
   * Insufficient storage space
   */
  static insufficientSpace(): DownloadError {
    return new DownloadError(
      ErrorCode.InsufficientStorage,
      'Insufficient storage space'
    );
  }

  /**
   * Model not found
   */
  static modelNotFound(): DownloadError {
    return new DownloadError(ErrorCode.ModelNotFound, 'Model not found');
  }

  /**
   * Network connection lost
   */
  static connectionLost(): DownloadError {
    return new DownloadError(
      ErrorCode.NetworkUnavailable,
      'Network connection lost'
    );
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
    this.name = 'DownloadError';
    Object.setPrototypeOf(this, DownloadError.prototype);
  }
}
