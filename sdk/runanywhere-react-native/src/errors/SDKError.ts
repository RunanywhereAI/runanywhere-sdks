/**
 * RunAnywhere React Native SDK - Error Types
 *
 * These error types match the iOS Swift SDK error definitions.
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Errors/SDKError.swift
 */

import { LLMFramework } from '../types';

/**
 * Error codes matching the iOS SDK error cases
 */
export enum SDKErrorCode {
  NotInitialized = 'NOT_INITIALIZED',
  NotImplemented = 'NOT_IMPLEMENTED',
  InvalidAPIKey = 'INVALID_API_KEY',
  ModelNotFound = 'MODEL_NOT_FOUND',
  ModelNotLoaded = 'MODEL_NOT_LOADED',
  ModelLoadFailed = 'MODEL_LOAD_FAILED',
  LoadingFailed = 'LOADING_FAILED',
  GenerationFailed = 'GENERATION_FAILED',
  GenerationTimeout = 'GENERATION_TIMEOUT',
  FrameworkNotAvailable = 'FRAMEWORK_NOT_AVAILABLE',
  DownloadFailed = 'DOWNLOAD_FAILED',
  ValidationFailed = 'VALIDATION_FAILED',
  RoutingFailed = 'ROUTING_FAILED',
  DatabaseInitializationFailed = 'DATABASE_INITIALIZATION_FAILED',
  UnsupportedModality = 'UNSUPPORTED_MODALITY',
  InvalidResponse = 'INVALID_RESPONSE',
  AuthenticationFailed = 'AUTHENTICATION_FAILED',
  NetworkError = 'NETWORK_ERROR',
  InvalidState = 'INVALID_STATE',
  ComponentNotInitialized = 'COMPONENT_NOT_INITIALIZED',
  ComponentNotReady = 'COMPONENT_NOT_READY',
  Timeout = 'TIMEOUT',
  ServerError = 'SERVER_ERROR',
  StorageError = 'STORAGE_ERROR',
  InvalidConfiguration = 'INVALID_CONFIGURATION',
  // STT specific errors
  TranscriptionFailed = 'TRANSCRIPTION_FAILED',
  StreamCreationFailed = 'STREAM_CREATION_FAILED',
  ServiceNotInitialized = 'SERVICE_NOT_INITIALIZED',
  // TTS specific errors
  SynthesisFailed = 'SYNTHESIS_FAILED',
  VoiceNotFound = 'VOICE_NOT_FOUND',
  // VAD specific errors
  ProcessingFailed = 'PROCESSING_FAILED',
  CleanupFailed = 'CLEANUP_FAILED',
  Unknown = 'UNKNOWN',
}

/**
 * SDK Error class matching the iOS Swift SDK SDKError enum
 */
export class SDKError extends Error {
  /** Error code for programmatic handling */
  public readonly code: SDKErrorCode;

  /** Additional context or reason */
  public readonly reason?: string;

  /** Underlying error if any */
  public readonly underlyingError?: Error;

  /** Framework involved (for framework-specific errors) */
  public readonly framework?: LLMFramework;

  /** Model ID involved (for model-specific errors) */
  public readonly modelId?: string;

  constructor(
    code: SDKErrorCode,
    message: string,
    options?: {
      reason?: string;
      underlyingError?: Error;
      framework?: LLMFramework;
      modelId?: string;
    }
  ) {
    super(message);
    this.name = 'SDKError';
    this.code = code;
    this.reason = options?.reason;
    this.underlyingError = options?.underlyingError;
    this.framework = options?.framework;
    this.modelId = options?.modelId;

    // Maintains proper stack trace for where our error was thrown
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, SDKError);
    }
  }

  /**
   * Create a human-readable error description
   */
  get errorDescription(): string {
    return this.message;
  }

  // ============================================================================
  // Static Factory Methods (matching iOS SDK error cases)
  // ============================================================================

  static notInitialized(): SDKError {
    return new SDKError(
      SDKErrorCode.NotInitialized,
      'SDK not initialized. Call initialize() first.'
    );
  }

  static notImplemented(): SDKError {
    return new SDKError(
      SDKErrorCode.NotImplemented,
      'This feature is not yet implemented.'
    );
  }

  static invalidAPIKey(reason: string): SDKError {
    return new SDKError(SDKErrorCode.InvalidAPIKey, `Invalid API key: ${reason}`, {
      reason,
    });
  }

  static modelNotFound(modelId: string): SDKError {
    return new SDKError(SDKErrorCode.ModelNotFound, `Model '${modelId}' not found.`, {
      modelId,
    });
  }

  static loadingFailed(reason: string, modelId?: string): SDKError {
    return new SDKError(SDKErrorCode.LoadingFailed, `Failed to load model: ${reason}`, {
      reason,
      modelId,
    });
  }

  static generationFailed(reason: string): SDKError {
    return new SDKError(SDKErrorCode.GenerationFailed, `Generation failed: ${reason}`, {
      reason,
    });
  }

  static generationTimeout(reason: string): SDKError {
    return new SDKError(
      SDKErrorCode.GenerationTimeout,
      `Generation timed out: ${reason}`,
      { reason }
    );
  }

  static frameworkNotAvailable(framework: LLMFramework): SDKError {
    return new SDKError(
      SDKErrorCode.FrameworkNotAvailable,
      `Framework ${framework} not available`,
      { framework }
    );
  }

  static downloadFailed(error: Error, modelId?: string): SDKError {
    return new SDKError(
      SDKErrorCode.DownloadFailed,
      `Download failed: ${error.message}`,
      { underlyingError: error, modelId }
    );
  }

  static validationFailed(reason: string): SDKError {
    return new SDKError(SDKErrorCode.ValidationFailed, `Validation failed: ${reason}`, {
      reason,
    });
  }

  static routingFailed(reason: string): SDKError {
    return new SDKError(SDKErrorCode.RoutingFailed, `Routing failed: ${reason}`, {
      reason,
    });
  }

  static databaseInitializationFailed(error: Error): SDKError {
    return new SDKError(
      SDKErrorCode.DatabaseInitializationFailed,
      `Database initialization failed: ${error.message}`,
      { underlyingError: error }
    );
  }

  static unsupportedModality(modality: string): SDKError {
    return new SDKError(
      SDKErrorCode.UnsupportedModality,
      `Unsupported modality: ${modality}`,
      { reason: modality }
    );
  }

  static invalidResponse(reason: string): SDKError {
    return new SDKError(SDKErrorCode.InvalidResponse, `Invalid response: ${reason}`, {
      reason,
    });
  }

  static authenticationFailed(reason: string): SDKError {
    return new SDKError(
      SDKErrorCode.AuthenticationFailed,
      `Authentication failed: ${reason}`,
      { reason }
    );
  }

  static networkError(reason: string): SDKError {
    return new SDKError(SDKErrorCode.NetworkError, `Network error: ${reason}`, {
      reason,
    });
  }

  static invalidState(reason: string): SDKError {
    return new SDKError(SDKErrorCode.InvalidState, `Invalid state: ${reason}`, {
      reason,
    });
  }

  static componentNotInitialized(component: string): SDKError {
    return new SDKError(
      SDKErrorCode.ComponentNotInitialized,
      `Component not initialized: ${component}`,
      { reason: component }
    );
  }

  static timeout(reason: string): SDKError {
    return new SDKError(SDKErrorCode.Timeout, `Operation timed out: ${reason}`, {
      reason,
    });
  }

  static serverError(reason: string): SDKError {
    return new SDKError(SDKErrorCode.ServerError, `Server error: ${reason}`, {
      reason,
    });
  }

  static storageError(reason: string): SDKError {
    return new SDKError(SDKErrorCode.StorageError, `Storage error: ${reason}`, {
      reason,
    });
  }

  static invalidConfiguration(reason: string): SDKError {
    return new SDKError(
      SDKErrorCode.InvalidConfiguration,
      `Invalid configuration: ${reason}`,
      { reason }
    );
  }

  /**
   * Create an SDKError from a native error payload
   */
  static fromNative(nativeError: {
    code?: string;
    message?: string;
    reason?: string;
    framework?: string;
    modelId?: string;
  }): SDKError {
    const code =
      (nativeError.code as SDKErrorCode) || SDKErrorCode.Unknown;
    const message = nativeError.message || 'An unknown error occurred';

    return new SDKError(code, message, {
      reason: nativeError.reason,
      framework: nativeError.framework as LLMFramework | undefined,
      modelId: nativeError.modelId,
    });
  }

  /**
   * Convert to a plain object for serialization
   */
  toJSON(): Record<string, unknown> {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      reason: this.reason,
      framework: this.framework,
      modelId: this.modelId,
    };
  }
}

// Re-export error code for convenience
export { SDKErrorCode as ErrorCode };
