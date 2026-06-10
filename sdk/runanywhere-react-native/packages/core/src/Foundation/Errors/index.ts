/**
 * Foundation/Errors
 *
 * `SDKException` (this folder) is the only throwable in `@runanywhere/core`.
 * The proto-encoded `SDKError`, `ErrorCode`, `ErrorCategory`, and
 * `ErrorContext` types live in `@runanywhere/proto-ts/errors`; we re-export
 * them here so consumers have a single import surface.
 */

export type {
  ErrorContext,
  SDKError as SDKErrorProto,
} from '@runanywhere/proto-ts/errors';
export {
  ErrorCategory,
  ErrorCode,
} from '@runanywhere/proto-ts/errors';

export {
  SDKException,
  isSDKException,
  asSDKException,
} from './SDKException';
