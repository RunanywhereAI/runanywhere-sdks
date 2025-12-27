/**
 * SpeakerDiarizationError.ts
 * RunAnywhere SDK
 *
 * Errors that can occur during speaker diarization operations.
 * Matches iOS: Features/SpeakerDiarization/Protocol/SpeakerDiarizationError.swift
 */

/**
 * Speaker diarization error codes
 */
export enum SpeakerDiarizationErrorCode {
  // Initialization Errors
  /** No provider found for the requested model */
  NoProviderFound = 'SPEAKER_DIARIZATION_NO_PROVIDER_FOUND',
  /** Service failed to initialize */
  InitializationFailed = 'SPEAKER_DIARIZATION_INITIALIZATION_FAILED',
  /** Model file not found at path */
  ModelNotFound = 'SPEAKER_DIARIZATION_MODEL_NOT_FOUND',

  // Runtime Errors
  /** Service not initialized before use */
  NotInitialized = 'SPEAKER_DIARIZATION_NOT_INITIALIZED',
  /** Diarization processing failed */
  ProcessingFailed = 'SPEAKER_DIARIZATION_PROCESSING_FAILED',
  /** Invalid audio format */
  InvalidAudioFormat = 'SPEAKER_DIARIZATION_INVALID_AUDIO_FORMAT',
  /** Audio too short for diarization */
  AudioTooShort = 'SPEAKER_DIARIZATION_AUDIO_TOO_SHORT',
  /** No speakers detected in audio */
  NoSpeakersDetected = 'SPEAKER_DIARIZATION_NO_SPEAKERS_DETECTED',

  // Configuration Errors
  /** Invalid configuration provided */
  InvalidConfiguration = 'SPEAKER_DIARIZATION_INVALID_CONFIGURATION',
  /** Max speakers must be between 1 and 100 */
  InvalidMaxSpeakers = 'SPEAKER_DIARIZATION_INVALID_MAX_SPEAKERS',
  /** Invalid threshold value */
  InvalidThreshold = 'SPEAKER_DIARIZATION_INVALID_THRESHOLD',

  // Resource Errors
  /** Insufficient memory for model */
  InsufficientMemory = 'SPEAKER_DIARIZATION_INSUFFICIENT_MEMORY',
  /** Operation cancelled */
  Cancelled = 'SPEAKER_DIARIZATION_CANCELLED',
}

/**
 * Speaker diarization error class
 */
export class SpeakerDiarizationError extends Error {
  readonly code: SpeakerDiarizationErrorCode;
  readonly cause?: Error;
  readonly metadata?: Record<string, unknown>;

  constructor(
    code: SpeakerDiarizationErrorCode,
    message: string,
    cause?: Error,
    metadata?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'SpeakerDiarizationError';
    this.code = code;
    this.cause = cause;
    this.metadata = metadata;

    // Maintain proper prototype chain
    Object.setPrototypeOf(this, SpeakerDiarizationError.prototype);
  }

  // MARK: - Initialization Errors

  static noProviderFound(modelId?: string): SpeakerDiarizationError {
    const message = modelId
      ? `No speaker diarization provider found for model: ${modelId}`
      : 'No speaker diarization provider available';
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.NoProviderFound,
      message,
      undefined,
      { modelId }
    );
  }

  static initializationFailed(cause: Error): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.InitializationFailed,
      `Speaker diarization initialization failed: ${cause.message}`,
      cause
    );
  }

  static modelNotFound(path: string): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.ModelNotFound,
      `Speaker diarization model not found at: ${path}`,
      undefined,
      { path }
    );
  }

  // MARK: - Runtime Errors

  static notInitialized(): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.NotInitialized,
      'Speaker diarization service not initialized. Call initialize() first.'
    );
  }

  static processingFailed(reason: string): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.ProcessingFailed,
      `Speaker diarization processing failed: ${reason}`,
      undefined,
      { reason }
    );
  }

  static invalidAudioFormat(
    expected: string,
    received: string
  ): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.InvalidAudioFormat,
      `Invalid audio format. Expected ${expected}, received ${received}`,
      undefined,
      { expected, received }
    );
  }

  static audioTooShort(minimumSeconds: number): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.AudioTooShort,
      `Audio too short. Minimum ${minimumSeconds} seconds required.`,
      undefined,
      { minimumSeconds }
    );
  }

  static noSpeakersDetected(): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.NoSpeakersDetected,
      'No speakers detected in the audio'
    );
  }

  // MARK: - Configuration Errors

  static invalidConfiguration(reason: string): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.InvalidConfiguration,
      `Invalid configuration: ${reason}`,
      undefined,
      { reason }
    );
  }

  static invalidMaxSpeakers(value: number): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.InvalidMaxSpeakers,
      `Invalid max speakers value: ${value}. Must be between 1 and 100.`,
      undefined,
      { value }
    );
  }

  static invalidThreshold(value: number): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.InvalidThreshold,
      `Invalid threshold value: ${value}. Must be between 0 and 1.`,
      undefined,
      { value }
    );
  }

  // MARK: - Resource Errors

  static insufficientMemory(
    required: number,
    available: number
  ): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.InsufficientMemory,
      `Insufficient memory. Required: ${required} bytes, Available: ${available} bytes`,
      undefined,
      { required, available }
    );
  }

  static cancelled(): SpeakerDiarizationError {
    return new SpeakerDiarizationError(
      SpeakerDiarizationErrorCode.Cancelled,
      'Speaker diarization operation was cancelled'
    );
  }
}

/**
 * Type guard to check if an error is a SpeakerDiarizationError
 */
export function isSpeakerDiarizationError(
  error: unknown
): error is SpeakerDiarizationError {
  return error instanceof SpeakerDiarizationError;
}
