/**
 * RunAnywhere Web SDK - SDKException.
 *
 * Wave 2: SDKException is the SOLE exception class. The legacy `SDKError` has
 * been deleted; all throw sites now use SDKException. SDKException wraps the
 * canonical proto-ts `SDKError` shape from `@runanywhere/proto-ts/errors` so a
 * thrown error can carry the full proto envelope (category, code, message,
 * details, c_abi_code, context) for wire interop while still behaving like a
 * plain `Error` to TS callers.
 *
 * Source of truth (wire shape): idl/errors.proto
 *   - ProtoSDKError = { category, code, c_abi_code, message, details?, ... }
 */
import {
  ErrorCategory as ProtoErrorCategory,
  ErrorCode as ProtoErrorCode,
  type SDKError as ProtoSDKError,
} from '@runanywhere/proto-ts/errors';

/**
 * Signed-negative SDK error codes that mirror the rac_result_t C ABI ranges.
 * Web SDK still throws / catches numeric codes; the proto envelope holds a
 * round-tripped copy in `c_abi_code`. The proto-ts `ErrorCode` enum carries
 * POSITIVE values (proto3 forbids negative literals) — the absolute magnitude
 * matches.
 */
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
 * Map a signed-negative `SDKErrorCode` to the matching proto-ts `ErrorCategory`.
 */
function categoryForCode(code: SDKErrorCode): ProtoErrorCategory {
  if (code === 0) return ProtoErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
  const abs = Math.abs(code);
  if (abs >= 100 && abs <= 109) return ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION;
  if (abs >= 110 && abs <= 129) return ProtoErrorCategory.ERROR_CATEGORY_MODEL;
  if (abs >= 130 && abs <= 149) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 150 && abs <= 179) return ProtoErrorCategory.ERROR_CATEGORY_NETWORK;
  if (abs >= 180 && abs <= 219) return ProtoErrorCategory.ERROR_CATEGORY_IO;
  if (abs >= 220 && abs <= 229) return ProtoErrorCategory.ERROR_CATEGORY_VALIDATION;
  if (abs >= 230 && abs <= 249) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 600 && abs <= 699) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 900 && abs <= 999) return ProtoErrorCategory.ERROR_CATEGORY_INTERNAL;
  return ProtoErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
}

/**
 * Map a signed-negative SDKErrorCode to the matching proto-ts ErrorCode
 * (positive values, since proto3 forbids negative enum literals).
 */
function protoCodeForSDKCode(code: SDKErrorCode): ProtoErrorCode {
  const positive = Math.abs(code);
  if (Object.values(ProtoErrorCode).includes(positive)) {
    return positive as ProtoErrorCode;
  }
  return ProtoErrorCode.ERROR_CODE_UNSPECIFIED;
}

/**
 * SDK exception class — wraps a full proto-ts SDKError envelope. Wire-compatible
 * with the C ABI (same negative numeric code range).
 */
export class SDKException extends Error {
  readonly proto: ProtoSDKError;

  constructor(codeOrProto: SDKErrorCode | ProtoSDKError, message?: string, details?: string) {
    if (typeof codeOrProto === 'number') {
      const code = codeOrProto;
      const msg = message ?? `SDK error: ${code}`;
      super(msg);
      this.name = 'SDKException';
      this.proto = {
        category: categoryForCode(code),
        code: protoCodeForSDKCode(code),
        cAbiCode: code,
        message: msg,
        nestedMessage: details,
        context: undefined,
      };
    } else {
      super(codeOrProto.message);
      this.name = 'SDKException';
      this.proto = codeOrProto;
    }
  }

  /** The signed-negative SDKErrorCode (matches rac_result_t). */
  get code(): SDKErrorCode {
    return (this.proto.cAbiCode as SDKErrorCode) ?? (-this.proto.code as SDKErrorCode);
  }

  /** Optional structured details (proto.nestedMessage). */
  get details(): string | undefined {
    return this.proto.nestedMessage;
  }

  /** Whether the result code indicates success (code === 0). */
  static isSuccess(resultCode: number): boolean {
    return resultCode === 0;
  }

  /** Build an SDKException from a signed numeric SDKErrorCode + message. */
  static fromCode(code: SDKErrorCode, message: string, details?: string): SDKException {
    return new SDKException(code, message, details);
  }

  /** Build an SDKException from a raw `rac_result_t` result code. */
  static fromRACResult(resultCode: number, details?: string): SDKException {
    const message = `RACommons error: ${resultCode}`;
    return SDKException.fromCode(resultCode as SDKErrorCode, message, details);
  }

  // ---------------------------------------------------------------------------
  // Convenience constructors.
  // ---------------------------------------------------------------------------

  static notInitialized(message = 'SDK not initialized'): SDKException {
    return SDKException.fromCode(SDKErrorCode.NotInitialized, message);
  }

  static wasmNotLoaded(message = 'WASM module not loaded'): SDKException {
    return SDKException.fromCode(SDKErrorCode.WASMNotLoaded, message);
  }

  static modelNotFound(modelId: string): SDKException {
    return SDKException.fromCode(
      SDKErrorCode.ModelNotFound,
      `Model not found: ${modelId}`,
    );
  }

  static componentNotReady(component: string, details?: string): SDKException {
    return SDKException.fromCode(
      SDKErrorCode.ComponentNotReady,
      `Component not ready: ${component}`,
      details,
    );
  }

  static generationFailed(details?: string): SDKException {
    return SDKException.fromCode(
      SDKErrorCode.GenerationFailed,
      'Generation failed',
      details,
    );
  }

  static backendNotAvailable(feature: string, details?: string): SDKException {
    return SDKException.fromCode(
      SDKErrorCode.BackendNotAvailable,
      `Backend not available for: ${feature}`,
      details,
    );
  }
}

/** Type guard: returns true if the value is an SDKException instance. */
export function isSDKException(error: unknown): error is SDKException {
  return error instanceof SDKException;
}

// Proto re-exports for advanced consumers needing the wire envelope shape.
export type {
  ErrorContext as ProtoErrorContext,
  SDKError as ProtoSDKError,
} from '@runanywhere/proto-ts/errors';
export {
  ErrorCategory as ProtoErrorCategory,
  ErrorCode as ProtoErrorCode,
} from '@runanywhere/proto-ts/errors';
