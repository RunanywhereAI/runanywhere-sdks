/**
 * SDKException.ts
 *
 * Throwable wrapper around the proto-encoded `SDKError` payload generated
 * from `sdk/proto/errors.proto`. Wave 2 mandate: this is the ONLY
 * throwable type in the SDK. All call sites must `throw new SDKException(...)`
 * or use one of the static factory methods (`SDKException.notInitialized`,
 * etc.).
 *
 * Reference: sdk/proto/errors.proto
 *            sdk/runanywhere-proto-ts/dist/errors.d.ts
 */

import {
  ErrorCategory as ErrorCategoryProto,
  ErrorCode as ErrorCodeProto,
  type SDKError as SDKErrorProto,
  type ErrorContext as ErrorContextProto,
  SDKError as SDKErrorProtoCtor,
} from '@runanywhere/proto-ts/errors';

/**
 * Throwable wrapper. Subclass of `Error` so it works with `instanceof Error`
 * and preserves a JS stack trace. Carries the canonical proto payload on
 * `proto` for serialization to analytics / cross-SDK transport.
 */
export class SDKException extends Error {
  readonly proto: SDKErrorProto;

  constructor(proto: SDKErrorProto) {
    super(proto.message || 'SDK error');
    this.proto = proto;
    this.name = 'SDKException';
    Object.setPrototypeOf(this, SDKException.prototype);
  }

  /** Numeric proto error code (e.g. ERROR_CODE_MODEL_NOT_FOUND = 110). */
  get code(): ErrorCodeProto {
    return this.proto.code;
  }

  /** Coarse-grained category bucket. */
  get category(): ErrorCategoryProto {
    return this.proto.category;
  }

  /** Negative rac_result_t value (when present). */
  get cAbiCode(): number | undefined {
    return this.proto.cAbiCode;
  }

  /** Optional source location + telemetry metadata. */
  get context(): ErrorContextProto | undefined {
    return this.proto.context;
  }

  /**
   * Build an SDKException from raw proto fields. Caller-friendly shorthand
   * mirrors the Kotlin / Swift extension-point factories — saves consumers
   * from constructing the wrapped proto manually.
   */
  static of(
    code: ErrorCodeProto,
    message: string,
    options?: {
      category?: ErrorCategoryProto;
      cAbiCode?: number;
      nestedMessage?: string;
      context?: ErrorContextProto;
    }
  ): SDKException {
    const proto = SDKErrorProtoCtor.create({
      code,
      category: options?.category ?? categoryForCode(code),
      message,
      cAbiCode: options?.cAbiCode,
      nestedMessage: options?.nestedMessage,
      context: options?.context,
    });
    return new SDKException(proto);
  }

  // ── Convenience factories (mirror legacy `notInitializedError` etc.) ──

  static notInitialized(component?: string): SDKException {
    const message = component
      ? `${component} not initialized`
      : 'SDK not initialized';
    return SDKException.of(ErrorCodeProto.ERROR_CODE_NOT_INITIALIZED, message);
  }

  static alreadyInitialized(component?: string): SDKException {
    const message = component
      ? `${component} already initialized`
      : 'SDK already initialized';
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_ALREADY_INITIALIZED,
      message
    );
  }

  static invalidInput(details?: string): SDKException {
    const message = details ? `Invalid input: ${details}` : 'Invalid input';
    return SDKException.of(ErrorCodeProto.ERROR_CODE_INVALID_INPUT, message);
  }

  static modelNotFound(modelId?: string): SDKException {
    const message = modelId
      ? `Model not found: ${modelId}`
      : 'Model not found';
    return SDKException.of(ErrorCodeProto.ERROR_CODE_MODEL_NOT_FOUND, message);
  }

  static modelLoadFailed(modelId?: string, cause?: Error): SDKException {
    const message = modelId
      ? `Failed to load model: ${modelId}`
      : 'Failed to load model';
    return SDKException.of(ErrorCodeProto.ERROR_CODE_MODEL_LOAD_FAILED, message, {
      nestedMessage: cause?.message,
    });
  }

  static networkError(details?: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_NETWORK_UNAVAILABLE,
      details ?? 'Network error',
      { nestedMessage: cause?.message }
    );
  }

  static authenticationFailed(details?: string): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_AUTHENTICATION_FAILED,
      details ?? 'Authentication failed'
    );
  }

  static generationFailed(details?: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_GENERATION_FAILED,
      details ?? 'Generation failed',
      { nestedMessage: cause?.message }
    );
  }

  static storageError(details?: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_STORAGE_ERROR,
      details ?? 'Storage error',
      { nestedMessage: cause?.message }
    );
  }

  static notImplemented(feature?: string): SDKException {
    const message = feature
      ? `${feature} not implemented`
      : 'Not implemented';
    return SDKException.of(ErrorCodeProto.ERROR_CODE_NOT_IMPLEMENTED, message);
  }

  static componentNotReady(component?: string): SDKException {
    const message = component
      ? `${component} not ready`
      : 'Component not ready';
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_COMPONENT_NOT_READY,
      message
    );
  }

  static unknown(details?: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_UNKNOWN,
      details ?? 'Unknown error',
      { nestedMessage: cause?.message }
    );
  }
}

/** Type guard for `SDKException`. */
export function isSDKException(error: unknown): error is SDKException {
  return error instanceof SDKException;
}

/**
 * Best-effort coercion from any thrown value to `SDKException`. Already
 * `SDKException` instances pass through; native bridge `Error` instances
 * become `ERROR_CODE_UNKNOWN` with `nestedMessage`. JSON-encoded native
 * errors are parsed; everything else stringifies to UNKNOWN.
 */
export function asSDKException(error: unknown): SDKException {
  if (error instanceof SDKException) return error;
  if (error instanceof Error) {
    return SDKException.unknown(error.message, error);
  }
  if (typeof error === 'string') {
    return SDKException.unknown(error);
  }
  return SDKException.unknown(String(error));
}

/** Category bucket for a proto error code. Mirrors Swift's getCategoryFromCode. */
function categoryForCode(code: ErrorCodeProto): ErrorCategoryProto {
  if (code >= 100 && code < 110)
    return ErrorCategoryProto.ERROR_CATEGORY_CONFIGURATION;
  if (code >= 110 && code < 130) return ErrorCategoryProto.ERROR_CATEGORY_MODEL;
  if (code >= 130 && code < 150)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 150 && code < 180)
    return ErrorCategoryProto.ERROR_CATEGORY_NETWORK;
  if (code >= 180 && code < 220) return ErrorCategoryProto.ERROR_CATEGORY_IO;
  if (code >= 220 && code < 230)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  if (code >= 230 && code < 250)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 250 && code < 280)
    return ErrorCategoryProto.ERROR_CATEGORY_VALIDATION;
  if (code >= 280 && code < 320) return ErrorCategoryProto.ERROR_CATEGORY_IO;
  if (code >= 320 && code < 330) return ErrorCategoryProto.ERROR_CATEGORY_AUTH;
  if (code >= 330 && code < 400) return ErrorCategoryProto.ERROR_CATEGORY_IO;
  if (code >= 400 && code < 500)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 500 && code < 700)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 700 && code < 800)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  if (code >= 800 && code < 900)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
}
