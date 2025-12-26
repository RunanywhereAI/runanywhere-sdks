/**
 * VoiceSessionError.ts
 * RunAnywhere SDK
 *
 * Errors that can occur during voice session operations.
 * Matches iOS: Public/Extensions/RunAnywhere+VoiceSession.swift
 */

/**
 * Voice session error codes
 */
export enum VoiceSessionErrorCode {
  /** Microphone permission was denied */
  MicrophonePermissionDenied = 'VOICE_SESSION_MIC_PERMISSION_DENIED',
  /** Voice agent not ready (models not loaded) */
  NotReady = 'VOICE_SESSION_NOT_READY',
  /** Session already running */
  AlreadyRunning = 'VOICE_SESSION_ALREADY_RUNNING',
  /** Session not started */
  NotStarted = 'VOICE_SESSION_NOT_STARTED',
  /** Audio capture failed */
  AudioCaptureFailed = 'VOICE_SESSION_AUDIO_CAPTURE_FAILED',
  /** Processing failed */
  ProcessingFailed = 'VOICE_SESSION_PROCESSING_FAILED',
}

/**
 * Voice session error class
 */
export class VoiceSessionError extends Error {
  readonly code: VoiceSessionErrorCode;
  readonly cause?: Error;
  readonly metadata?: Record<string, unknown>;

  constructor(
    code: VoiceSessionErrorCode,
    message: string,
    cause?: Error,
    metadata?: Record<string, unknown>
  ) {
    super(message);
    this.name = 'VoiceSessionError';
    this.code = code;
    this.cause = cause;
    this.metadata = metadata;

    // Maintain proper prototype chain
    Object.setPrototypeOf(this, VoiceSessionError.prototype);
  }

  /**
   * Create a microphone permission denied error
   */
  static microphonePermissionDenied(): VoiceSessionError {
    return new VoiceSessionError(
      VoiceSessionErrorCode.MicrophonePermissionDenied,
      'Microphone permission denied'
    );
  }

  /**
   * Create a not ready error
   */
  static notReady(reason?: string): VoiceSessionError {
    return new VoiceSessionError(
      VoiceSessionErrorCode.NotReady,
      reason || 'Voice agent not ready. Load STT, LLM, and TTS models first.',
      undefined,
      { reason }
    );
  }

  /**
   * Create an already running error
   */
  static alreadyRunning(): VoiceSessionError {
    return new VoiceSessionError(
      VoiceSessionErrorCode.AlreadyRunning,
      'Voice session already running'
    );
  }

  /**
   * Create a not started error
   */
  static notStarted(): VoiceSessionError {
    return new VoiceSessionError(
      VoiceSessionErrorCode.NotStarted,
      'Voice session not started'
    );
  }

  /**
   * Create an audio capture failed error
   */
  static audioCaptureFailed(cause?: Error): VoiceSessionError {
    return new VoiceSessionError(
      VoiceSessionErrorCode.AudioCaptureFailed,
      `Audio capture failed: ${cause?.message || 'Unknown error'}`,
      cause
    );
  }

  /**
   * Create a processing failed error
   */
  static processingFailed(reason: string, cause?: Error): VoiceSessionError {
    return new VoiceSessionError(
      VoiceSessionErrorCode.ProcessingFailed,
      `Processing failed: ${reason}`,
      cause,
      { reason }
    );
  }
}

/**
 * Type guard to check if an error is a VoiceSessionError
 */
export function isVoiceSessionError(
  error: unknown
): error is VoiceSessionError {
  return error instanceof VoiceSessionError;
}
