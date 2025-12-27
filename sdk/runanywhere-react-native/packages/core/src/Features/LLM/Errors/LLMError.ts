/**
 * LLMError.ts
 *
 * Typed errors for LLM operations.
 * Matches iOS SDK: Features/LLM/Protocol/LLMError.swift
 */

import { SDKError } from '../../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Errors that can occur during LLM operations
 */
export class LLMError extends SDKError {
  // MARK: - Initialization Errors

  /**
   * Service not initialized before use
   */
  static notInitialized(): LLMError {
    return new LLMError(
      ErrorCode.NotInitialized,
      'LLM service is not initialized. Call initialize() first.'
    );
  }

  /**
   * No provider found for the requested model
   */
  static noProviderFound(modelId?: string): LLMError {
    const message = modelId
      ? `No LLM provider found for model: ${modelId}`
      : 'No LLM provider registered. Register one with ModuleRegistry.shared.registerLLM(provider).';
    return new LLMError(ErrorCode.ModelNotFound, message, {
      details: { modelId },
    });
  }

  /**
   * Model file not found at path
   */
  static modelNotFound(path: string): LLMError {
    return new LLMError(
      ErrorCode.ModelNotFound,
      `Model not found at path: ${path}`,
      {
        details: { path },
      }
    );
  }

  /**
   * Service failed to initialize
   */
  static initializationFailed(underlying: Error): LLMError {
    return new LLMError(
      ErrorCode.NotInitialized,
      `LLM initialization failed: ${underlying.message}`,
      {
        underlyingError: underlying,
      }
    );
  }

  // MARK: - Generation Errors

  /**
   * Generation failed with underlying error
   */
  static generationFailed(error: Error): LLMError {
    return new LLMError(
      ErrorCode.GenerationFailed,
      `Generation failed: ${error.message}`,
      {
        underlyingError: error,
      }
    );
  }

  /**
   * Generation timed out
   */
  static generationTimeout(message: string): LLMError {
    return new LLMError(
      ErrorCode.GenerationTimeout,
      `Generation timed out: ${message}`,
      {
        details: { timeoutMessage: message },
      }
    );
  }

  /**
   * Context length exceeded
   */
  static contextLengthExceeded(
    maxLength: number,
    requestedLength: number
  ): LLMError {
    return new LLMError(
      ErrorCode.ContextTooLong,
      `Context length exceeded. Maximum: ${maxLength}, Requested: ${requestedLength}`,
      {
        details: { maxLength, requestedLength },
      }
    );
  }

  /**
   * Invalid generation options
   */
  static invalidOptions(reason: string): LLMError {
    return new LLMError(
      ErrorCode.InvalidInput,
      `Invalid generation options: ${reason}`,
      {
        details: { reason },
      }
    );
  }

  // MARK: - Streaming Errors

  /**
   * Streaming generation is not supported by this service
   */
  static streamingNotSupported(): LLMError {
    return new LLMError(
      ErrorCode.GenerationFailed,
      'Streaming generation is not supported by this service'
    );
  }

  /**
   * Stream was cancelled
   */
  static streamCancelled(): LLMError {
    return new LLMError(
      ErrorCode.OperationCancelled,
      'Stream generation was cancelled'
    );
  }

  // MARK: - Resource Errors

  /**
   * Insufficient memory for model
   */
  static insufficientMemory(required: number, available: number): LLMError {
    return new LLMError(
      ErrorCode.HardwareUnavailable,
      `Insufficient memory. Required: ${required} bytes, Available: ${available} bytes`,
      {
        details: { required, available },
      }
    );
  }

  /**
   * Service is busy processing another request
   */
  static serviceBusy(): LLMError {
    return new LLMError(
      ErrorCode.GenerationFailed,
      'LLM service is busy processing another request'
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
    this.name = 'LLMError';
    Object.setPrototypeOf(this, LLMError.prototype);
  }
}
