/**
 * RunAnywhere Web SDK - SDKException.
 *
 * SDKException is the SOLE exception class. The legacy `SDKError` has
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
 * Map a signed-negative `rac_result_t` code to the matching proto-ts `ErrorCategory`.
 *
 * Verbatim port of the canonical 18-range table in
 * `sdk/runanywhere-commons/src/core/rac_error_proto.cpp::category_for_code()`.
 * Web cannot call the C++ helper synchronously before WASM is loaded, so the
 * table is replicated here; any change to the canonical mapping MUST be
 * mirrored in this function (and in the RN equivalent).
 */
function categoryForCode(code: number): ProtoErrorCategory {
  if (code === 0) return ProtoErrorCategory.ERROR_CATEGORY_UNSPECIFIED;
  const abs = Math.abs(code);
  if (abs >= 100 && abs <= 109) return ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION;
  if (abs >= 110 && abs <= 129) return ProtoErrorCategory.ERROR_CATEGORY_MODEL;
  if (abs >= 130 && abs <= 149) return ProtoErrorCategory.ERROR_CATEGORY_INTERNAL;
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
 * Map a signed-negative `rac_result_t` code to the matching proto-ts ErrorCode
 * (positive values, since proto3 forbids negative enum literals).
 */
function protoCodeForSDKCode(code: number): ProtoErrorCode {
  const positive = Math.abs(code);
  if (Object.values(ProtoErrorCode).includes(positive)) {
    return positive as ProtoErrorCode;
  }
  return ProtoErrorCode.ERROR_CODE_UNSPECIFIED;
}

function severityForCode(code: number): ProtoErrorSeverity {
  return code === 0
    ? ProtoErrorSeverity.ERROR_SEVERITY_UNSPECIFIED
    : ProtoErrorSeverity.ERROR_SEVERITY_ERROR;
}

function componentForCode(code: number): string {
  if (code === 0) return 'sdk';
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

  constructor(codeOrProto: number | ProtoSDKError, message?: string, details?: string) {
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

  /** The signed-negative C ABI code (matches rac_result_t). */
  get code(): number {
    return this.proto.cAbiCode ?? 0;
  }

  /** The positive proto ErrorCode value (matches Swift proto.code / RAErrorCode.rawValue). */
  get protoCode(): ProtoErrorCode {
    return this.proto.code;
  }

  /** Optional structured details (proto.nestedMessage). */
  get details(): string | undefined {
    return this.proto.nestedMessage;
  }

  /**
   * Structured validation field-path accessor.
   *
   * Byte-isomorphic with Swift/Kotlin/Flutter/RN SDKException. Reads the typed
   * `context.fieldPath` (first-class proto field) so cross-SDK consumer code
   * can rely on `e.fieldPath === 'X.y'` regardless of which SDK threw the
   * exception. Returns `undefined` when absent (e.g. non-validation exceptions).
   */
  get fieldPath(): string | undefined {
    const typed = this.proto.context?.fieldPath;
    return typed && typed.length > 0 ? typed : undefined;
  }

  /** Whether the result code indicates success (code === 0). */
  static isSuccess(resultCode: number): boolean {
    return resultCode === 0;
  }

  /** Build an SDKException from a signed numeric `rac_result_t` code + message. */
  static fromCode(code: number, message: string, details?: string): SDKException {
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
    return SDKException.fromCode(resultCode, message, details);
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
    // Swift canonical: notInitialized uses category=COMPONENT (SDKException.swift:178-179).
    // categoryForCode(-100) returns CONFIGURATION (matching C++ commons range table), so
    // we construct the proto directly to override the category to COMPONENT.
    const proto: ProtoSDKError = {
      category: ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
      code: ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      message,
      nestedMessage: undefined,
      context: undefined,
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
      component: componentForCode(-ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED),
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    return new SDKException(proto);
  }

  /**
   * Canonical cancellation factory.
   *
   * Mirrors Swift `SDKException.cancelled(_:)` (SDKException.swift:225-226):
   * code=.cancelled, category=.internal, shouldLog=false. Uses proto
   * ERROR_CODE_CANCELLED=380 with cAbiCode=-380; isExpected() returns true so
   * callers suppress ERROR-level logging.
   */
  static cancelled(message = 'Operation cancelled'): SDKException {
    const proto: ProtoSDKError = {
      category: ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
      code: ProtoErrorCode.ERROR_CODE_CANCELLED,
      cAbiCode: -380,
      message,
      nestedMessage: undefined,
      context: undefined,
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_UNSPECIFIED,
      component: 'sdk',
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    return new SDKException(proto);
  }

  static wasmNotLoaded(message = 'WASM module not loaded'): SDKException {
    return SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED, message);
  }

  static modelNotFound(modelId: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
      `Model not found: ${modelId}`,
    );
  }

  static componentNotReady(component: string, details?: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
      `Component not ready: ${component}`,
      details,
    );
  }

  static generationFailed(details?: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
      'Generation failed',
      details,
    );
  }

  static backendNotAvailable(feature: string, details?: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      `Backend not available for: ${feature}`,
      details,
    );
  }

  static invalidInput(message: string, details?: string): SDKException {
    return SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_INVALID_PARAMETER, message, details);
  }

  /**
   * Structured validation failure.
   *
   * Byte-isomorphic with Swift/Kotlin/Flutter/RN
   * `SDKException.validationFailed(...)`. Encodes the structured field
   * path into the typed `proto.context.fieldPath` so consumers can
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
      // ErrorContext.fieldPath carries the structured field path so the
      // accessor `e.fieldPath` returns the value across SDKs.
      context: {
        metadata: {},
        sourceFile: undefined,
        sourceLine: undefined,
        operation: undefined,
        fieldPath: args.fieldPath,
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

/**
 * Returns true when the proto error code represents a routine/expected
 * condition (cancellation) that should not be logged at ERROR level.
 *
 * Mirrors Swift `RAErrorCode.isExpected`, Kotlin `ProtoErrorCode.isExpected`,
 * and Dart `ErrorCodeClassification.isExpected` — all check the same two codes.
 */
export function isExpected(code: ProtoErrorCode): boolean {
  return code === ProtoErrorCode.ERROR_CODE_CANCELLED || code === ProtoErrorCode.ERROR_CODE_STREAM_CANCELLED;
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
