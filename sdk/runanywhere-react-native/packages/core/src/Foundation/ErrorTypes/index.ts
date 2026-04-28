/**
 * Foundation/ErrorTypes
 *
 * Wave 2 cleanup: legacy `SDKError` / `ErrorCode` / `ErrorCategory` /
 * `ErrorContext` modules have been deleted. The canonical proto-encoded
 * error shape lives in `@runanywhere/proto-ts/errors` and the throwable
 * wrapper is `SDKException` (this file's only export). Consumers MUST
 * use `SDKException` for all SDK-throw sites and `ErrorCode` /
 * `ErrorCategory` from `@runanywhere/proto-ts/errors` for code-level
 * dispatch.
 */

// Canonical proto error types (re-exported for ergonomic access).
export type {
  ErrorContext,
  SDKError as SDKErrorProto,
} from '@runanywhere/proto-ts/errors';
export {
  ErrorCategory,
  ErrorCode,
} from '@runanywhere/proto-ts/errors';

// SDKException — the only RN throwable wrapper around the proto.
export {
  SDKException,
  isSDKException,
  asSDKException,
} from './SDKException';
