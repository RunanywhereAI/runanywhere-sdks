/**
 * STTError.ts
 *
 * Errors for STT services.
 * Matches iOS SDK: Features/STT/Protocol/STTError.swift
 */

import { SDKError } from '../../../Foundation/ErrorTypes/SDKError';
import { ErrorCode } from '../../../Foundation/ErrorTypes/ErrorCodes';

/**
 * Errors for STT services
 */
export class STTError extends SDKError {
  /**
   * Service not initialized
   */
  static serviceNotInitialized(): STTError {
    return new STTError(ErrorCode.NotInitialized, 'STT service is not initialized');
  }

  /**
   * Transcription failed
   */
  static transcriptionFailed(error: Error): STTError {
    return new STTError(
      ErrorCode.GenerationFailed,
      `Transcription failed: ${error.message}`,
      {
        underlyingError: error,
      }
    );
  }

  /**
   * Streaming transcription is not supported
   */
  static streamingNotSupported(): STTError {
    return new STTError(ErrorCode.GenerationFailed, 'Streaming transcription is not supported');
  }

  /**
   * Language not supported
   */
  static languageNotSupported(language: string): STTError {
    return new STTError(ErrorCode.InvalidInput, `Language not supported: ${language}`, {
      details: { language },
    });
  }

  /**
   * Model not found
   */
  static modelNotFound(model: string): STTError {
    return new STTError(ErrorCode.ModelNotFound, `Model not found: ${model}`, {
      details: { model },
    });
  }

  /**
   * Audio format is not supported
   */
  static audioFormatNotSupported(): STTError {
    return new STTError(ErrorCode.InvalidInput, 'Audio format is not supported');
  }

  /**
   * Insufficient audio data for transcription
   */
  static insufficientAudioData(): STTError {
    return new STTError(ErrorCode.InvalidInput, 'Insufficient audio data for transcription');
  }

  /**
   * Insufficient memory for voice processing
   */
  static insufficientMemory(): STTError {
    return new STTError(ErrorCode.HardwareUnavailable, 'Insufficient memory for voice processing');
  }

  /**
   * No STT service available for transcription
   */
  static noVoiceServiceAvailable(): STTError {
    return new STTError(ErrorCode.GenerationFailed, 'No STT service available for transcription');
  }

  /**
   * Audio session is not configured
   */
  static audioSessionNotConfigured(): STTError {
    return new STTError(ErrorCode.NotInitialized, 'Audio session is not configured');
  }

  /**
   * Failed to activate audio session
   */
  static audioSessionActivationFailed(): STTError {
    return new STTError(ErrorCode.HardwareUnavailable, 'Failed to activate audio session');
  }

  /**
   * Microphone permission was denied
   */
  static microphonePermissionDenied(): STTError {
    return new STTError(ErrorCode.AuthorizationDenied, 'Microphone permission was denied');
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
    this.name = 'STTError';
    Object.setPrototypeOf(this, STTError.prototype);
  }
}
