/**
 * RunAnywhere Web SDK - Error Types
 *
 * Structured error handling matching the RACommons error code system.
 * Error codes map to rac_error.h ranges (-100 to -999).
 */

/** RACommons error code ranges */
export enum SDKErrorCode {
  // Success
  Success = 0,

  // Initialization errors (-100 to -109)
  NotInitialized = -100,
  AlreadyInitialized = -101,
  InvalidConfiguration = -102,
  InitializationFailed = -103,

  // Model errors (-110 to -129)
  ModelNotFound = -110,
  ModelLoadFailed = -111,
  ModelInvalidFormat = -112,
  ModelNotLoaded = -113,
  ModelAlreadyLoaded = -114,

  // Generation errors (-130 to -149)
  GenerationFailed = -130,
  GenerationCancelled = -131,
  GenerationTimeout = -132,
  InvalidPrompt = -133,
  ContextLengthExceeded = -134,

  // Network errors (-150 to -179)
  NetworkError = -150,
  NetworkTimeout = -151,
  AuthenticationFailed = -152,
  DownloadFailed = -160,
  DownloadCancelled = -161,

  // Storage errors (-180 to -219)
  StorageError = -180,
  InsufficientStorage = -181,
  FileNotFound = -182,
  FileWriteFailed = -183,

  // Parameter errors (-220 to -229)
  InvalidParameter = -220,

  // Component errors (-230 to -249)
  ComponentNotReady = -230,
  ComponentBusy = -231,
  InvalidState = -232,

  // Backend errors (-600 to -699)
  BackendNotAvailable = -600,
  BackendError = -601,

  // WASM-specific errors (-900 to -999)
  WASMLoadFailed = -900,
  WASMNotLoaded = -901,
  WASMCallbackError = -902,
  WASMMemoryError = -903,
}

/**
 * SDK Error class matching the error handling pattern across all SDKs.
 */
export class SDKError extends Error {
  readonly code: SDKErrorCode;
  readonly details?: string;

  constructor(code: SDKErrorCode, message: string, details?: string) {
    super(message);
    this.name = 'SDKError';
    this.code = code;
    this.details = details;
  }

  /** Create from a RACommons rac_result_t error code */
  static fromRACResult(resultCode: number, details?: string): SDKError {
    const message = `RACommons error: ${resultCode}`;
    return new SDKError(resultCode as SDKErrorCode, message, details);
  }

  /** Check if error code indicates success */
  static isSuccess(resultCode: number): boolean {
    return resultCode === 0;
  }

  /** Convenience constructors */
  static notInitialized(message = 'SDK not initialized'): SDKError {
    return new SDKError(SDKErrorCode.NotInitialized, message);
  }

  static wasmNotLoaded(message = 'WASM module not loaded'): SDKError {
    return new SDKError(SDKErrorCode.WASMNotLoaded, message);
  }

  static modelNotFound(modelId: string): SDKError {
    return new SDKError(
      SDKErrorCode.ModelNotFound,
      `Model not found: ${modelId}`,
    );
  }

  static componentNotReady(component: string, details?: string): SDKError {
    return new SDKError(
      SDKErrorCode.ComponentNotReady,
      `Component not ready: ${component}`,
      details,
    );
  }

  static generationFailed(details?: string): SDKError {
    return new SDKError(
      SDKErrorCode.GenerationFailed,
      'Generation failed',
      details,
    );
  }
}

/** Type guard: returns true if the value is an SDKError instance. */
export function isSDKError(error: unknown): error is SDKError {
  return error instanceof SDKError;
}
