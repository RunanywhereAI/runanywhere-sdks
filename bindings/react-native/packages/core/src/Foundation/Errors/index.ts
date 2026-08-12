/**
 * Foundation/Errors
 *
 * `SDKException` (this folder) is the only throwable in `@runanywhere/core`.
 * The proto-encoded `SDKError`, `ErrorCode`, and `ErrorCategory` types live
 * in `@runanywhere/proto-ts/errors`; we re-export them here so consumers
 * have a single import surface.
 *
 * `ErrorContext` is deleted outright: `SDKError.param` now carries the
 * "<Message>.<field>" validation field-path string directly (idl comment:
 * "OpenAI's `param`"), replacing the nested `context.fieldPath` accessor.
 */

export type { SDKError as SDKErrorProto } from '@runanywhere/proto-ts/errors';
export {
  ErrorCategory,
  ErrorCode,
} from '@runanywhere/proto-ts/errors';

export {
  SDKException,
  isSDKException,
  asSDKException,
  isExpectedErrorCode,
  sdkExceptionFromRcResult,
  throwIfRcError,
} from './SDKException';
