/**
 * VADError.ts
 *
 * Errors that can occur during Voice Activity Detection operations.
 * Matches iOS SDK: Features/VAD/Protocol/VADError.swift
 */

import { SDKError } from '../../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Errors that can occur during Voice Activity Detection operations
 */
export class VADError extends SDKError {
  // MARK: - Initialization Errors

  /**
   * Service not initialized before use
   */
  static notInitialized(): VADError {
    return new VADError(ErrorCode.NotInitialized, 'VAD service not initialized. Call initialize() first.');
  }

  /**
   * Service failed to initialize
   */
  static initializationFailed(reason: string): VADError {
    return new VADError(ErrorCode.NotInitialized, `VAD initialization failed: ${reason}`, {
      details: { reason },
    });
  }

  /**
   * Invalid configuration provided
   */
  static invalidConfiguration(reason: string): VADError {
    return new VADError(ErrorCode.InvalidInput, `Invalid VAD configuration: ${reason}`, {
      details: { reason },
    });
  }

  // MARK: - Runtime Errors

  /**
   * VAD service not available
   */
  static serviceNotAvailable(): VADError {
    return new VADError(ErrorCode.HardwareUnavailable, 'VAD service not available');
  }

  /**
   * Processing failed
   */
  static processingFailed(reason: string): VADError {
    return new VADError(ErrorCode.GenerationFailed, `VAD processing failed: ${reason}`, {
      details: { reason },
    });
  }

  /**
   * Invalid audio format
   */
  static invalidAudioFormat(expected: string, received: string): VADError {
    return new VADError(
      ErrorCode.InvalidInput,
      `Invalid audio format. Expected ${expected}, received ${received}`,
      {
        details: { expected, received },
      }
    );
  }

  /**
   * Audio buffer is empty
   */
  static emptyAudioBuffer(): VADError {
    return new VADError(ErrorCode.InvalidInput, 'Cannot process empty audio buffer');
  }

  /**
   * Invalid input provided
   */
  static invalidInput(reason: string): VADError {
    return new VADError(ErrorCode.InvalidInput, `Invalid VAD input: ${reason}`, {
      details: { reason },
    });
  }

  // MARK: - Calibration Errors

  /**
   * Calibration failed
   */
  static calibrationFailed(reason: string): VADError {
    return new VADError(ErrorCode.GenerationFailed, `VAD calibration failed: ${reason}`, {
      details: { reason },
    });
  }

  /**
   * Calibration timeout
   */
  static calibrationTimeout(): VADError {
    return new VADError(ErrorCode.GenerationTimeout, 'VAD calibration timed out');
  }

  // MARK: - Resource Errors

  /**
   * Operation cancelled
   */
  static cancelled(): VADError {
    return new VADError(ErrorCode.OperationCancelled, 'VAD operation was cancelled');
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
    this.name = 'VADError';
    Object.setPrototypeOf(this, VADError.prototype);
  }
}
