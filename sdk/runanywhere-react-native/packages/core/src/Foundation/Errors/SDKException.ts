/**
 * SDKException.ts
 *
 * Throwable wrapper around the proto-encoded `SDKError` payload generated
 * from `idl/errors.proto`. This is the only throwable type the SDK raises:
 * call sites must `throw new SDKException(...)` directly or use one of the
 * static factory methods (`SDKException.notInitialized`, etc.).
 *
 * Reference: idl/errors.proto, @runanywhere/proto-ts/errors.
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
   * Structured validation field-path accessor.
   *
   * pass3-syn-031: byte-isomorphic with Swift/Kotlin/Flutter SDKException.
   * Reads `context.metadata['field_path']` populated by
   * `SDKException.validationFailed(...)` (see below). Cross-SDK consumer
   * code can rely on `e.fieldPath === 'X.y'` regardless of which SDK
   * threw the exception. Returns `undefined` when the metadata entry is
   * absent (e.g. non-validation exceptions).
   */
  get fieldPath(): string | undefined {
    const meta = this.proto.context?.metadata;
    if (!meta) return undefined;
    // proto-ts emits map<string,string> as a JS object literal.
    const raw = (meta as Record<string, string>)['field_path'];
    return raw && raw.length > 0 ? raw : undefined;
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
    // Round-trip C ABI code: positive proto code ↔ negative rac_result_t.
    // Mirrors Swift SDKException.init: `if raw > 0 && raw <= 899 { proto.cAbiCode = -Int32(raw) }`.
    const cAbiCode =
      options?.cAbiCode !== undefined
        ? options.cAbiCode
        : code > 0 && code <= 899
          ? -code
          : undefined;
    const proto = SDKErrorProtoCtor.create({
      code,
      category: options?.category ?? categoryForCode(code),
      message,
      cAbiCode,
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
    // Swift parity: notInitialized uses category .component, not .configuration.
    return SDKException.of(ErrorCodeProto.ERROR_CODE_NOT_INITIALIZED, message, {
      category: ErrorCategoryProto.ERROR_CATEGORY_COMPONENT,
    });
  }

  /**
   * Raised when the NitroModules native module (HybridRunAnywhereCore)
   * cannot be accessed. Matches Kotlin's `SDKException.notInitialized`
   * semantics for the bridge layer.
   */
  static nativeModuleUnavailable(details?: string): SDKException {
    const message = details
      ? `Native module not available: ${details}`
      : 'Native module not available';
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_NOT_INITIALIZED,
      message
    );
  }

  /**
   * Raised when a proto-byte response from the native bridge is empty
   * or fails to decode into the expected message shape.
   */
  static protoDecodeFailed(operation: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_INTERNAL,
      `${operation} returned an empty or invalid proto result`,
      { nestedMessage: cause?.message }
    );
  }

  /**
   * Raised when a component (LLM, STT, TTS, VAD, VoiceAgent) is not yet
   * ready for the requested operation. Matches Swift/Kotlin pattern.
   */
  static generationFailedWith(details: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_GENERATION_FAILED,
      details,
      { nestedMessage: cause?.message }
    );
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

  /**
   * Structured validation failure.
   *
   * pass3-syn-031: byte-isomorphic with Swift/Kotlin/Flutter
   * `SDKException.validationFailed(...)`. Encodes the structured field
   * path into `proto.context.metadata['field_path']` so consumers can
   * read it back uniformly across SDKs via {@link fieldPath}.
   *
   * Recommended usage from generated `validate<Msg>` helpers:
   *
   *     throw SDKException.validationFailed({
   *       fieldPath: 'VADConfiguration.sample_rate',
   *       message: 'sample_rate must be > 0',
   *     });
   *
   * Code / category / cAbiCode mirror the Swift / Kotlin / Flutter wire
   * shape (ERROR_CODE_INVALID_ARGUMENT = 259, ERROR_CATEGORY_VALIDATION,
   * cAbiCode = -259).
   */
  static validationFailed(args: {
    fieldPath: string;
    message: string;
    cause?: Error;
  }): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_INVALID_ARGUMENT,
      args.message,
      {
        category: ErrorCategoryProto.ERROR_CATEGORY_VALIDATION,
        cAbiCode: -259,
        nestedMessage: args.cause?.message,
        // ErrorContext.metadata carries the structured field path so the
        // accessor `e.fieldPath` returns the value across SDKs.
        context: {
          metadata: { field_path: args.fieldPath },
          sourceFile: undefined,
          sourceLine: undefined,
          operation: undefined,
        } as ErrorContextProto,
      }
    );
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
      ErrorCodeProto.ERROR_CODE_NETWORK_ERROR,
      details ?? 'Network error',
      { nestedMessage: cause?.message }
    );
  }

  static networkUnavailable(details?: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCodeProto.ERROR_CODE_NETWORK_UNAVAILABLE,
      details ?? 'Network unavailable',
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

  /**
   * Common shortcut: cancelled operation. Not logged (cancellation is expected).
   * Mirrors Swift `SDKException.cancelled` and Dart `SDKException.cancelled`.
   */
  static cancelled(message = 'Operation cancelled'): SDKException {
    return SDKException.of(ErrorCodeProto.ERROR_CODE_CANCELLED, message, {
      category: ErrorCategoryProto.ERROR_CATEGORY_INTERNAL,
    });
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

/**
 * Map a proto `ErrorCode` (positive value, matches `|rac_result_t|`) to the
 * canonical proto `ErrorCategory`.
 *
 * Verbatim port of the canonical 18-range table in
 * `sdk/runanywhere-commons/src/core/rac_error_proto.cpp::category_for_code()`.
 * The native bridge cannot be called synchronously from every JS throw site
 * (especially during bridge bootstrap), so the table is replicated here; any
 * change to the canonical mapping MUST be mirrored in this function (and in
 * the Web SDK equivalent). See commons-074-C.
 */
function categoryForCode(code: ErrorCodeProto): ErrorCategoryProto {
  if (code === 0) return ErrorCategoryProto.ERROR_CATEGORY_UNSPECIFIED;
  if (code >= 100 && code <= 109)
    return ErrorCategoryProto.ERROR_CATEGORY_CONFIGURATION;
  if (code >= 110 && code <= 129) return ErrorCategoryProto.ERROR_CATEGORY_MODEL;
  if (code >= 130 && code <= 149)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 150 && code <= 179)
    return ErrorCategoryProto.ERROR_CATEGORY_NETWORK;
  if ((code >= 180 && code <= 219) || (code >= 280 && code <= 299)) {
    return ErrorCategoryProto.ERROR_CATEGORY_IO;
  }
  if (code >= 220 && code <= 229)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  if (code >= 230 && code <= 249)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 250 && code <= 279)
    return ErrorCategoryProto.ERROR_CATEGORY_VALIDATION;
  if (code >= 300 && code <= 319)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 320 && code <= 329) return ErrorCategoryProto.ERROR_CATEGORY_AUTH;
  if (code >= 330 && code <= 349) return ErrorCategoryProto.ERROR_CATEGORY_AUTH;
  if (code >= 350 && code <= 369) return ErrorCategoryProto.ERROR_CATEGORY_IO;
  if (code >= 370 && code <= 379)
    return ErrorCategoryProto.ERROR_CATEGORY_VALIDATION;
  if (code >= 380 && code <= 389)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  if (code >= 400 && code <= 499)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 500 && code <= 599)
    return ErrorCategoryProto.ERROR_CATEGORY_CONFIGURATION;
  if (code >= 600 && code <= 699)
    return ErrorCategoryProto.ERROR_CATEGORY_COMPONENT;
  if (code >= 700 && code <= 799)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  if (code >= 800 && code <= 899)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  if (code >= 900 && code <= 999)
    return ErrorCategoryProto.ERROR_CATEGORY_INTERNAL;
  return ErrorCategoryProto.ERROR_CATEGORY_UNSPECIFIED;
}
