// errors.ts — SDKException, the single throwable type the SDK raises. Mirrors the
// shape used by the Swift / Kotlin / React-Native / Web SDKs so cross-platform
// consumer code can read `e.code` / `e.category` / `e.recoverySuggestion` /
// `e.fieldPath` uniformly.
//
// The numeric ErrorCode / ErrorCategory values are the canonical ones from
// idl/errors.proto. This SDK deliberately does not depend on the generated proto
// (the native addon owns proto on its side), so the constants + the category
// table are replicated here — exactly as the RN and Web SDKs replicate them.
// Keep them in sync with idl/errors.proto if the canonical mapping changes.

export enum ErrorCode {
  UNSPECIFIED = 0,
  NOT_INITIALIZED = 100,
  MODEL_NOT_FOUND = 110,
  MODEL_LOAD_FAILED = 111,
  GENERATION_FAILED = 130,
  STORAGE_ERROR = 182,
  INVALID_STATE = 231,
  SERVICE_NOT_AVAILABLE = 232,
  PROCESSING_FAILED = 234,
  INVALID_INPUT = 251,
  INVALID_ARGUMENT = 259,
  CANCELLED = 380,
  NOT_IMPLEMENTED = 800,
  UNKNOWN = 804,
}

export enum ErrorCategory {
  UNSPECIFIED = 0,
  NETWORK = 1,
  VALIDATION = 2,
  MODEL = 3,
  COMPONENT = 4,
  IO = 5,
  AUTH = 6,
  INTERNAL = 7,
  CONFIGURATION = 8,
}

/**
 * Map an ErrorCode to its ErrorCategory — verbatim port of the canonical range
 * table in commons `rac_error_proto.cpp::category_for_code()` (also replicated
 * in the RN/Web SDKs). Keep in sync.
 */
export function categoryForCode(code: number): ErrorCategory {
  if (code === 0) return ErrorCategory.UNSPECIFIED;
  if (code >= 100 && code <= 109) return ErrorCategory.CONFIGURATION;
  if (code >= 110 && code <= 129) return ErrorCategory.MODEL;
  if (code >= 130 && code <= 149) return ErrorCategory.COMPONENT;
  if (code >= 150 && code <= 179) return ErrorCategory.NETWORK;
  if ((code >= 180 && code <= 219) || (code >= 280 && code <= 299)) return ErrorCategory.IO;
  if (code >= 220 && code <= 229) return ErrorCategory.INTERNAL;
  if (code >= 230 && code <= 249) return ErrorCategory.COMPONENT;
  if (code >= 250 && code <= 279) return ErrorCategory.VALIDATION;
  if (code >= 300 && code <= 319) return ErrorCategory.COMPONENT;
  if (code >= 320 && code <= 349) return ErrorCategory.AUTH;
  if (code >= 350 && code <= 369) return ErrorCategory.IO;
  if (code >= 370 && code <= 379) return ErrorCategory.VALIDATION;
  if (code >= 380 && code <= 389) return ErrorCategory.INTERNAL;
  if (code >= 400 && code <= 499) return ErrorCategory.COMPONENT;
  if (code >= 500 && code <= 599) return ErrorCategory.CONFIGURATION;
  if (code >= 600 && code <= 699) return ErrorCategory.COMPONENT;
  if (code >= 700 && code <= 999) return ErrorCategory.INTERNAL;
  return ErrorCategory.UNSPECIFIED;
}

export interface SDKErrorFields {
  code: ErrorCode;
  message: string;
  category?: ErrorCategory;
  cAbiCode?: number;
  nestedMessage?: string;
  fieldPath?: string;
}

/**
 * Throwable subclass of Error (so `instanceof Error` + stack traces work).
 * Carries the canonical `code` / `category` for cross-SDK-uniform handling.
 */
export class SDKException extends Error {
  readonly code: ErrorCode;
  readonly category: ErrorCategory;
  /** Negative rac_result_t equivalent, when applicable. */
  readonly cAbiCode?: number;
  readonly nestedMessage?: string;
  /** Structured validation field path (e.g. "ToolSpec.name"), when applicable. */
  readonly fieldPath?: string;

  constructor(fields: SDKErrorFields) {
    super(fields.message || 'SDK error');
    this.name = 'SDKException';
    this.code = fields.code;
    this.category = fields.category ?? categoryForCode(fields.code);
    this.cAbiCode =
      fields.cAbiCode ?? (fields.code > 0 && fields.code <= 899 ? -fields.code : undefined);
    this.nestedMessage = fields.nestedMessage;
    this.fieldPath = fields.fieldPath;
    Object.setPrototypeOf(this, SDKException.prototype);
  }

  /** Human-readable recovery hint for common codes, mirroring the other SDKs. */
  get recoverySuggestion(): string | undefined {
    switch (this.code) {
      case ErrorCode.NOT_INITIALIZED:
        return 'Initialize the SDK (RunAnywhere.initialize()) before using it.';
      case ErrorCode.MODEL_NOT_FOUND:
        return 'Ensure the model is downloaded and the path/id is correct.';
      case ErrorCode.MODEL_LOAD_FAILED:
        return 'Check the model file is valid and compatible.';
      case ErrorCode.STORAGE_ERROR:
        return 'Free up storage space and try again.';
      default:
        return undefined;
    }
  }

  /** Expected/routine errors (cancellation) that need not be logged as errors. */
  get isExpected(): boolean {
    return this.code === ErrorCode.CANCELLED;
  }

  static of(code: ErrorCode, message: string, options?: Omit<SDKErrorFields, 'code' | 'message'>): SDKException {
    return new SDKException({ code, message, ...options });
  }

  static notInitialized(component?: string): SDKException {
    return SDKException.of(ErrorCode.NOT_INITIALIZED, component ? `${component} not initialized` : 'SDK not initialized', {
      category: ErrorCategory.COMPONENT,
    });
  }
  static invalidInput(details?: string): SDKException {
    return SDKException.of(ErrorCode.INVALID_INPUT, details ? `Invalid input: ${details}` : 'Invalid input');
  }
  static validationFailed(args: { fieldPath: string; message: string }): SDKException {
    return SDKException.of(ErrorCode.INVALID_ARGUMENT, args.message, {
      category: ErrorCategory.VALIDATION,
      cAbiCode: -259,
      fieldPath: args.fieldPath,
    });
  }
  static modelNotFound(modelId?: string): SDKException {
    return SDKException.of(ErrorCode.MODEL_NOT_FOUND, modelId ? `Model not found: ${modelId}` : 'Model not found');
  }
  static modelLoadFailed(modelId?: string, cause?: Error): SDKException {
    return SDKException.of(ErrorCode.MODEL_LOAD_FAILED, modelId ? `Failed to load model: ${modelId}` : 'Failed to load model', {
      nestedMessage: cause?.message,
    });
  }
  static generationFailed(details?: string, cause?: Error): SDKException {
    return SDKException.of(ErrorCode.GENERATION_FAILED, details ?? 'Generation failed', { nestedMessage: cause?.message });
  }
  static invalidState(details?: string): SDKException {
    return SDKException.of(ErrorCode.INVALID_STATE, details ?? 'Invalid state', { category: ErrorCategory.INTERNAL });
  }
  static notImplemented(feature?: string): SDKException {
    return SDKException.of(ErrorCode.NOT_IMPLEMENTED, feature ? `${feature} not implemented` : 'Not implemented');
  }
  static cancelled(message = 'Operation cancelled'): SDKException {
    return SDKException.of(ErrorCode.CANCELLED, message, { category: ErrorCategory.INTERNAL });
  }
  static unknown(details?: string, cause?: Error): SDKException {
    return SDKException.of(ErrorCode.UNKNOWN, details ?? 'Unknown error', { nestedMessage: cause?.message });
  }
}

/** Type guard. */
export function isSDKException(error: unknown): error is SDKException {
  return error instanceof SDKException;
}

/** Coerce any thrown value into an SDKException (matches RN/Web `asSDKException`). */
export function asSDKException(error: unknown): SDKException {
  if (error instanceof SDKException) return error;
  if (error instanceof Error) return SDKException.unknown(error.message, error);
  if (typeof error === 'string') return SDKException.unknown(error);
  return SDKException.unknown(String(error));
}
