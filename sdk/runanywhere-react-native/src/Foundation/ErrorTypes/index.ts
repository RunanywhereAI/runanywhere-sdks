/**
 * Foundation/ErrorTypes
 *
 * Unified error handling system for the SDK.
 * Matches iOS SDK: Foundation/ErrorTypes/
 */

// Error codes
export { ErrorCode, getErrorCodeMessage } from './ErrorCodes';

// Error categories
export {
  ErrorCategory,
  allErrorCategories,
  getCategoryFromCode,
  inferCategoryFromError,
} from './ErrorCategory';

// Error context
export {
  ErrorContext,
  createErrorContext,
  formatStackTrace,
  formatLocation,
  formatContext,
  ContextualError,
  withContext,
  getErrorContext,
  getUnderlyingError,
} from './ErrorContext';

// SDK Error class and utilities
export {
  // Legacy enum (backwards compatibility)
  SDKErrorCode,
  // Protocol and class
  SDKErrorProtocol,
  SDKError,
  // Utility functions
  asSDKError,
  isSDKError,
  captureAndThrow,
  // Convenience factory functions
  notInitializedError,
  alreadyInitializedError,
  invalidInputError,
  modelNotFoundError,
  modelLoadError,
  networkError,
  authenticationError,
  generationError,
  storageError,
} from './SDKError';
