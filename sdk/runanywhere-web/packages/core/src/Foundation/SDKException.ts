/**
 * RunAnywhere Web SDK - SDKException.
 *
 * SDKException is the SOLE exception class. The legacy `SDKError` has
 * been deleted; all throw sites now use SDKException. SDKException wraps the
 * canonical proto-ts `SDKError` shape from `@runanywhere/proto-ts/errors` so a
 * thrown error can carry the full proto envelope (category, code, message,
 * nested_message, c_abi_code, context) for wire interop while still behaving
 * like a plain `Error` to TS callers.
 *
 * Source of truth (wire shape): idl/errors.proto
 *   - ProtoSDKError = { category, code, c_abi_code, message, nested_message?, ... }
 */
import {
  errorCategoryToJSON,
  errorCodeToJSON,
  ErrorCategory as ProtoErrorCategory,
  ErrorCode as ProtoErrorCode,
  ErrorSeverity as ProtoErrorSeverity,
  SDKError as SDKErrorCodec,
  type SDKError as ProtoSDKError,
} from '@runanywhere/proto-ts/errors';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm';
import { SDKLogger } from './SDKLogger';

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

  /** The positive proto ErrorCode value. Mirrors Swift `SDKException.code`
   * (`RAErrorCode`, SDKException.swift:62). */
  get code(): ProtoErrorCode {
    return this.proto.code;
  }

  /** The signed-negative C ABI code (matches rac_result_t). Mirrors the
   * proto `cAbiCode` field Swift exposes via `proto.cAbiCode` / `rawCABICode`. */
  get cAbiCode(): number {
    return this.proto.cAbiCode ?? 0;
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

  /**
   * Human-readable remediation hint for the wrapped error code.
   *
   * Mirrors Swift's computed `recoverySuggestion` property
   * (SDKException.swift:87-110) case-for-case. Returns `undefined` for codes
   * with no actionable suggestion (including cancellation).
   */
  get recoverySuggestion(): string | undefined {
    switch (this.proto.code) {
      case ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED:
        return 'Initialize the component before using it.';
      case ProtoErrorCode.ERROR_CODE_MODEL_NOT_FOUND:
        return 'Ensure the model is downloaded and the path is correct.';
      case ProtoErrorCode.ERROR_CODE_NETWORK_UNAVAILABLE:
        return 'Check your internet connection and try again.';
      case ProtoErrorCode.ERROR_CODE_INSUFFICIENT_STORAGE:
        return 'Free up storage space and try again.';
      case ProtoErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY:
        return 'Close other applications to free up memory.';
      case ProtoErrorCode.ERROR_CODE_MICROPHONE_PERMISSION_DENIED:
        return 'Grant microphone permission in Settings.';
      case ProtoErrorCode.ERROR_CODE_TIMEOUT:
        return 'Try again or check your connection.';
      case ProtoErrorCode.ERROR_CODE_INVALID_API_KEY:
        return 'Verify your API key is correct.';
      case ProtoErrorCode.ERROR_CODE_CANCELLED:
        return undefined;
      default:
        return undefined;
    }
  }

  /**
   * Log this exception to all configured destinations.
   *
   * Mirrors Swift `SDKException.log(file:line:function:)`
   * (SDKException.swift:362-393): cancellation logs at INFO, everything else
   * at ERROR; metadata carries error_code / error_category / failure_reason /
   * underlying_error plus the top SDK stack frames. Swift's `#file` / `#line`
   * / `#function` source-location metadata has no JS equivalent and is
   * omitted; the JS `Error.stack` replaces `Thread.callStackSymbols`.
   */
  log(): void {
    const metadata: Record<string, unknown> = {
      error_code: errorCodeToJSON(this.proto.code),
      error_category: errorCategoryToJSON(this.proto.category),
    };

    if (this.proto.nestedMessage) {
      metadata.underlying_error = this.proto.nestedMessage;
    }
    // Swift `failureReason` (SDKException.swift:83-85): "[category] code".
    metadata.failure_reason =
      `[${errorCategoryToJSON(this.proto.category)}] ${errorCodeToJSON(this.proto.code)}`;

    // Top SDK frames only (cheap and useful) — Swift filters
    // `Thread.callStackSymbols` for "RunAnywhere"; JS bundles carry the
    // package path in lowercase, so match case-insensitively.
    const sdkFrames = (this.stack ?? '')
      .split('\n')
      .filter((frame) => frame.toLowerCase().includes('runanywhere'))
      .slice(0, 5);
    if (sdkFrames.length > 0) {
      metadata.stack_trace = sdkFrames.join('\n');
    }

    const suffix = Object.entries(metadata)
      .map(([key, value]) => `${key}=${String(value)}`)
      .join(', ');
    const logger = new SDKLogger(errorCategoryToJSON(this.proto.category));
    const line = `${this.proto.message} | ${suffix}`;
    if (this.proto.code === ProtoErrorCode.ERROR_CODE_CANCELLED) {
      logger.info(line);
    } else {
      logger.error(line);
    }
  }

  /** Whether the result code indicates success (code === 0). */
  static isSuccess(resultCode: number): boolean {
    return resultCode === 0;
  }

  /** Build an SDKException from a signed numeric `rac_result_t` code + message.
   * Web-platform-specific WASM bridge primitive — no Swift counterpart by design. */
  static fromCode(code: number, message: string, details?: string): SDKException {
    return new SDKException(code, message, details);
  }

  /**
   * Build an SDKException from a raw `rac_result_t` result code.
   * Web-platform-specific WASM bridge primitive (optional in-process module
   * parameter) — Swift's nearest analog is `SDKException.from(rcResult:)`.
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
   * Throw an `SDKException` if the `rac_result_t` indicates failure; no-op on
   * `RAC_SUCCESS` (0). Mirrors Swift `SDKException.throwIfError(_:)`
   * (RASDKError+Helpers.swift:92-96). The optional `details`/`wasm` arguments
   * follow {@link fromRACResult} so the rac_result_t → proto translation can
   * route through the canonical commons helper when a module is loaded.
   */
  static throwIfError(
    resultCode: number,
    details?: string,
    wasm?: { module: ProtoWasmModule; logger: SDKLogger },
  ): void {
    if (SDKException.isSuccess(resultCode)) return;
    throw SDKException.fromRACResult(resultCode, details, wasm);
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

  /**
   * Generic factory; auto-logs unexpected errors.
   *
   * Mirrors Swift `SDKException.make(code:message:category:underlying:shouldLog:)`
   * (SDKException.swift:154-166): builds the proto envelope with the pinned
   * category, round-trips the C ABI code (positive proto code ↔ negative
   * rac_result_t, capped at raw <= 899), and calls {@link log} unless the
   * code is expected/routine (cancellation) or `shouldLog` is false.
   */
  static make(
    code: ProtoErrorCode,
    message: string,
    category: ProtoErrorCategory = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
    underlying?: Error,
    shouldLog = true,
  ): SDKException {
    const proto: ProtoSDKError = {
      category,
      code,
      // Round-trip C ABI code: positive proto code ↔ negative rac_result_t
      // (Swift caps at raw > 0 && raw <= 899, SDKException.swift:48-51).
      cAbiCode: code > 0 && code <= 899 ? -code : 0,
      message,
      nestedMessage: underlying ? String(underlying) : undefined,
      context: undefined,
      timestampMs: Date.now(),
      severity: severityForCode(-code),
      component: componentForCode(-code),
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    const ex = new SDKException(proto);
    if (shouldLog && !isExpected(code)) {
      ex.log();
    }
    return ex;
  }

  /**
   * Common shortcut: invalid configuration.
   * Mirrors Swift `SDKException.invalidConfiguration(_:)`
   * (SDKException.swift:183-185): code=.invalidConfiguration,
   * category=.configuration.
   */
  static invalidConfiguration(message: string): SDKException {
    return SDKException.make(
      ProtoErrorCode.ERROR_CODE_INVALID_CONFIGURATION,
      message,
      ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
    );
  }

  /**
   * Common shortcut: timeout.
   * Mirrors Swift `SDKException.timeout(_:)` (SDKException.swift:235-237):
   * code=.timeout, category=.network.
   */
  static timeout(message: string): SDKException {
    return SDKException.make(
      ProtoErrorCode.ERROR_CODE_TIMEOUT,
      message,
      ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
    );
  }

  /**
   * Common shortcut: network error.
   * Mirrors Swift `SDKException.networkError(_:)` (SDKException.swift:240-242):
   * code=.networkError, category=.network.
   */
  static networkError(message: string): SDKException {
    return SDKException.make(
      ProtoErrorCode.ERROR_CODE_NETWORK_ERROR,
      message,
      ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
    );
  }

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

  /** Web-platform-specific WASM bridge primitive — no Swift counterpart by design. */
  static wasmNotLoaded(message = 'WASM module not loaded'): SDKException {
    return SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED, message);
  }

  static modelNotFound(modelId: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
      `Model not found: ${modelId}`,
    );
  }

  /** Web-platform-specific backend-registration primitive (V2 split-package
   * WASM loading) — no Swift counterpart by design. */
  static backendNotAvailable(feature: string, details?: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      `Backend not available for: ${feature}`,
      details,
    );
  }

  /**
   * Failed operation.
   *
   * Mirrors the dominant Swift pairing
   * `SDKException(code: .processingFailed, message:, category: .internal)`
   * (CppBridge+NativeProtoABI.swift:76, RunAnywhere+StructuredOutput.swift:149,
   * RunAnywhere+Solutions.swift:110, ...).
   */
  static processingFailed(message: string, details?: string): SDKException {
    const proto: ProtoSDKError = {
      category: ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
      code: ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED,
      message,
      nestedMessage: details,
      context: undefined,
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
      component: componentForCode(-ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED),
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    return new SDKException(proto);
  }

  /**
   * Wrong-state call (operation invoked while the component is in a state
   * that cannot serve it).
   *
   * Swift throws `.invalidState` via the constructor with per-site categories
   * (RunAnywhere+Solutions.swift:101 `.internal`, RunAnywhere+Storage.swift:436
   * `.network`); this factory uses Swift's constructor-default `.component`,
   * which also matches the canonical C++ range table for code 231.
   */
  static invalidState(message: string, details?: string): SDKException {
    const proto: ProtoSDKError = {
      category: ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
      code: ProtoErrorCode.ERROR_CODE_INVALID_STATE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_INVALID_STATE,
      message,
      nestedMessage: details,
      context: undefined,
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
      component: componentForCode(-ProtoErrorCode.ERROR_CODE_INVALID_STATE),
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    return new SDKException(proto);
  }

  /**
   * Required service is missing / could not be brought up.
   *
   * Mirrors Swift `SDKException(code: .serviceNotAvailable, message:,
   * category: .component)` (SystemFoundationModelsService.swift:45,
   * HybridSTTRouter.swift:99 and all other router sites).
   */
  static serviceNotAvailable(message: string, details?: string): SDKException {
    const proto: ProtoSDKError = {
      category: ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
      code: ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
      message,
      nestedMessage: details,
      context: undefined,
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
      component: componentForCode(-ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE),
      retryable: false,
      remediationHint: '',
      correlationId: '',
    };
    return new SDKException(proto);
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
   *
   * The plain-string overload mirrors Swift `validationFailed(_ message:)`
   * (SDKException.swift:188-190): code `.validationFailed`,
   * category `.validation`.
   */
  static validationFailed(message: string): SDKException;
  static validationFailed(args: {
    fieldPath: string;
    message: string;
    cause?: Error;
  }): SDKException;
  static validationFailed(args: string | {
    fieldPath: string;
    message: string;
    cause?: Error;
  }): SDKException {
    if (typeof args === 'string') {
      const proto: ProtoSDKError = {
        category: ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
        code: ProtoErrorCode.ERROR_CODE_VALIDATION_FAILED,
        cAbiCode: -ProtoErrorCode.ERROR_CODE_VALIDATION_FAILED,
        message: args,
        nestedMessage: undefined,
        context: undefined,
        timestampMs: Date.now(),
        severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
        component: 'validation',
        retryable: false,
        remediationHint: '',
        correlationId: '',
      };
      return new SDKException(proto);
    }
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

  /**
   * Map an ONNX Runtime C error code into an SDKException.
   *
   * Verbatim port of Swift `SDKException.fromONNXCode(_:)`
   * (SDKException.swift:299-341): same code→proto-code table, same messages,
   * category pinned to INTERNAL.
   */
  static fromONNXCode(code: number): SDKException {
    let protoCode: ProtoErrorCode;
    let message: string;
    switch (code) {
      case 0:
        protoCode = ProtoErrorCode.ERROR_CODE_UNKNOWN;
        message = 'Unexpected success code passed to error handler';
        break;
      case -1:
        protoCode = ProtoErrorCode.ERROR_CODE_INITIALIZATION_FAILED;
        message = 'ONNX Runtime initialization failed';
        break;
      case -2:
        protoCode = ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED;
        message = 'Failed to load ONNX model';
        break;
      case -3:
        protoCode = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED;
        message = 'ONNX inference failed';
        break;
      case -4:
        protoCode = ProtoErrorCode.ERROR_CODE_INVALID_STATE;
        message = 'Invalid ONNX handle';
        break;
      case -5:
        protoCode = ProtoErrorCode.ERROR_CODE_INVALID_INPUT;
        message = 'Invalid ONNX parameters';
        break;
      case -6:
        protoCode = ProtoErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY;
        message = 'ONNX Runtime out of memory';
        break;
      case -7:
        protoCode = ProtoErrorCode.ERROR_CODE_NOT_IMPLEMENTED;
        message = 'ONNX feature not implemented';
        break;
      case -8:
        protoCode = ProtoErrorCode.ERROR_CODE_CANCELLED;
        message = 'ONNX operation cancelled';
        break;
      case -9:
        protoCode = ProtoErrorCode.ERROR_CODE_TIMEOUT;
        message = 'ONNX operation timed out';
        break;
      case -10:
        protoCode = ProtoErrorCode.ERROR_CODE_STORAGE_ERROR;
        message = 'ONNX IO error';
        break;
      default:
        protoCode = ProtoErrorCode.ERROR_CODE_UNKNOWN;
        message = `ONNX error code: ${code}`;
        break;
    }
    const proto: ProtoSDKError = {
      // Swift pins category .internal for ONNX mapping; the code-range table
      // would derive a per-range category, so construct the proto directly.
      category: ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
      code: protoCode,
      // Round-trip C ABI code: positive proto code ↔ negative rac_result_t
      // (Swift caps at raw <= 899; every code in this table qualifies).
      cAbiCode: -protoCode,
      message,
      nestedMessage: undefined,
      context: undefined,
      timestampMs: Date.now(),
      severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
      component: componentForCode(-protoCode),
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
