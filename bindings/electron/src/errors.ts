// errors.ts — SDKException, the single throwable type the SDK raises. Mirrors the
// shape used by the Swift / Kotlin / React-Native / Web SDKs so cross-platform
// consumer code can read `e.code` / `e.category` / `e.recoverySuggestion` /
// `e.fieldPath` uniformly.
//
// `ErrorCode`, `ErrorCategory`, and `ErrorSeverity` are the GENERATED proto enums
// from `idl/errors.proto`, re-exported rather than re-declared — the Web SDK does
// the same (`Foundation/SDKException.ts`). A local subset would silently collapse
// the 115 commons codes it did not list, which is exactly the bug this file used
// to have.

import {
  ErrorCategory,
  ErrorCode,
  ErrorSeverity,
  SDKError,
} from '@runanywhere/proto-ts/errors';
// Same reasoning one level up: the code -> category range table is shared, not
// re-declared here. `@runanywhere/proto-ts/convenience/errors_category` is the
// canonical table for Web, React Native and Electron, and says so.
import { categoryForCode } from '@runanywhere/proto-ts/convenience/errors_category';

export { ErrorCategory, ErrorCode, ErrorSeverity, categoryForCode };

/** Strip a generated enum's `ERROR_CODE_` / `ERROR_CATEGORY_` prefix from a member name. */
type ShortName<Key extends string, Prefix extends string> = Key extends `${Prefix}${infer Rest}`
  ? Rest
  : never;

/** Short member name of an {@link ErrorCode}, e.g. `MODEL_NOT_FOUND`. */
export type ErrorCodeName = ShortName<keyof typeof ErrorCode & string, 'ERROR_CODE_'>;
/** Short member name of an {@link ErrorCategory}, e.g. `NETWORK`. */
export type ErrorCategoryName = ShortName<keyof typeof ErrorCategory & string, 'ERROR_CATEGORY_'>;

/**
 * Drop `prefix` from every forward member of a generated numeric enum.
 *
 * A TypeScript numeric enum object carries both the forward mapping and the
 * numeric reverse mapping, plus ts-proto's `UNRECOGNIZED = -1`; only the
 * prefixed forward entries survive.
 */
function shortNames(members: Record<string, string | number>, prefix: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(members)) {
    if (typeof value !== 'number' || !key.startsWith(prefix)) continue;
    out[key.slice(prefix.length)] = value;
  }
  return out;
}

/**
 * Short-name aliases for {@link ErrorCode}, so app code reads
 * `ErrorCodes.MODEL_NOT_FOUND` rather than `ErrorCode.ERROR_CODE_MODEL_NOT_FOUND`.
 * Derived from the generated enum, never hand-listed, so it can never drift.
 */
export const ErrorCodes: Readonly<Record<ErrorCodeName, ErrorCode>> = Object.freeze(
  shortNames(ErrorCode, 'ERROR_CODE_')
) as Readonly<Record<ErrorCodeName, ErrorCode>>;

/** Short-name aliases for {@link ErrorCategory}. See {@link ErrorCodes}. */
export const ErrorCategories: Readonly<Record<ErrorCategoryName, ErrorCategory>> = Object.freeze(
  shortNames(ErrorCategory, 'ERROR_CATEGORY_')
) as Readonly<Record<ErrorCategoryName, ErrorCategory>>;

export interface SDKErrorFields {
  code: ErrorCode;
  message: string;
  category?: ErrorCategory;
  cAbiCode?: number;
  nestedMessage?: string;
  fieldPath?: string;
  /** Which subsystem failed, as commons named it (e.g. "model", "generation"). */
  component?: string;
  /** Whether commons believes the same call could succeed on a retry. */
  retryable?: boolean;
  /** Correlates the failure with the request that caused it. */
  requestId?: string;
  severity?: ErrorSeverity;
  /** When commons minted the error, ms since epoch. */
  timestampMs?: number;
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
  /** Subsystem commons blamed; empty when it did not say. */
  readonly component: string;
  /** Whether a retry is worth offering. False unless commons said otherwise. */
  readonly retryable: boolean;
  /** Request correlation id; empty when the failure carried none. */
  readonly requestId: string;
  readonly severity: ErrorSeverity;
  /** When the error was minted, ms since epoch. */
  readonly timestampMs: number;

  constructor(fields: SDKErrorFields) {
    super(fields.message || 'SDK error');
    this.name = 'SDKException';
    this.code = fields.code;
    this.category = fields.category ?? categoryForCode(fields.code);
    this.cAbiCode =
      fields.cAbiCode ?? (fields.code > 0 && fields.code <= 899 ? -fields.code : undefined);
    this.nestedMessage = fields.nestedMessage;
    this.fieldPath = fields.fieldPath;
    this.component = fields.component ?? '';
    this.retryable = fields.retryable ?? false;
    this.requestId = fields.requestId ?? '';
    this.severity =
      fields.severity ??
      (fields.code === ErrorCode.ERROR_CODE_UNSPECIFIED
        ? ErrorSeverity.ERROR_SEVERITY_UNSPECIFIED
        : ErrorSeverity.ERROR_SEVERITY_ERROR);
    this.timestampMs = fields.timestampMs ?? Date.now();
    Object.setPrototypeOf(this, SDKException.prototype);
  }

  /** Human-readable recovery hint for common codes, mirroring the other SDKs. */
  get recoverySuggestion(): string | undefined {
    switch (this.code) {
      case ErrorCode.ERROR_CODE_NOT_INITIALIZED:
        return 'Initialize the SDK (RunAnywhere.initialize()) before using it.';
      case ErrorCode.ERROR_CODE_MODEL_NOT_FOUND:
        return 'Ensure the model is downloaded and the path/id is correct.';
      case ErrorCode.ERROR_CODE_MODEL_LOAD_FAILED:
        return 'Check the model file is valid and compatible.';
      case ErrorCode.ERROR_CODE_STORAGE_ERROR:
        return 'Free up storage space and try again.';
      default:
        return undefined;
    }
  }

  /** Expected/routine errors (cancellation) that need not be logged as errors. */
  get isExpected(): boolean {
    return this.code === ErrorCode.ERROR_CODE_CANCELLED;
  }

  static of(code: ErrorCode, message: string, options?: Omit<SDKErrorFields, 'code' | 'message'>): SDKException {
    return new SDKException({ code, message, ...options });
  }

  /** Build from a decoded proto `SDKError` payload (the D5 structured-error field). */
  static fromProto(error: SDKError): SDKException {
    return fromStructuredError({
      code: error.code,
      message: error.message,
      category: error.category,
      cAbiCode: error.cAbiCode,
      nestedMessage: error.nestedMessage,
      fieldPath: error.param,
      component: error.component,
      retryable: error.retryable,
      requestId: error.requestId,
      severity: error.severity,
      timestampMs: error.timestampMs,
    });
  }

  static notInitialized(component?: string): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_NOT_INITIALIZED,
      component ? `${component} not initialized` : 'SDK not initialized',
      { category: ErrorCategory.ERROR_CATEGORY_COMPONENT }
    );
  }
  static invalidInput(details?: string): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_INVALID_INPUT,
      details ? `Invalid input: ${details}` : 'Invalid input'
    );
  }
  static validationFailed(args: { fieldPath: string; message: string }): SDKException {
    return SDKException.of(ErrorCode.ERROR_CODE_INVALID_ARGUMENT, args.message, {
      category: ErrorCategory.ERROR_CATEGORY_VALIDATION,
      cAbiCode: -ErrorCode.ERROR_CODE_INVALID_ARGUMENT,
      fieldPath: args.fieldPath,
    });
  }
  static modelNotFound(modelId?: string): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
      modelId ? `Model not found: ${modelId}` : 'Model not found'
    );
  }
  static modelLoadFailed(modelId?: string, cause?: Error): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
      modelId ? `Failed to load model: ${modelId}` : 'Failed to load model',
      { nestedMessage: cause?.message }
    );
  }
  static generationFailed(details?: string, cause?: Error): SDKException {
    return SDKException.of(ErrorCode.ERROR_CODE_GENERATION_FAILED, details ?? 'Generation failed', {
      nestedMessage: cause?.message,
    });
  }
  static invalidState(details?: string): SDKException {
    return SDKException.of(ErrorCode.ERROR_CODE_INVALID_STATE, details ?? 'Invalid state', {
      category: ErrorCategory.ERROR_CATEGORY_INTERNAL,
    });
  }
  static notImplemented(feature?: string): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
      feature ? `${feature} not implemented` : 'Not implemented'
    );
  }
  /** Linked backend / modality missing — prefer over a crash or bare Error. */
  static featureNotAvailable(feature?: string): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
      feature ? `${feature} is not available` : 'Feature not available',
      { category: ErrorCategory.ERROR_CATEGORY_CONFIGURATION, component: 'backend' }
    );
  }
  /**
   * Thin addon with an empty plugin registry (core package alone).
   * Same code as {@link featureNotAvailable}; dedicated message for register() guidance.
   */
  static noBackendEngines(): SDKException {
    return SDKException.of(
      ErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
      'No inference backends are registered. Install and call register() on at least one of ' +
        '@runanywhere/electron-llamacpp, @runanywhere/electron-onnx, or @runanywhere/electron-sherpa ' +
        'in the Electron main process before loading models.',
      { category: ErrorCategory.ERROR_CATEGORY_CONFIGURATION, component: 'backend' }
    );
  }
  static cancelled(message = 'Operation cancelled'): SDKException {
    return SDKException.of(ErrorCode.ERROR_CODE_CANCELLED, message, {
      category: ErrorCategory.ERROR_CATEGORY_INTERNAL,
    });
  }
  static unknown(details?: string, cause?: Error): SDKException {
    return SDKException.of(ErrorCode.ERROR_CODE_UNKNOWN, details ?? 'Unknown error', {
      nestedMessage: cause?.message,
    });
  }
}

/** Type guard. */
export function isSDKException(error: unknown): error is SDKException {
  return error instanceof SDKException;
}

type ErrorLike = {
  message?: unknown;
  code?: unknown;
  cAbiCode?: unknown;
  category?: unknown;
  nestedMessage?: unknown;
  fieldPath?: unknown;
  /** Serialized `runanywhere.v1.SDKError` attached by the addon's proto error path. */
  sdkError?: unknown;
};

/**
 * Decode the `SDKError` bytes the addon attaches to every proto-path failure.
 * This is the authoritative mapping — commons produced it via
 * `rac_result_to_proto_error`, so when it is present the shared `categoryForCode`
 * table is not consulted at all.
 */
function fromSerializedSdkError(value: unknown): SDKException | null {
  if (!(value instanceof Uint8Array) || value.length === 0) return null;
  try {
    return SDKException.fromProto(SDKError.decode(value));
  } catch {
    return null;
  }
}

function finiteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

/** Every value `idl/errors.proto` defines, for the one check below. */
const KNOWN_ERROR_CODES: ReadonlySet<number> = new Set(
  Object.values(ErrorCode).filter((v): v is number => typeof v === 'number' && v >= 0)
);

/**
 * Build an exception from whatever fields a failure carried.
 *
 * Every one of the 131 codes `idl/errors.proto` declares passes through — the
 * subset this file used to enumerate is what turned 115 of them into `UNKNOWN`.
 * A magnitude that is not a declared code at all (a rac value with no proto
 * counterpart) still reports `UNKNOWN`, with the raw value readable on
 * `cAbiCode`, because typing it as an `ErrorCode` would be a lie.
 *
 * A category is only derived when the wire supplied none — proto3 leaves an
 * unset enum at 0, so `UNSPECIFIED` counts as unset.
 */
function fromStructuredError(args: {
  code: number;
  message: string;
  cAbiCode?: number;
  category?: number;
  nestedMessage?: string;
  fieldPath?: string;
  component?: string;
  retryable?: boolean;
  requestId?: string;
  severity?: number;
  timestampMs?: number;
}): SDKException {
  const magnitude = Math.abs(Math.trunc(args.code));
  const code = (KNOWN_ERROR_CODES.has(magnitude) ? magnitude : ErrorCode.ERROR_CODE_UNKNOWN) as ErrorCode;
  const wireCategory =
    args.category != null && Math.trunc(args.category) !== ErrorCategory.ERROR_CATEGORY_UNSPECIFIED
      ? (Math.trunc(args.category) as ErrorCategory)
      : undefined;
  return new SDKException({
    code,
    message: args.message,
    cAbiCode: args.cAbiCode,
    category: wireCategory ?? categoryForCode(code),
    nestedMessage: args.nestedMessage,
    fieldPath: args.fieldPath,
    component: args.component,
    retryable: args.retryable,
    requestId: args.requestId,
    severity: args.severity as ErrorSeverity | undefined,
    timestampMs: args.timestampMs,
  });
}

/**
 * Raise an SDKException for a negative ``rac_result_t`` (parity with Python
 * ``raise_for_rac``). Preserves the raw negative ABI code as ``cAbiCode`` and
 * uses its positive absolute value as the canonical SDK ``ErrorCode``.
 */
export function raiseForRac(racCode: number, message?: string): never {
  const cAbiCode = -Math.abs(Math.trunc(racCode || 0));
  throw fromStructuredError({
    code: Math.abs(cAbiCode) || ErrorCode.ERROR_CODE_UNKNOWN,
    cAbiCode,
    message: message ?? `Native call failed (rac=${cAbiCode})`,
  });
}

/**
 * Parse a trailing negative rac code from a native error message
 * (e.g. ``"load_model failed: -111"``). Returns null when none found.
 */
export function parseRacCodeFromMessage(message: string): number | null {
  const m = /failed:\s*(-?\d+)\s*(?:\(|$)/i.exec(message) ?? /(?:^|\s)(-[1-9]\d{0,3})\s*$/.exec(message);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) && n < 0 ? n : null;
}

/** Coerce any thrown value into an SDKException (matches RN/Web `asSDKException`). */
export function asSDKException(error: unknown): SDKException {
  if (error instanceof SDKException) return error;
  if (error && typeof error === 'object') {
    const candidate = error as ErrorLike;
    const structured = fromSerializedSdkError(candidate.sdkError);
    if (structured) return structured;
    const message =
      stringValue(candidate.message) ??
      (error instanceof Error ? error.message : undefined) ??
      String(error);
    const cAbiCode = finiteNumber(candidate.cAbiCode);
    if (cAbiCode != null && cAbiCode !== 0) {
      return fromStructuredError({
        code: Math.abs(cAbiCode),
        cAbiCode,
        message,
        category: finiteNumber(candidate.category) ?? undefined,
        nestedMessage: stringValue(candidate.nestedMessage),
        fieldPath: stringValue(candidate.fieldPath),
      });
    }
    const code = finiteNumber(candidate.code);
    if (code != null && code > 0) {
      return fromStructuredError({
        code,
        cAbiCode: -Math.abs(Math.trunc(code)),
        message,
        category: finiteNumber(candidate.category) ?? undefined,
        nestedMessage: stringValue(candidate.nestedMessage),
        fieldPath: stringValue(candidate.fieldPath),
      });
    }
    const rac = parseRacCodeFromMessage(message);
    if (rac !== null) {
      return fromStructuredError({
        code: Math.abs(rac),
        cAbiCode: rac,
        message,
        nestedMessage: error instanceof Error ? error.message : undefined,
      });
    }
    if (error instanceof Error) return SDKException.unknown(message, error);
    return SDKException.unknown(message);
  }
  if (typeof error === 'string') {
    const rac = parseRacCodeFromMessage(error);
    if (rac !== null) {
      return fromStructuredError({ code: Math.abs(rac), cAbiCode: rac, message: error });
    }
    return SDKException.unknown(error);
  }
  return SDKException.unknown(String(error));
}
