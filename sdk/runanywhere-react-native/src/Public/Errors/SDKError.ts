/**
 * SDKError.ts
 *
 * Public SDK error types.
 * Re-exports from Foundation/ErrorTypes for consistency.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Errors/RunAnywhereError.swift
 */

// Re-export everything from Foundation/ErrorTypes/SDKError
export {
  // Legacy enum (backwards compatibility)
  SDKErrorCode,
  // SDKError class
  SDKError,
  type SDKErrorProtocol,
  // Utility functions
  asSDKError,
  isSDKError,
  captureAndThrow,
  // Factory functions
  notInitializedError,
  alreadyInitializedError,
  invalidInputError,
  modelNotFoundError,
  modelLoadError,
  networkError,
  authenticationError,
  generationError,
  storageError,
} from '../../Foundation/ErrorTypes/SDKError';

// Re-export error codes and categories
export { ErrorCode, getErrorCodeMessage } from '../../Foundation/ErrorTypes/ErrorCodes';
export { ErrorCategory, getCategoryFromCode } from '../../Foundation/ErrorTypes/ErrorCategory';
