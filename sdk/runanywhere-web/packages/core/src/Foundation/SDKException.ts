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
  ErrorSeverity as ProtoErrorSeverity,
  SDKError as SDKErrorCodec,
  type SDKError as ProtoSDKError,
} from '@runanywhere/proto-ts/errors';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm';
import type { SDKLogger } from './SDKLogger';

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
 *
 * Verbatim port of the canonical 18-range table in
 * `sdk/runanywhere-commons/src/core/rac_error_proto.cpp::category_for_code()`.
 * Web cannot call the C++ helper synchronously before WASM is loaded, so the
 * table is replicated here; any change to the canonical mapping MUST be
 * mirrored in this function (and in the RN equivalent). See commons-074-A.
 */
function categoryForCode(code: SDKErrorCode): ProtoErrorCategory {
  if (code === 0) return ProtoErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
  const abs = Math.abs(code);
  if (abs >= 100 && abs <= 109) return ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION;
  if (abs >= 110 && abs <= 129) return ProtoErrorCategory.ERROR_CATEGORY_MODEL;
  if (abs >= 130 && abs <= 149) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 150 && abs <= 179) return ProtoErrorCategory.ERROR_CATEGORY_NETWORK;
  if ((abs >= 180 && abs <= 219) || (abs >= 280 && abs <= 299)) {
    return ProtoErrorCategory.ERROR_CATEGORY_IO;
  }
  if (abs >= 220 && abs <= 229) return ProtoErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 230 && abs <= 249) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 250 && abs <= 279) return ProtoErrorCategory.ERROR_CATEGORY_VALIDATION;
  if (abs >= 300 && abs <= 319) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 320 && abs <= 329) return ProtoErrorCategory.ERROR_CATEGORY_AUTH;
  if (abs >= 330 && abs <= 349) return ProtoErrorCategory.ERROR_CATEGORY_AUTH;
  if (abs >= 350 && abs <= 369) return ProtoErrorCategory.ERROR_CATEGORY_IO;
  if (abs >= 370 && abs <= 379) return ProtoErrorCategory.ERROR_CATEGORY_VALIDATION;
  if (abs >= 380 && abs <= 389) return ProtoErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 400 && abs <= 499) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 500 && abs <= 599) return ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION;
  if (abs >= 600 && abs <= 699) return ProtoErrorCategory.ERROR_CATEGORY_COMPONENT;
  if (abs >= 700 && abs <= 799) return ProtoErrorCategory.ERROR_CATEGORY_INTERNAL;
  if (abs >= 800 && abs <= 899) return ProtoErrorCategory.ERROR_CATEGORY_INTERNAL;
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

function severityForCode(code: SDKErrorCode): ProtoErrorSeverity {
  return code === SDKErrorCode.Success
    ? ProtoErrorSeverity.ERROR_SEVERITY_UNSPECIFIED
    : ProtoErrorSeverity.ERROR_SEVERITY_ERROR;
}

function componentForCode(code: SDKErrorCode): string {
  if (code === SDKErrorCode.Success) return 'sdk';
  const abs = Math.abs(code);
  if (abs >= 100 && abs <= 109) return 'sdk';
  if (abs >= 110 && abs <= 129) return 'model';
  if (abs >= 130 && abs <= 149) return 'generation';
  if (abs >= 150 && abs <= 179) return 'network';
  if ((abs >= 180 && abs <= 219) || (abs >= 280 && abs <= 299)) return 'storage';
  if (abs >= 220 && abs <= 229) return 'sdk';
  if (abs >= 230 && abs <= 249) return 'component';
  if (abs >= 250 && abs <= 279) return 'validation';
  if (abs >= 300 && abs <= 319) return 'component';
  if (abs >= 320 && abs <= 349) return 'auth';
  if (abs >= 350 && abs <= 369) return 'storage';
  if (abs >= 370 && abs <= 379) return 'validation';
  if (abs >= 380 && abs <= 389) return 'sdk';
  if (abs >= 400 && abs <= 499) return 'component';
  if (abs >= 500 && abs <= 599) return 'sdk';
  if (abs >= 600 && abs <= 699) return 'backend';
  if (abs >= 700 && abs <= 899) return 'sdk';
  if (abs >= 900 && abs <= 999) return 'wasm';
  return 'sdk';
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
        timestampMs: Date.now(),
        severity: severityForCode(code),
        component: componentForCode(code),
        retryable: false,
        remediationHint: '',
        correlationId: '',
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

  /**
   * Structured validation field-path accessor.
   *
   * pass3-syn-031: byte-isomorphic with Swift/Kotlin/Flutter/RN SDKException.
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

  /** Whether the result code indicates success (code === 0). */
  static isSuccess(resultCode: number): boolean {
    return resultCode === 0;
  }

  /** Build an SDKException from a signed numeric SDKErrorCode + message. */
  static fromCode(code: SDKErrorCode, message: string, details?: string): SDKException {
    return new SDKException(code, message, details);
  }

  /**
   * Build an SDKException from a raw `rac_result_t` result code.
   *
   * When a loaded WASM [wasm] module is supplied, the rac_result_t -> proto
   * translation is routed through the canonical commons helper
   * `rac_result_to_proto_error` (mirroring Swift's `SDKException.from(rcResult:)`)
   * so code/category/message stay byte-identical across SDKs. Without a module
   * (e.g. before WASM is loaded), it falls back to the local mapping table —
   * the same behaviour as before this routing was added.
   */
  static fromRACResult(
    resultCode: number,
    details?: string,
    wasm?: { module: ProtoWasmModule; logger: SDKLogger },
  ): SDKException {
    if (wasm && typeof wasm.module._rac_wasm_result_to_proto_error === 'function') {
      const proto = SDKException.protoFromCommons(wasm.module, wasm.logger, resultCode);
      if (proto) {
        if (details && !proto.nestedMessage) proto.nestedMessage = details;
        return new SDKException(proto);
      }
    }
    const message = `RACommons error: ${resultCode}`;
    return SDKException.fromCode(resultCode as SDKErrorCode, message, details);
  }

  /**
   * Decode the canonical commons SDKError proto for [resultCode] via the
   * `_rac_wasm_result_to_proto_error` WASM export. Returns `undefined` when the
   * export is unavailable or yields no payload, letting callers fall back to
   * the local mapping.
   */
  private static protoFromCommons(
    module: ProtoWasmModule,
    logger: SDKLogger,
    resultCode: number,
  ): ProtoSDKError | undefined {
    const bridge = new ProtoWasmBridge(module, logger);
    const bytes = bridge.readResultProto(
      (outPtr) => module._rac_wasm_result_to_proto_error!(resultCode, outPtr),
      'rac_wasm_result_to_proto_error',
    );
    if (!bytes || bytes.length === 0) return undefined;
    try {
      return SDKErrorCodec.decode(bytes);
    } catch {
      return undefined;
    }
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

  static invalidInput(message: string, details?: string): SDKException {
    return SDKException.fromCode(SDKErrorCode.InvalidParameter, message, details);
  }

  /**
   * Structured validation failure.
   *
   * pass3-syn-031: byte-isomorphic with Swift/Kotlin/Flutter/RN
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
   * Code / category / cAbiCode mirror the Swift / Kotlin / Flutter / RN
   * wire shape (ERROR_CODE_INVALID_ARGUMENT = 259, ERROR_CATEGORY_VALIDATION,
   * cAbiCode = -259).
   */
  static validationFailed(args: {
    fieldPath: string;
    message: string;
    cause?: Error;
  }): SDKException {
    const proto: ProtoSDKError = {
      category: ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
      code: ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT,
      cAbiCode: -259,
      message: args.message,
      nestedMessage: args.cause?.message,
      // ErrorContext.metadata carries the structured field path so the
      // accessor `e.fieldPath` returns the value across SDKs.
      context: {
        metadata: { field_path: args.fieldPath },
        sourceFile: undefined,
        sourceLine: undefined,
        operation: undefined,
      },
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
      component: 'validation',
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    return new SDKException(proto);
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
  ErrorSeverity as ProtoErrorSeverity,
} from '@runanywhere/proto-ts/errors';
