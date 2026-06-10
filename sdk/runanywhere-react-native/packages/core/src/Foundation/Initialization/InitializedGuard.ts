/**
 * InitializedGuard
 *
 * Synchronous Phase-1 readiness gate used by the public extension files.
 *
 * Mirrors Swift's `guard isInitialized else { throw SDKException(code:
 * .notInitialized, message: "SDK not initialized", category: .internal) }`
 * pattern found at nearly every public entry point (e.g.
 * RunAnywhere+TextGeneration.swift:44-46, RunAnywhere+RAG.swift:59-61).
 *
 * Swift reads the static `RunAnywhere.isInitialized` flag directly because
 * all extensions live in the same module. TypeScript extension files are
 * independent modules, so — exactly like `ServicesReadyGuard` — the live
 * flag is registered once by `RunAnywhere.ts` at construction time and read
 * through this indirection, avoiding a circular import.
 */

import { SDKException } from '../Errors/SDKException';
import {
  ErrorCategory as ErrorCategoryProto,
  ErrorCode as ErrorCodeProto,
} from '@runanywhere/proto-ts/errors';

type InitializedProviderFn = () => boolean;

let _isInitialized: InitializedProviderFn | null = null;

/**
 * Called once by `RunAnywhere.ts` to register the live Phase-1 flag reader.
 * Idempotent — re-registering with the same function is a no-op.
 */
export function registerInitializedProvider(fn: InitializedProviderFn): void {
  _isInitialized = fn;
}

/**
 * Whether the SDK completed Phase 1 (core) initialization.
 * Mirrors Swift `RunAnywhere.isInitialized`.
 */
export function isSDKInitialized(): boolean {
  return _isInitialized ? _isInitialized() : false;
}

/**
 * Throw the Swift-shaped not-initialized failure when Phase 1 has not run.
 *
 * Failure shape mirrors the Swift inline guards exactly:
 * `SDKException(code: .notInitialized, message: "SDK not initialized",
 * category: .internal)`.
 */
export function requireInitialized(): void {
  if (!isSDKInitialized()) {
    throw SDKException.of(
      ErrorCodeProto.ERROR_CODE_NOT_INITIALIZED,
      'SDK not initialized',
      { category: ErrorCategoryProto.ERROR_CATEGORY_INTERNAL }
    );
  }
}
