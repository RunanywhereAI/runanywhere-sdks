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

// Error context - Type exports
export type { ErrorContext } from './ErrorContext';

// Error context - Value exports
export {
  createErrorContext,
  formatStackTrace,
  formatLocation,
  formatContext,
  ContextualError,
  withContext,
  getErrorContext,
  getUnderlyingError,
} from './ErrorContext';

// SDK Error - Type exports
export type { SDKErrorProtocol } from './SDKError';

// SDK Error - Value exports
export {
  // Legacy enum (backwards compatibility)
  SDKErrorCode,
  // Class
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
