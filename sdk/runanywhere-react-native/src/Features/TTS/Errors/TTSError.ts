/**
 * TTSError.ts
 *
 * Typed errors for Text-to-Speech operations.
 * Matches iOS SDK: Features/TTS/Protocol/TTSError.swift
 */

import { SDKError } from '../../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Errors that can occur during Text-to-Speech operations
 */
export class TTSError extends SDKError {
  // MARK: - Initialization Errors

  /**
   * Service not initialized before use
   */
  static notInitialized(): TTSError {
    return new TTSError(ErrorCode.NotInitialized, 'TTS service not initialized. Call initialize() first.');
  }

  /**
   * Service failed to initialize
   */
  static initializationFailed(underlying: Error): TTSError {
    return new TTSError(
      ErrorCode.NotInitialized,
      `TTS initialization failed: ${underlying.message}`,
      {
        underlyingError: underlying,
      }
    );
  }

  /**
   * No provider found for the requested voice/model
   */
  static noProviderFound(voiceId: string): TTSError {
    return new TTSError(ErrorCode.ModelNotFound, `No TTS provider found for voice: ${voiceId}`, {
      details: { voiceId },
    });
  }

  /**
   * Model/voice file not found at path
   */
  static modelNotFound(path: string): TTSError {
    return new TTSError(ErrorCode.ModelNotFound, `TTS model not found at: ${path}`, {
      details: { path },
    });
  }

  // MARK: - Configuration Errors

  /**
   * Invalid configuration provided
   */
  static invalidConfiguration(reason: string): TTSError {
    return new TTSError(ErrorCode.InvalidInput, `Invalid TTS configuration: ${reason}`, {
      details: { reason },
    });
  }

  /**
   * Invalid speaking rate (must be 0.5-2.0)
   */
  static invalidSpeakingRate(value: number): TTSError {
    return new TTSError(
      ErrorCode.InvalidInput,
      `Invalid speaking rate: ${value}. Must be between 0.5 and 2.0.`,
      {
        details: { value, validRange: '0.5-2.0' },
      }
    );
  }

  /**
   * Invalid pitch (must be 0.5-2.0)
   */
  static invalidPitch(value: number): TTSError {
    return new TTSError(
      ErrorCode.InvalidInput,
      `Invalid pitch: ${value}. Must be between 0.5 and 2.0.`,
      {
        details: { value, validRange: '0.5-2.0' },
      }
    );
  }

  /**
   * Invalid volume (must be 0.0-1.0)
   */
  static invalidVolume(value: number): TTSError {
    return new TTSError(
      ErrorCode.InvalidInput,
      `Invalid volume: ${value}. Must be between 0.0 and 1.0.`,
      {
        details: { value, validRange: '0.0-1.0' },
      }
    );
  }

  // MARK: - Input Errors

  /**
   * Empty text provided for synthesis
   */
  static emptyText(): TTSError {
    return new TTSError(ErrorCode.InvalidInput, 'Cannot synthesize empty text.');
  }

  /**
   * Text too long for synthesis
   */
  static textTooLong(maxCharacters: number, received: number): TTSError {
    return new TTSError(
      ErrorCode.InvalidInput,
      `Text too long. Maximum ${maxCharacters} characters allowed, received ${received}.`,
      {
        details: { maxCharacters, received },
      }
    );
  }

  /**
   * Invalid SSML markup
   */
  static invalidSSML(reason: string): TTSError {
    return new TTSError(ErrorCode.InvalidInput, `Invalid SSML markup: ${reason}`, {
      details: { reason },
    });
  }

  // MARK: - Runtime Errors

  /**
   * Synthesis failed
   */
  static synthesisFailed(reason: string): TTSError {
    return new TTSError(ErrorCode.GenerationFailed, `TTS synthesis failed: ${reason}`, {
      details: { reason },
    });
  }

  /**
   * Voice not available
   */
  static voiceNotAvailable(voiceId: string): TTSError {
    return new TTSError(ErrorCode.ModelNotFound, `Voice not available: ${voiceId}`, {
      details: { voiceId },
    });
  }

  /**
   * Language not supported
   */
  static languageNotSupported(language: string): TTSError {
    return new TTSError(ErrorCode.InvalidInput, `Language not supported: ${language}`, {
      details: { language },
    });
  }

  /**
   * Audio format not supported
   */
  static audioFormatNotSupported(format: string): TTSError {
    return new TTSError(ErrorCode.InvalidInput, `Audio format not supported: ${format}`, {
      details: { format },
    });
  }

  // MARK: - Resource Errors

  /**
   * Insufficient memory for synthesis
   */
  static insufficientMemory(required: number, available: number): TTSError {
    return new TTSError(
      ErrorCode.HardwareUnavailable,
      `Insufficient memory. Required: ${required} bytes, Available: ${available} bytes`,
      {
        details: { required, available },
      }
    );
  }

  /**
   * Operation cancelled
   */
  static cancelled(): TTSError {
    return new TTSError(ErrorCode.OperationCancelled, 'TTS operation was cancelled');
  }

  /**
   * Service is busy with another operation
   */
  static busy(): TTSError {
    return new TTSError(ErrorCode.GenerationFailed, 'TTS service is busy with another operation');
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
    this.name = 'TTSError';
    Object.setPrototypeOf(this, TTSError.prototype);
  }
}
