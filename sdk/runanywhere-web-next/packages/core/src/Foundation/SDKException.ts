import {
  errorCategoryToJSON,
  errorCodeToJSON,
  ErrorCategory as ProtoErrorCategory,
  ErrorCode as ProtoErrorCode,
  ErrorSeverity as ProtoErrorSeverity,
  type SDKError as ProtoSDKError,
} from '@runanywhere/proto-ts/errors';
import { SDKLogger } from './SDKLogger';

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

  get code(): ProtoErrorCode {
    return this.proto.code;
  }

  get cAbiCode(): number {
    return this.proto.cAbiCode ?? 0;
  }

  get fieldPath(): string | undefined {
    const typed = this.proto.context?.fieldPath;
    return typed && typed.length > 0 ? typed : undefined;
  }

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
      default:
        return undefined;
    }
  }

  log(): void {
    const fields: Record<string, unknown> = {
      error_code: errorCodeToJSON(this.proto.code),
      error_category: errorCategoryToJSON(this.proto.category),
      failure_reason: `[${errorCategoryToJSON(this.proto.category)}] ${errorCodeToJSON(this.proto.code)}`,
    };
    if (this.proto.nestedMessage) fields.underlying_error = this.proto.nestedMessage;
    const sdkFrames = (this.stack ?? '')
      .split('\n')
      .filter((frame) => frame.toLowerCase().includes('runanywhere'))
      .slice(0, 5);
    if (sdkFrames.length > 0) fields.stack_trace = sdkFrames.join('\n');

    const logger = new SDKLogger(errorCategoryToJSON(this.proto.category));
    if (this.proto.code === ProtoErrorCode.ERROR_CODE_CANCELLED) {
      logger.info(this.proto.message, fields);
    } else {
      logger.error(this.proto.message, fields);
    }
  }

  static isSuccess(resultCode: number): boolean {
    return resultCode === 0;
  }

  static fromCode(code: number, message: string, details?: string): SDKException {
    return new SDKException(code, message, details);
  }

  static fromRACResult(resultCode: number, details?: string): SDKException {
    const message = details ? `RACommons error: ${resultCode} (${details})` : `RACommons error: ${resultCode}`;
    return SDKException.fromCode(resultCode, message, details);
  }

  static throwIfError(resultCode: number, details?: string): void {
    if (SDKException.isSuccess(resultCode)) return;
    throw SDKException.fromRACResult(resultCode, details);
  }

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
    if (shouldLog && !isExpected(code)) ex.log();
    return ex;
  }

  static invalidConfiguration(message: string): SDKException {
    return SDKException.make(
      ProtoErrorCode.ERROR_CODE_INVALID_CONFIGURATION,
      message,
      ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
    );
  }

  static timeout(message: string): SDKException {
    return SDKException.make(
      ProtoErrorCode.ERROR_CODE_TIMEOUT,
      message,
      ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
    );
  }

  static networkError(message: string): SDKException {
    return SDKException.make(
      ProtoErrorCode.ERROR_CODE_NETWORK_ERROR,
      message,
      ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
    );
  }

  static notInitialized(message = 'SDK not initialized'): SDKException {
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

  static backendNotAvailable(feature: string, details?: string): SDKException {
    return SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      `Backend not available for: ${feature}`,
      details,
    );
  }

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

  static validationFailed(message: string): SDKException;
  static validationFailed(args: { fieldPath: string; message: string; cause?: Error }): SDKException;
  static validationFailed(
    args: string | { fieldPath: string; message: string; cause?: Error },
  ): SDKException {
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
      category: ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
      code: protoCode,
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

export function isSDKException(error: unknown): error is SDKException {
  return error instanceof SDKException;
}

export function isExpected(code: ProtoErrorCode): boolean {
  return code === ProtoErrorCode.ERROR_CODE_CANCELLED || code === ProtoErrorCode.ERROR_CODE_STREAM_CANCELLED;
}

export type {
  ErrorContext as ProtoErrorContext,
  SDKError as ProtoSDKError,
} from '@runanywhere/proto-ts/errors';
export {
  ErrorCategory as ProtoErrorCategory,
  ErrorCode as ProtoErrorCode,
  ErrorSeverity as ProtoErrorSeverity,
} from '@runanywhere/proto-ts/errors';
